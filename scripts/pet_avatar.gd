extends Control
class_name PetAvatar
## Cartoon pet renderer and reactions for Save the Pet mode.

const PET_IDS := ["cat", "dog", "parrot", "fish", "hamster"]
const MOOD_IDLE := "idle"
const MOOD_HAPPY := "happy"
const MOOD_WORRIED := "worried"
const MOOD_SAVED := "saved"
const MOOD_LOST := "lost"

const OUTLINE := Color("#273044")
const SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const WHITE := Color("#fff8ec")
const BLUSH := Color("#ff9eb3")
const TEAR := Color("#7fd7ff")
const SPARK := Color("#ffe77a")

var pet_id: String = "cat"

var _mood: String = MOOD_IDLE
var _time := 0.0
var _shake_offset := 0.0
var _reaction_token := 0
var _final_locked := false
var _reaction_tween: Tween
var _correct_count := 0
var _goal := 1
var _wrong_count := 0
var _max_wrong := 1


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(180, 144)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	pivot_offset = size * 0.5
	queue_redraw()


func set_pet(id: String) -> void:
	pet_id = id if PET_IDS.has(id) else "cat"
	queue_redraw()


func set_progress(correct: int, goal: int, wrong: int, max_wrong: int) -> void:
	_correct_count = max(correct, 0)
	_goal = max(goal, 1)
	_wrong_count = max(wrong, 0)
	_max_wrong = max(max_wrong, 1)
	queue_redraw()


func progress_ratio() -> float:
	return clampf(float(_correct_count) / float(_goal), 0.0, 1.0)


func react_correct(correct: int, goal: int) -> void:
	if _final_locked:
		return
	_correct_count = max(correct, 0)
	_goal = max(goal, 1)
	_mood = MOOD_HAPPY
	_reaction_token += 1
	_play_happy_tween()
	_return_to_idle_after(_reaction_token, 0.95)


func react_wrong(wrong: int, max_wrong: int) -> void:
	if _final_locked:
		return
	_wrong_count = max(wrong, 0)
	_max_wrong = max(max_wrong, 1)
	_mood = MOOD_WORRIED
	_reaction_token += 1
	_play_wrong_tween()
	_return_to_idle_after(_reaction_token, 1.2)


func set_final_state(saved: bool) -> void:
	_final_locked = true
	_mood = MOOD_SAVED if saved else MOOD_LOST
	_shake_offset = 0.0
	_reaction_token += 1
	if _reaction_tween != null:
		_reaction_tween.kill()
	_reaction_tween = null
	scale = Vector2.ONE
	queue_redraw()


func _return_to_idle_after(token: int, seconds: float) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout
	if token == _reaction_token and not _final_locked:
		_mood = MOOD_IDLE
		queue_redraw()


func _play_happy_tween() -> void:
	if not is_inside_tree():
		return
	_reset_tween()
	scale = Vector2.ONE
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(self, "scale", Vector2(1.08, 0.94), 0.08)
	_reaction_tween.tween_property(self, "scale", Vector2(0.96, 1.08), 0.11)
	_reaction_tween.tween_property(self, "scale", Vector2.ONE, 0.14)


func _play_wrong_tween() -> void:
	if not is_inside_tree():
		return
	_reset_tween()
	scale = Vector2.ONE
	_shake_offset = 0.0
	_reaction_tween = create_tween()
	_reaction_tween.tween_property(self, "_shake_offset", -8.0, 0.05)
	_reaction_tween.tween_property(self, "_shake_offset", 8.0, 0.05)
	_reaction_tween.tween_property(self, "_shake_offset", -5.0, 0.05)
	_reaction_tween.tween_property(self, "_shake_offset", 5.0, 0.05)
	_reaction_tween.tween_property(self, "_shake_offset", 0.0, 0.08)


func _reset_tween() -> void:
	if _reaction_tween != null:
		_reaction_tween.kill()
	_reaction_tween = null


func _draw() -> void:
	var s: float = min(size.x / 210.0, size.y / 166.0)
	var bob := sin(_time * 3.0) * 2.6
	var center := Vector2(size.x * 0.5 + _shake_offset, size.y * 0.48 + bob)

	draw_set_transform(center, 0.0, Vector2(s, s))
	_draw_ellipse_shape(Vector2(0, 54), Vector2(64, 10), SHADOW, false)
	match pet_id:
		"dog":
			_draw_dog()
		"parrot":
			_draw_parrot()
		"fish":
			_draw_fish()
		"hamster":
			_draw_hamster()
		_:
			_draw_cat()
	if _mood == MOOD_HAPPY or _mood == MOOD_SAVED:
		_draw_sparkles()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_progress()


