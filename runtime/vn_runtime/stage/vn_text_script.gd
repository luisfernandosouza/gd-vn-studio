class_name VNTextScript
extends RefCounted
## Texto de uma fala com a marcação do Data Model §9.1, pronto para a
## digitação (tarefa M2-03; RT §5.2 "Digitação").
##
## [method parse] separa o que aparece (o [member plain] e o [member bbcode] do
## [RichTextLabel]) do que só vale na digitação: [code][pause=s][/code] e
## [code][speed=m]…[/speed][/code]. Só contam os caracteres visíveis: a
## marcação de estilo aparece junto com o primeiro caractere que ela envolve,
## e [code][[[/code] e [code]]][/code] valem um caractere cada.
##
## [method visible_at] diz quantos caracteres já apareceram [code]t[/code]
## segundos depois do começo, para uma velocidade em caracteres por segundo.
## É puro (sem nós), então a linha do tempo é testável sem desenhar nada.

const PAUSE_MAX := 10.0
const SPEED_MIN := 0.1
const SPEED_MAX := 10.0

## Texto visível, sem marcação (colchetes literais já resolvidos).
var plain: String = ""
## Marcação de estilo em BBCode do [RichTextLabel] ([code]b[/code], [code]i[/code], [code]color[/code]).
var bbcode: String = ""
## Pausas: [code][{ at: int, seconds: float }][/code]; [code]at[/code] é o
## número de caracteres visíveis antes da pausa.
var pauses: Array[Dictionary] = []
## Trechos com velocidade própria: [code][{ from: int, to: int, mult: float }][/code]
## ([code]to[/code] exclusivo, em caracteres visíveis).
var speeds: Array[Dictionary] = []


## Analisa [param s]. Marca desconhecida ou com parâmetro inválido é ignorada
## (a validação R018 é do Studio e do compilador; o runtime não quebra).
static func parse(s: String) -> VNTextScript:
	var out := VNTextScript.new()
	var speed_stack: Array[Dictionary] = []   # { from, mult }
	var i := 0
	var n := s.length()
	var visible := 0
	while i < n:
		var c := s[i]
		if c == "[" and s.substr(i, 2) == "[[":
			out.plain += "["
			out.bbcode += "[lb]"
			visible += 1
			i += 2
		elif c == "]" and s.substr(i, 2) == "]]":
			out.plain += "]"
			out.bbcode += "[rb]"
			visible += 1
			i += 2
		elif c == "[":
			var close := s.find("]", i)
			if close < 0:
				out.plain += "["
				out.bbcode += "[lb]"
				visible += 1
				i += 1
				continue
			var tag := s.substr(i + 1, close - i - 1)
			var closing := tag.begins_with("/")
			var name := tag.trim_prefix("/").get_slice("=", 0)
			var arg := tag.get_slice("=", 1) if tag.contains("=") else ""
			match name:
				"b", "i":
					out.bbcode += "[%s]" % tag
				"color":
					if closing or not arg.is_empty():
						out.bbcode += "[%s]" % tag
				"pause":
					if not closing and arg.is_valid_float():
						out.pauses.append({"at": visible, "seconds": clampf(arg.to_float(), 0.0, PAUSE_MAX)})
				"speed":
					if closing:
						if not speed_stack.is_empty():
							var top: Dictionary = speed_stack.pop_back()
							out._add_speed(top.from, visible, top.mult)
					elif arg.is_valid_float() and arg.to_float() > 0.0:
						speed_stack.append({"from": visible, "mult": clampf(arg.to_float(), SPEED_MIN, SPEED_MAX)})
			i = close + 1
		elif c == "]":
			out.plain += "]"
			out.bbcode += "[rb]"
			visible += 1
			i += 1
		else:
			out.plain += c
			out.bbcode += c
			visible += 1
			i += 1
	# [speed] sem fechar vale até o fim.
	while not speed_stack.is_empty():
		var top: Dictionary = speed_stack.pop_back()
		out._add_speed(top.from, visible, top.mult)
	return out


func _add_speed(from: int, to: int, mult: float) -> void:
	if to > from:
		speeds.append({"from": from, "to": to, "mult": mult})


## Número de caracteres visíveis.
func length() -> int:
	return plain.length()


## Multiplicador de velocidade do caractere [param index] (marcas aninhadas se multiplicam).
func speed_of(index: int) -> float:
	var m := 1.0
	for sp in speeds:
		if index >= sp.from and index < sp.to:
			m *= sp.mult
	return m


## Instante em que cada caractere termina de aparecer, em segundos, para
## [param cps] caracteres por segundo. [param use_speed] liga os
## [code][speed][/code] (desligados com [code]reduce_motion[/code], Req §12);
## [code][pause][/code] vale sempre. Com [code]cps <= 0[/code] a fala inteira
## aparece de uma vez e a lista fica vazia.
func timeline(cps: float, use_speed: bool = true) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if cps <= 0.0:
		return out
	var t := 0.0
	var pi := 0
	for i in range(plain.length()):
		while pi < pauses.size() and pauses[pi].at <= i:
			t += pauses[pi].seconds
			pi += 1
		t += 1.0 / (cps * (speed_of(i) if use_speed else 1.0))
		out.append(t)
	return out


## Duração total da digitação (inclui pausas no fim do texto).
func duration(cps: float, use_speed: bool = true) -> float:
	if cps <= 0.0:
		return 0.0
	var tl := timeline(cps, use_speed)
	var t := tl[tl.size() - 1] if tl.size() > 0 else 0.0
	for p in pauses:
		if p.at >= plain.length():
			t += p.seconds
	return t


## Quantos caracteres já apareceram em [param t] segundos, dada a linha do tempo.
static func visible_at(tl: PackedFloat32Array, t: float, total: int) -> int:
	if tl.is_empty():
		return total
	var lo := 0
	var hi := tl.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if tl[mid] <= t:
			lo = mid + 1
		else:
			hi = mid
	return lo
