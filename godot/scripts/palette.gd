class_name Palette
extends RefCounted
## Colours, fonts and style helpers shared by the whole game.

const BG := Color(1.0, 0.957, 0.902)            # warm page
const INK := Color(0.114, 0.106, 0.184)
const MUTED := Color(0.467, 0.439, 0.541)
const CARD := Color(1, 1, 1)
const LINE := Color(0.945, 0.875, 0.796)
const BOARD := Color(0.078, 0.106, 0.188)        # navy board
const MINT := Color(0.125, 0.788, 0.592)
const MINT_INK := Color(0.024, 0.157, 0.122)
const OFF := Color(0.91, 0.349, 0.047)           # "off script" orange
const GOLD := Color(1.0, 0.831, 0.231)
const TILE_INK := Color(0.114, 0.106, 0.184)
const TILES: Array[Color] = [
	Color(1.0, 0.529, 0.529),   # coral
	Color(1.0, 0.663, 0.302),   # orange
	Color(1.0, 0.831, 0.231),   # yellow
	Color(0.455, 0.753, 0.988), # sky
	Color(0.694, 0.592, 0.988), # violet
	Color(0.98, 0.635, 0.757),  # pink
]

const FONT_BOLD := preload("res://fonts/Inter-Bold.otf")
const FONT_SEMI := preload("res://fonts/Inter-SemiBold.otf")
const FONT_BLACK := preload("res://fonts/Inter-ExtraBold.otf")


static func tile_color(ch: String) -> Color:
	return TILES[(ch.unicode_at(0) * 7) % TILES.size()]


static func box(bg: Color, radius: int, pad := Vector2(0, 0), border := 0, border_color := Color.TRANSPARENT,
		bottom := 0, bottom_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	if bottom > 0:
		sb.border_width_bottom = bottom
		sb.border_color = bottom_color
	sb.anti_aliasing = true
	return sb
