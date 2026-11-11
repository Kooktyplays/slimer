extends Node2D
## The arc a melee swing leaves behind: a crescent that sweeps across the cut
## and fades, so the player can see exactly what the swing covered.
##
## Drawn, not a sprite - the arc's angle and reach change with upgrades, and a
## texture would have to be stretched to match. Drawn on whole art pixels
## (PIXEL) so it sits in the same pixel grid as the sprites around it.

const PIXEL := 2.0
const LIFE := 0.20

var _angle := 0.0
var _arc := 1.0
var _reach := 120.0
var _color := Color.WHITE
var _thrust := false
var _t := 0.0


func play(at: Vector2, angle: float, arc: float, reach: float, color: Color,
		thrust: bool) -> void:
	global_position = at
	_angle = angle
	_arc = arc
	_reach = reach
	_color = color
	_thrust = thrust
	_t = 0.0
	z_index = 40
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / LIFE, 0.0, 1.0)
	var col := _color
	col.a = (1.0 - k) * 0.85
	if _thrust:
		# a narrow streak that shoots out to full reach
		var length := _reach * (0.35 + 0.65 * minf(k * 2.5, 1.0))
		var width := maxf(PIXEL * 2.0, 18.0 * (1.0 - k))
		var dir := Vector2.RIGHT.rotated(_angle)
		var side := dir.orthogonal() * width * 0.5
		var tip := dir * length
		draw_colored_polygon(PackedVector2Array([
			_snap(side), _snap(tip), _snap(-side)]), col)
		return
	# a crescent: the leading edge sweeps across the arc as it fades
	var steps := 18
	var sweep := minf(k * 2.2, 1.0)
	var start := _angle - _arc * 0.5
	var end := start + _arc * sweep
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(start, end, float(i) / steps)
		var thick := 0.30 * sin(PI * float(i) / steps) + 0.05
		outer.append(_snap(Vector2.RIGHT.rotated(a) * _reach))
		inner.append(_snap(Vector2.RIGHT.rotated(a) * _reach * (1.0 - thick)))
	inner.reverse()
	outer.append_array(inner)
	draw_colored_polygon(outer, col)


func _snap(p: Vector2) -> Vector2:
	return (p / PIXEL).round() * PIXEL
