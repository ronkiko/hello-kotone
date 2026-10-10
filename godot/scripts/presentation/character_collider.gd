extends RefCounted
## One ground-pivot collision geometry contract for owner and prediction proxies.
## Server-selected body dimensions are the only source; presentation assets never
## resize or offset the physical shape.

static func size_px(body: Dictionary, pixels_per_meter: float) -> Vector2:
	if pixels_per_meter <= 0.0:
		return Vector2.ZERO
	var width: Variant = body.get("collision_width_mm")
	var height: Variant = body.get("collision_height_mm")
	if typeof(width) != TYPE_INT or typeof(height) != TYPE_INT 		or int(width) <= 0 or int(height) <= 0:
		return Vector2.ZERO
	return Vector2(float(width), float(height)) * pixels_per_meter / 1000.0

static func install(collision: CollisionShape2D, body: Dictionary, pixels_per_meter: float) -> bool:
	if collision == null:
		return false
	var size := size_px(body, pixels_per_meter)
	if size == Vector2.ZERO:
		# Invalid server geometry fails closed. Repeated invalid snapshots are no-ops.
		if not collision.disabled:
			collision.disabled = true
		if collision.shape != null:
			collision.shape = null
		return false
	# World snapshots can arrive every frame. Keep the native Shape2D resource
	# stable so Godot physics and the Remote Inspector never see a replacement
	# collider unless this node has no rectangle yet.
	var shape := collision.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		shape.size = size
		collision.shape = shape
	elif shape.size != size:
		shape.size = size
	# Character world position is the canonical ground-contact pivot. Rectangle
	# center therefore sits exactly half its physical height above the ground.
	var center := Vector2(0.0, -size.y / 2.0)
	if collision.position != center:
		collision.position = center
	if collision.disabled:
		collision.disabled = false
	return true
