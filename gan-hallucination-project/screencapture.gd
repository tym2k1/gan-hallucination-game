extends Node3D

class_name ScreenCapture

var http: HTTPRequest

#@onready var preview_rect: TextureRect = $Window/PreviewRect
var preview_rect: TextureRect = null
var current_preview_texture: ImageTexture = null
var busy: bool = false

func _ready() -> void:
	randomize()
	# ensure HTTPRequest exists and is connected
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed)

# Helper to append a string as UTF-8 bytes
func _append_str(buf: PackedByteArray, s: String) -> void:
	buf.append_array(s.to_utf8_buffer())

func grab_and_send_frame() -> void:
	if busy:
		return  # already processing
	busy = true      # lock until server responds
	# Get the current viewport's image
	var img: Image = get_viewport().get_texture().get_image()

	# Save a temporary PNG to send to the server
	var folder_path = "user://screenshots"
	DirAccess.make_dir_recursive_absolute(folder_path)
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var tmp_file = folder_path + "/frame_" + timestamp + ".png"
	var err = img.save_png(tmp_file)
	if err != OK:
		push_error("Failed to save frame! Error code: %d" % err)
		busy = false
		return
	print("✅ Saved frame to:", tmp_file)


	var abs_path = ProjectSettings.globalize_path(tmp_file)
	var boundary = "----GodotBoundary%08x" % randi()
	var crlf = "\r\n"
	var body_buf := PackedByteArray()

	# Open file once for reuse
	var f = FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		push_error("❌ Could not open file for reading: %s" % abs_path)
		busy = false
		return
	var file_bytes := f.get_buffer(f.get_length())
	f.close()

	# Label part
	_append_str(body_buf, "--" + boundary + crlf)
	_append_str(body_buf, 'Content-Disposition: form-data; name="label"; filename="%s"%s' % [tmp_file.get_file(), crlf])
	_append_str(body_buf, "Content-Type: image/png" + crlf + crlf)
	body_buf.append_array(file_bytes)
	_append_str(body_buf, crlf)

	# Inst part
	_append_str(body_buf, "--" + boundary + crlf)
	_append_str(body_buf, 'Content-Disposition: form-data; name="inst"; filename="%s"%s' % [tmp_file.get_file(), crlf])
	_append_str(body_buf, "Content-Type: image/png" + crlf + crlf)
	body_buf.append_array(file_bytes)
	_append_str(body_buf, crlf)

	# Noise value
	_append_str(body_buf, "--" + boundary + crlf)
	_append_str(body_buf, 'Content-Disposition: form-data; name="noise"' + crlf + crlf)
	_append_str(body_buf, "1.0" + crlf)

	# Finish body
	_append_str(body_buf, "--" + boundary + "--" + crlf)

	var headers := PackedStringArray([
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Accept: application/json"
	])

	# Start async HTTP request (POST)
	var url = "http://127.0.0.1:5000/infer"
	var req_err = http.request_raw(url, headers, HTTPClient.METHOD_POST, body_buf)
	if req_err != OK:
		push_error("❌ Failed to start HTTPRequest: %d" % req_err)
		busy = false
		return

	print("📤 HTTPRequest sent (async). Waiting for response...")

# Called when HTTPRequest completes
func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	# result: internal engine result (OK or error), response_code: HTTP status (200, 500, ...)
	if result != OK:
		push_error("❌ HTTPRequest failed with engine result: %d" % result)
		busy = false
		return
	print("📥 HTTP response code:", response_code)

	# Convert body to string
	var resp_text: String = ""
	if body.size() > 0:
		resp_text = body.get_string_from_utf8()
	else:
		push_error("❌ Empty response body")
		busy = false
		return

	print("📥 Raw response body:", resp_text)

	# Try to find/parse the first JSON object in the response
	var json_result := {}
	# Many servers return JSON-only; some return lines. We'll attempt to parse the whole body first,
	# then fallback to scanning lines for the first JSON dictionary.
	var parsed_json = JSON.parse_string(resp_text)
	if typeof(parsed_json) == TYPE_DICTIONARY:
		json_result = parsed_json
	else:
		# fallback: split lines and parse first JSON-looking line
		for line in resp_text.split("\n"):
			var trimmed = line.strip_edges()
			if trimmed == "":
				continue
			var p = JSON.parse_string(trimmed)
			if typeof(p) == TYPE_DICTIONARY:
				json_result = p
				break

	if json_result.is_empty():
		push_error("❌ Could not parse JSON from server response.")
		busy = false
		return
	print("✅ Parsed JSON:", json_result)

	# Handle the generated file reference
	if "generated" in json_result:
		print("generated field present: ", json_result["generated"])
		var server_file_path = ProjectSettings.globalize_path(json_result["generated"])
		print("server_file_path:", server_file_path)

		# Existence check
		if not FileAccess.file_exists(server_file_path):
			push_error("❌ Server image file does not exist: %s" % server_file_path)
			busy = false
			return

		var im := Image.new()
		var load_err = im.load(server_file_path)
		if load_err != OK:
			push_error("❌ Failed to load server image at: %s (err=%d)" % [server_file_path, load_err])
			busy = false
			return

		# create texture (static call)
		current_preview_texture = ImageTexture.create_from_image(im)
		if current_preview_texture == null:
			push_error("❌ create_from_image returned null")
			busy = false
			return

		preview_rect.texture = current_preview_texture
		preview_rect.visible = true
		preview_rect.queue_redraw()
		print("✅ Preview updated from server! texture:", current_preview_texture)
		busy = false
	else:
		print("no generated")
		busy = false
