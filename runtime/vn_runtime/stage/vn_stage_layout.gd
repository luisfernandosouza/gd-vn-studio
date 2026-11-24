class_name VNStageLayout
extends RefCounted
## Contas de posição do palco (RT §1.1, DM §10.2), sem nós: o Stage usa estas
## funções para desenhar, e os testes as usam para conferir as posições.
##
## Tudo está em pixels da resolução base ([code]project.json → settings.resolution[/code]).
## Com [code]stretch_mode = canvas_items[/code] e [code]stretch_aspect = expand[/code],
## o Godot escala a tela inteira e aumenta a área visível no eixo que sobra; o
## Stage põe a área base no centro da área visível ([method base_offset]) e
## estende o cenário até as bordas da janela ([method cover_rect]).

## Nomes de [code]show.position[/code] e a fração da largura de cada um (DM §10.2).
const POSITIONS := {
	"far_left": 0.1,
	"left": 0.25,
	"center": 0.5,
	"right": 0.75,
	"far_right": 0.9,
}

## Âncora padrão de um sprite: centro dos pés (DM §10.2, [code]assets.schema.json[/code]).
const DEFAULT_ANCHOR := Vector2(0.5, 1.0)


## A fração da largura de uma [code]position[/code] (nome ou número de 0 a 1).
## Valor desconhecido vale [code]center[/code].
static func position_fraction(position: Variant) -> float:
	if position is float or position is int:
		return clampf(float(position), 0.0, 1.0)
	if position is String or position is StringName:
		return POSITIONS.get(String(position), 0.5)
	return 0.5


## Deslocamento da área base dentro da área visível: a área base fica centrada
## (RT §1.1). Numa janela 21:9 com base 1920×1080, a área visível é 2520×1080 e
## o deslocamento é (300, 0).
static func base_offset(base: Vector2, visible: Vector2) -> Vector2:
	return ((visible - base) / 2.0).round()


## O ponto do palco onde fica a âncora de uma personagem, em coordenadas da
## área base: a posição horizontal escolhida e a base da tela (DM §10.2).
static func character_point(base: Vector2, position: Variant) -> Vector2:
	return Vector2(round(base.x * position_fraction(position)), base.y)


## O retângulo do sprite, em coordenadas da área base, com a âncora em
## [param point] e a escala do asset.
static func sprite_rect(point: Vector2, texture_size: Vector2, anchor: Vector2, scale: float) -> Rect2:
	var size := texture_size * scale
	return Rect2(point - anchor * size, size)


## Escala e retângulo que cobrem a área visível inteira com uma imagem, sem
## deformar e centrada na área base ("a sobra mostra o cenário estendido", RT §1.1).
## Em coordenadas da área base: o retângulo pode começar em x ou y negativos.
## Devolve [code]{ "scale": float, "rect": Rect2 }[/code].
static func cover_rect(base: Vector2, visible: Vector2, texture_size: Vector2) -> Dictionary:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return {"scale": 1.0, "rect": Rect2(-base_offset(base, visible), visible)}
	var s := maxf(visible.x / texture_size.x, visible.y / texture_size.y)
	var size := texture_size * s
	var center := base / 2.0
	return {"scale": s, "rect": Rect2(center - size / 2.0, size)}


## A área visível em coordenadas da área base.
static func visible_rect(base: Vector2, visible: Vector2) -> Rect2:
	return Rect2(-base_offset(base, visible), visible)


## Anchor de [code]assets.json[/code] como [Vector2] (padrão: centro dos pés).
static func anchor_of(meta: Dictionary) -> Vector2:
	var a: Variant = meta.get("anchor")
	if a is Array and a.size() == 2:
		return Vector2(float(a[0]), float(a[1]))
	return DEFAULT_ANCHOR


## Scale de [code]assets.json[/code] (padrão 1.0).
static func scale_of(meta: Dictionary) -> float:
	var s: Variant = meta.get("scale")
	return float(s) if (s is float or s is int) and float(s) > 0.0 else 1.0