func _draw_cat() -> void:
	var body := Color("#f3bc63")
	var body_dark := Color("#da9246")
	var inner := Color("#ffd1c8")
	var face := Vector2(0, -18)

	draw_arc(Vector2(42, 26), 30, deg_to_rad(-95), deg_to_rad(130), 24, OUTLINE, 12.0, true)
	draw_arc(Vector2(42, 26), 30, deg_to_rad(-95), deg_to_rad(130), 24, body_dark, 8.0, true)
	draw_poly([Vector2(-34, -42), Vector2(-50, -78), Vector2(-10, -55)], body)
	draw_poly([Vector2(34, -42), Vector2(50, -78), Vector2(10, -55)], body)
	draw_poly([Vector2(-34, -48), Vector2(-43, -67), Vector2(-16, -55)], inner, false)
	draw_poly([Vector2(34, -48), Vector2(43, -67), Vector2(16, -55)], inner, false)
	_draw_ellipse_shape(Vector2(0, 26), Vector2(46, 36), body)
	draw_circle(Vector2(0, -22), 45, OUTLINE)
	draw_circle(Vector2(0, -22), 41, body)
	_draw_ellipse_shape(Vector2(0, -10), Vector2(18, 13), body.lightened(0.22), false)
	draw_circle(Vector2(-22, 54), 10, OUTLINE)
	draw_circle(Vector2(-22, 54), 7, body.lightened(0.1))
	draw_circle(Vector2(22, 54), 10, OUTLINE)
	draw_circle(Vector2(22, 54), 7, body.lightened(0.1))
	draw_line(Vector2(-24, -14), Vector2(-54, -18), OUTLINE, 2.0, true)
	draw_line(Vector2(-24, -8), Vector2(-55, -6), OUTLINE, 2.0, true)
	draw_line(Vector2(24, -14), Vector2(54, -18), OUTLINE, 2.0, true)
	draw_line(Vector2(24, -8), Vector2(55, -6), OUTLINE, 2.0, true)
	_draw_face(face, 1.0)


func _draw_dog() -> void:
	var body := Color("#c98249")
	var ear := Color("#7a4a32")
	var muzzle := Color("#ffe0b7")
	var face := Vector2(0, -17)

	draw_arc(Vector2(44, 30), 22, deg_to_rad(-65), deg_to_rad(85), 18, OUTLINE, 11.0, true)
	draw_arc(Vector2(44, 30), 22, deg_to_rad(-65), deg_to_rad(85), 18, body, 7.0, true)
	_draw_ellipse_shape(Vector2(0, 28), Vector2(44, 34), body)
	_draw_ellipse_shape(Vector2(-37, -18), Vector2(17, 36), ear)
	_draw_ellipse_shape(Vector2(37, -18), Vector2(17, 36), ear)
	draw_circle(Vector2(0, -25), 43, OUTLINE)
	draw_circle(Vector2(0, -25), 39, body)
	_draw_ellipse_shape(Vector2(0, -8), Vector2(21, 16), muzzle, false)
	draw_circle(Vector2(0, -17), 6, OUTLINE)
	draw_circle(Vector2(-22, 54), 10, OUTLINE)
	draw_circle(Vector2(-22, 54), 7, body.lightened(0.15))
	draw_circle(Vector2(22, 54), 10, OUTLINE)
	draw_circle(Vector2(22, 54), 7, body.lightened(0.15))
	_draw_face(face, 0.98)


func _draw_parrot() -> void:
	var body := Color("#46c885")
	var wing := Color("#1f9fba")
	var head := Color("#72dd91")
	var beak := Color("#ffbf3f")
	var face := Vector2(5, -27)

	draw_poly([Vector2(-14, 34), Vector2(-36, 76), Vector2(-4, 56)], Color("#2b8f6d"))
	draw_poly([Vector2(12, 34), Vector2(40, 74), Vector2(15, 55)], Color("#2f7fc9"))
	_draw_ellipse_shape(Vector2(0, 24), Vector2(39, 45), body)
	_draw_ellipse_shape(Vector2(-9, 25), Vector2(20, 32), wing)
	draw_circle(Vector2(0, -29), 39, OUTLINE)
	draw_circle(Vector2(0, -29), 35, head)
	draw_poly([Vector2(31, -28), Vector2(57, -18), Vector2(31, -7)], beak)
	draw_poly([Vector2(-18, -59), Vector2(-8, -85), Vector2(2, -57)], Color("#ff5d5d"))
	draw_poly([Vector2(-2, -59), Vector2(10, -84), Vector2(13, -55)], Color("#ff9900"))
	draw_circle(Vector2(-18, 61), 8, OUTLINE)
	draw_circle(Vector2(-18, 61), 5, Color("#ffbf3f"))
	draw_circle(Vector2(18, 61), 8, OUTLINE)
	draw_circle(Vector2(18, 61), 5, Color("#ffbf3f"))
	_draw_face(face, 0.9)


