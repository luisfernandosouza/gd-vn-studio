class_name VNUIText
extends RefCounted
## Textos das telas: caminho de tradução, interpolação e marcação (UI Spec
## §3.3; Data Model §9, §9.1; RT §12.1).
##
## O texto de um elemento vem de [code]locales/<idioma>.json[/code] pelo
## caminho [code]ui/<tela>/<elemento>…[/code]; sem tradução, vale o texto do
## bundle (idioma-fonte). A interpolação [code]{global.x}[/code] acontece antes
## da marcação e o valor interpolado é escapado. [code]{{[/code] e
## [code]}}[/code] são chaves literais.

## Formato de número por idioma (RT §12.1): decimal, milhar, mínimo de dígitos
## da parte inteira para usar o separador de milhar.
const NUMBER_FORMATS := {
	"en": {"decimal": ".", "group": ",", "min_grouping": 4},
	"ja": {"decimal": ".", "group": ",", "min_grouping": 4},
	"zh-Hans": {"decimal": ".", "group": ",", "min_grouping": 4},
	"zh-Hant": {"decimal": ".", "group": ",", "min_grouping": 4},
	"pt-BR": {"decimal": ",", "group": ".", "min_grouping": 4},
	"it": {"decimal": ",", "group": ".", "min_grouping": 4},
	"de": {"decimal": ",", "group": ".", "min_grouping": 4},
	"es": {"decimal": ",", "group": ".", "min_grouping": 5},
	"fr": {"decimal": ",", "group": " ", "min_grouping": 4},
}

## Traduções do idioma atual: caminho → texto.
var strings: Dictionary = {}
## Idioma atual (tag BCP 47).
var locale: String = "en"
## [code]project.json → settings.number_formats[/code].
var number_formats: Dictionary = {}
## Lê uma variável para a interpolação: [code]func(id: String) -> Variant[/code].
var reader: Callable = Callable()


## Texto do caminho, ou [param fallback] sem tradução; já interpolado.
func text(path: String, fallback: String = "") -> String:
	var raw: String = strings.get(path, fallback)
	return interpolate(raw)


## Texto cru (sem interpolação) do caminho.
func raw(path: String, fallback: String = "") -> String:
	return strings.get(path, fallback)


## Troca [code]{variavel}[/code] pelo valor formatado e escapado para a marcação.
func interpolate(s: String) -> String:
	if not s.contains("{") and not s.contains("}"):
		return s
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		var c := s[i]
		if c == "{" and i + 1 < n and s[i + 1] == "{":
			out += "{"
			i += 2
		elif c == "}" and i + 1 < n and s[i + 1] == "}":
			out += "}"
			i += 2
		elif c == "{":
			var close := s.find("}", i)
			if close < 0:
				out += s.substr(i)
				break
			var id := s.substr(i + 1, close - i - 1).strip_edges()
			var v: Variant = reader.call(id) if reader.is_valid() else null
			out += escape_markup(format_value(v))
			i = close + 1
		else:
			out += c
			i += 1
	return out


## Valor de variável como texto: inteiros sem casa decimal, números no formato do idioma.
func format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return format_number(float(v))
		TYPE_FLOAT:
			return format_number(v)
	return str(v)


## Número com até 2 casas, sem zeros à direita, separadores do idioma (RT §12.1).
func format_number(x: float) -> String:
	var fmt := _format_for(locale)
	var rounded := _round_half_away(x, 2)
	var neg := rounded < 0.0
	var a := absf(rounded)
	var int_part := int(floor(a))
	var frac := int(round((a - float(int_part)) * 100.0))
	if frac >= 100:
		int_part += 1
		frac -= 100
	var digits := str(int_part)
	var grouped := digits
	if not String(fmt.group).is_empty() and digits.length() >= int(fmt.min_grouping):
		grouped = ""
		var count := 0
		for k in range(digits.length() - 1, -1, -1):
			grouped = digits[k] + grouped
			count += 1
			if count % 3 == 0 and k > 0:
				grouped = String(fmt.group) + grouped
	var out := grouped
	if frac > 0:
		var f := "%02d" % frac
		if f.ends_with("0"):
			f = f.left(1)
		out += String(fmt.decimal) + f
	if neg and (int_part != 0 or frac != 0):
		out = "-" + out
	return out


func _format_for(tag: String) -> Dictionary:
	if number_formats.has(tag):
		return _with_defaults(number_formats[tag])
	if NUMBER_FORMATS.has(tag):
		return NUMBER_FORMATS[tag]
	var base := tag.get_slice("-", 0)
	if number_formats.has(base):
		return _with_defaults(number_formats[base])
	return NUMBER_FORMATS.get(base, NUMBER_FORMATS.en)


static func _with_defaults(f: Dictionary) -> Dictionary:
	return {"decimal": f.get("decimal", "."), "group": f.get("group", ""), "min_grouping": f.get("min_grouping", 4)}


static func _round_half_away(x: float, places: int) -> float:
	# Arredonda sobre a representação decimal mais curta (1.005 → 1.01).
	var s := String.num(x, 15)
	var dot := s.find(".")
	if dot < 0 or s.length() - dot - 1 <= places:
		return x
	var keep := s.left(dot + 1 + places)
	var next_digit := int(s[dot + 1 + places])
	var base := keep.to_float()
	if next_digit >= 5:
		var step := pow(10.0, -places)
		base = base + step if x >= 0.0 else base - step
	return snappedf(base, pow(10.0, -places))


## Escapa colchetes vindos de variável ([code][[/code], [code]]][/code]).
static func escape_markup(s: String) -> String:
	return s.replace("[", "[[").replace("]", "]]")


## Converte a marcação do Data Model §9.1 em BBCode do [RichTextLabel].
## [code]pause[/code] e [code]speed[/code] só valem na digitação e somem aqui.
static func to_bbcode(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		if s.substr(i, 2) == "[[":
			out += "[lb]"
			i += 2
		elif s.substr(i, 2) == "]]":
			out += "[rb]"
			i += 2
		elif s[i] == "[":
			var close := s.find("]", i)
			if close < 0:
				out += "[lb]"
				i += 1
				continue
			var tag := s.substr(i + 1, close - i - 1)
			var name := tag.get_slice("=", 0).trim_prefix("/")
			if name in ["b", "i"] or (name == "color" and (tag.begins_with("/") or tag.contains("="))):
				out += "[%s]" % tag
			# pause, speed e marcas desconhecidas não aparecem
			i = close + 1
		elif s[i] == "]":
			out += "[rb]"
			i += 1
		else:
			out += s[i]
			i += 1
	return out


## Texto puro, sem marcação (botões e rótulos de controles).
static func strip_markup(s: String) -> String:
	var out := ""
	var i := 0
	var n := s.length()
	while i < n:
		if s.substr(i, 2) == "[[":
			out += "["
			i += 2
		elif s.substr(i, 2) == "]]":
			out += "]"
			i += 2
		elif s[i] == "[":
			var close := s.find("]", i)
			if close < 0:
				out += s.substr(i)
				break
			i = close + 1
		else:
			out += s[i]
			i += 1
	return out
