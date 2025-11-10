extends CharacterBody3D

# Constants
const MOVE_STEP := 3.0               # How much the player moves per key press
const ROTATE_STEP := deg_to_rad(45)     # Rotate in 45 degree increments
const CAPTURE_DELAY_FRAMES := 5      # Frames to wait before capturing

# Timer to delay capture after movement
var capture_timer := 0

# Input locks to prevent continuous movement from holding keys
var move_locked := false
var rotate_locked := false

var ScreenCaptureClass = preload("res://screencapture.gd")
var screen_capture: Node = null


func _ready() -> void:
	# create an instance and add it so its _ready() runs
	screen_capture = ScreenCaptureClass.new()
	add_child(screen_capture)

	# assign preview_rect from the current scene (if it exists)
	var root_scene = get_tree().get_current_scene()
	if root_scene and root_scene.has_node("Window/Control/PreviewRect"):
		screen_capture.preview_rect = root_scene.get_node("Window/Control/PreviewRect")

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	if screen_capture and screen_capture.busy:
		return

	# --- Discrete rotation ---
	if not rotate_locked:
		if Input.is_action_just_pressed("ui_left"):
			rotation.y += ROTATE_STEP
			rotate_locked = true
			capture_timer = CAPTURE_DELAY_FRAMES
		elif Input.is_action_just_pressed("ui_right"):
			rotation.y -= ROTATE_STEP
			rotate_locked = true
			capture_timer = CAPTURE_DELAY_FRAMES
	elif not (Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right")):
		rotate_locked = false

	# --- Discrete forward/backward movement ---
	if not move_locked:
		if Input.is_action_just_pressed("ui_up"):
			_move_forward(MOVE_STEP)
			move_locked = true
			capture_timer = CAPTURE_DELAY_FRAMES
		elif Input.is_action_just_pressed("ui_down"):
			_move_forward(-MOVE_STEP)
			move_locked = true
			capture_timer = CAPTURE_DELAY_FRAMES
	elif not (Input.is_action_pressed("ui_up") or Input.is_action_pressed("ui_down")):
		move_locked = false

	# --- Handle delayed capture ---
	if capture_timer > 0:
		capture_timer -= 1
		if capture_timer == 0:
			_call_capture_if_ready()

func _move_forward(amount: float) -> void:
	var forward_dir := -transform.basis.z
	var displacement := forward_dir * amount
	move_and_collide(displacement)

func _call_capture_if_ready() -> void:
	if screen_capture:
		screen_capture.grab_and_send_frame()
	else:
		push_error("screen_capture is null")