func _draw_fish() -> void:
	var body := Color("#5bc7ff")
	var fin := Color("#ff9900")
	var belly := Color("#b9efff")
	var face := Vector2(16, -12)

	draw_poly([Vector2(-44, -8), Vector2(-76, -33), Vector2(-69, 0), Vector2(-76, 33), Vector2(-44, 8)], fin)
	_draw_ellipse_shape(Vector2(0, 0), Vector2(58, 35), body)
	_draw_ellipse_shape(Vector2(6, 8), Vector2(36, 17), belly, false)
	draw_poly([Vector2(-5, -27), Vector2(15, -57), Vector2(26, -21)], fin)
	draw_poly([Vector2(-3, 27), Vector2(18, 55), Vector2(26, 21)], fin)
	draw_line(Vector2(32, -24), Vector2(45, -13), OUTLINE, 2.0, true)
	draw_line(Vector2(36, 23), Vector2(48, 8), OUTLINE, 2.0, true)
	_draw_face(face, 0.92)


func _draw_hamster() -> void:
	var body := Color("#e3a96b")
	var belly := Color("#ffe9c9")
	var ear := Color("#caa17a")
	var face := Vector2(0, -14)

	draw_circle(Vector2(-20, 54), 9, OUTLINE)
	draw_circle(Vector2(-20, 54), 6, body.lightened(0.12))
	draw_circle(Vector2(20, 54), 9, OUTLINE)
	draw_circle(Vector2(20, 54), 6, body.lightened(0.12))
	_draw_ellipse_shape(Vector2(0, 22), Vector2(50, 42), body)
	_draw_ellipse_shape(Vector2(0, 30), Vector2(30, 26), belly, false)
	draw_circle(Vector2(-26, -40), 14, OUTLINE)
	draw_circle(Vector2(-26, -40), 10, ear)
	draw_circle(Vector2(26, -40), 14, OUTLINE)
	draw_circle(Vector2(26, -40), 10, ear)
	draw_circle(Vector2(0, -16), 42, OUTLINE)
	draw_circle(Vector2(0, -16), 38, body)
	_draw_ellipse_shape(Vector2(-30, -2), Vector2(16, 14), body.lightened(0.1), false)
	_draw_ellipse_shape(Vector2(30, -2), Vector2(16, 14), body.lightened(0.1), false)
	_draw_ellipse_shape(Vector2(0, -4), Vector2(13, 10), belly, false)
	draw_circle(Vector2(0, -10), 4, OUTLINE)
	_draw_face(face, 0.92)


func _draw_face(face: Vector2, face_scale: float) -> void:
	var blink := _is_blinking() and _mood == MOOD_IDLE
	var left := face + Vector2(-15, -7) * face_scale
	var right := face + Vector2(15, -7) * face_scale
	var mouth := face + Vector2(0, 11) * face_scale

	match _mood:
		MOOD_HAPPY:
			_draw_happy_eye(left, face_scale)
			_draw_happy_eye(right, face_scale)
			_draw_smile(mouth, 14.0 * face_scale, 4.0)
			draw_circle(face + Vector2(-29, 8) * face_scale, 5.0 * face_scale, BLUSH)
			draw_circle(face + Vector2(29, 8) * face_scale, 5.0 * face_scale, BLUSH)
		MOOD_WORRIED:
			_draw_open_eye(left, 6.5 * face_scale, Vector2(-1, 2) * face_scale)
			_draw_open_eye(right, 6.5 * face_scale, Vector2(1, 2) * face_scale)
			_draw_frown(mouth + Vector2(0, 4) * face_scale, 10.0 * face_scale, 3.0)
			draw_circle(right + Vector2(8, 11) * face_scale, 3.0 * face_scale, TEAR)
		MOOD_SAVED:
			_draw_star(left, 8.0 * face_scale, SPARK)
			_draw_star(right, 8.0 * face_scale, SPARK)
			_draw_smile(mouth, 16.0 * face_scale, 4.0)
			_draw_heart(face + Vector2(0, -42) * face_scale, 8.0 * face_scale)
		MOOD_LOST:
			_draw_x_eye(left, face_scale)
			_draw_x_eye(right, face_scale)
			_draw_frown(mouth + Vector2(0, 4) * face_scale, 13.0 * face_scale, 3.5)
		_:
			if blink:
				draw_line(left + Vector2(-7, 0) * face_scale, left + Vector2(7, 0) * face_scale, OUTLINE, 3.0, true)
				draw_line(right + Vector2(-7, 0) * face_scale, right + Vector2(7, 0) * face_scale, OUTLINE, 3.0, true)
			else:
				_draw_open_eye(left, 6.0 * face_scale, Vector2.ZERO)
				_draw_open_eye(right, 6.0 * face_scale, Vector2.ZERO)
			_draw_smile(mouth, 9.5 * face_scale, 2.5)


func _is_blinking() -> bool:
	return fmod(_time, 3.7) > 3.55


func _draw_open_eye(pos: Vector2, radius: float, pupil_offset: Vector2) -> void:
	draw_circle(pos, radius + 2.0, OUTLINE)
	draw_circle(pos, radius, WHITE)
	draw_circle(pos + pupil_offset, radius * 0.48, OUTLINE)
	draw_circle(pos + pupil_offset + Vector2(-radius * 0.18, -radius * 0.18), radius * 0.16, WHITE)


func _draw_happy_eye(pos: Vector2, face_scale: float) -> void:
	draw_arc(pos, 7.0 * face_scale, 0.0, PI, 12, OUTLINE, 3.0, true)


func _draw_x_eye(pos: Vector2, face_scale: float) -> void:
	var r := 7.0 * face_scale
	draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), OUTLINE, 3.0, true)
	draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), OUTLINE, 3.0, true)


func _draw_smile(pos: Vector2, radius: float, width: float) -> void:
	draw_arc(pos, radius, 0.0, PI, 18, OUTLINE, width, true)


func _draw_frown(pos: Vector2, radius: float, width: float) -> void:
	draw_arc(pos, radius, PI, TAU, 18, OUTLINE, width, true)


func _draw_sparkles() -> void:
	_draw_star(Vector2(-70, -52), 7.0, SPARK)
	_draw_star(Vector2(66, -43), 5.5, WHITE)
	_draw_star(Vector2(58, 30), 4.0, SPARK)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), color, 2.2, true)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), color, 2.2, true)
	draw_line(center + Vector2(-radius * 0.65, -radius * 0.65), center + Vector2(radius * 0.65, radius * 0.65), color, 1.5, true)
	draw_line(center + Vector2(-radius * 0.65, radius * 0.65), center + Vector2(radius * 0.65, -radius * 0.65), color, 1.5, true)


func _draw_heart(center: Vector2, radius: float) -> void:
	var color := Color("#ff5d8f")
	draw_circle(center + Vector2(-radius * 0.45, -radius * 0.15), radius * 0.55, color)
	draw_circle(center + Vector2(radius * 0.45, -radius * 0.15), radius * 0.55, color)
	draw_poly([
		center + Vector2(-radius, -radius * 0.05),
		center + Vector2(radius, -radius * 0.05),
		center + Vector2(0, radius * 1.2),
	], color, false)


func _draw_progress() -> void:
	var track_w: float = min(size.x * 0.68, 150.0)
	var track_pos := Vector2((size.x - track_w) * 0.5, size.y - 11.0)
	var track := Rect2(track_pos, Vector2(track_w, 5.0))
	draw_rect(track, Color("#242d4a"), true)
	draw_rect(Rect2(track.position, Vector2(track.size.x * progress_ratio(), track.size.y)), Color("#3ecf8e"), true)

	var strike_gap := 12.0
	var strikes_w := float(_max_wrong - 1) * strike_gap
	var strike_start := Vector2((size.x - strikes_w) * 0.5, size.y - 25.0)
	for i in range(_max_wrong):
		var used := i < _wrong_count
		draw_circle(strike_start + Vector2(float(i) * strike_gap, 0), 4.0, Color("#ff5d5d") if used else Color("#39435f"))


func _draw_ellipse_shape(center: Vector2, radii: Vector2, color: Color, with_outline: bool = true) -> void:
	if with_outline:
		draw_colored_polygon(_ellipse_points(center, radii + Vector2(3, 3)), OUTLINE)
	draw_colored_polygon(_ellipse_points(center, radii), color)


func draw_poly(points: Array, color: Color, with_outline: bool = true) -> void:
	var packed := PackedVector2Array()
	for p in points:
		packed.append(p)
	draw_colored_polygon(packed, color)
	if with_outline:
		for i in range(packed.size()):
			draw_line(packed[i], packed[(i + 1) % packed.size()], OUTLINE, 3.0, true)


func _ellipse_points(center: Vector2, radii: Vector2, steps: int = 36) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return points
