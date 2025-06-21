@tool
extends Node
class_name MCPClient

## WebSocket client for communicating with Claude MCP Server
## Handles all MCP command execution and scene manipulation

signal connected_to_server
signal disconnected_from_server
signal command_executed(command: String, result: Dictionary)
signal connection_status_changed(status: String)

const SERVER_URL = "ws://localhost:8765"

var websocket: WebSocketPeer
var connection_status: String = "disconnected"
var pending_requests: Dictionary = {}

# Connection interface references
var editor_interface: EditorInterface
var editor_selection: EditorSelection

# User intent tracking
var user_requested_disconnect: bool = false

func _ready():
	# Get editor interfaces - will be set by plugin when added to scene tree
	editor_interface = null
	editor_selection = null
	
	# Create WebSocket
	websocket = WebSocketPeer.new()
	
	print("[MCP Client] Initialized")

func set_editor_interface(ei: EditorInterface):
	# Called by plugin to provide editor interface
	print("[MCP_CLIENT] set_editor_interface called with: ", ei)
	if ei:
		editor_interface = ei
		editor_selection = ei.get_selection()
		print("[MCP_CLIENT] Editor interface SET successfully")
		print("[MCP_CLIENT] Editor selection: ", editor_selection)
	else:
		print("[MCP_CLIENT] ERROR: Received null editor interface")

func _process(_delta):
	if not websocket:
		return
		
	var old_status = connection_status
	websocket.poll()
	
	match websocket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if connection_status != "connecting":
				connection_status = "connecting"
				print("[MCP Client] Connecting to server...")
		WebSocketPeer.STATE_OPEN:
			if connection_status != "connected":
				connection_status = "connected"
				print("[MCP Client] Connected to server")
				connected_to_server.emit()
			
			# Process incoming messages
			while websocket.get_available_packet_count() > 0:
				var packet = websocket.get_packet()
				var message_text = packet.get_string_from_utf8()
				_handle_server_message(message_text)
		WebSocketPeer.STATE_CLOSING:
			if connection_status != "disconnecting":
				connection_status = "disconnecting"
				print("[MCP Client] Disconnecting from server...")
		WebSocketPeer.STATE_CLOSED:
			if connection_status != "disconnected":
				connection_status = "disconnected"
				print("[MCP Client] Disconnected from server")
				disconnected_from_server.emit()
	
	# Emit status change signal if status changed
	if old_status != connection_status:
		connection_status_changed.emit(connection_status)

func connect_to_server():
	print("[MCP Client] Connecting to ", SERVER_URL)
	
	# Clear user disconnect flag
	user_requested_disconnect = false
	
	# Ensure websocket is created
	if not websocket:
		websocket = WebSocketPeer.new()
	
	var error = websocket.connect_to_url(SERVER_URL)
	if error != OK:
		print("[MCP Client] Failed to connect: ", error)
		return false
	
	connection_status = "connecting"
	return true

func disconnect_from_server():
	print("[MCP Client] User requested disconnect")
	
	# Set user disconnect flag to prevent automatic reconnection
	user_requested_disconnect = true
	
	# Set status immediately to prevent reconnection
	connection_status = "disconnecting"
	connection_status_changed.emit("disconnecting")
	
	if websocket:
		websocket.close(1000, "User requested disconnect")
	else:
		# If no websocket, go directly to disconnected
		connection_status = "disconnected"
		connection_status_changed.emit("disconnected")
	
	# The actual disconnection will be handled in _process() when STATE_CLOSED is detected

func is_server_connected() -> bool:
	return connection_status == "connected"

func _handle_server_message(message_text: String):
	# Validate input
	if message_text.is_empty():
		print("[MCP Client] Received empty message")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(message_text)
	
	if parse_result != OK:
		print("[MCP Client] Failed to parse JSON (error ", parse_result, "): ", message_text)
		return
	
	var message = json.data
	if not message is Dictionary:
		print("[MCP Client] Message is not a dictionary: ", typeof(message))
		return
	
	# Handle multi-client protocol messages
	var msg_type = message.get("type", "")
	if msg_type == "handshake":
		_handle_handshake(message)
		return
	elif msg_type == "heartbeat":
		_handle_heartbeat(message)
		return
	
	print("[MCP Client] Received command: ", message.get("command", "unknown"))
	
	# Execute the command with error handling
	var result = _execute_command(message)
	if not result:
		result = {"success": false, "error": "Command execution returned null"}
	
	# Send response back
	var response = {
		"id": message.get("id", ""),
		"success": result.get("success", false),
		"result": result.get("data") if result.get("success", false) else null,
		"error": result.get("error") if not result.get("success", false) else null,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	_send_response(response)

func _execute_command(message: Dictionary) -> Dictionary:
	var command = message.get("command", "")
	var params = message.get("params", {})
	print("[MCP_CLIENT] Executing command: ", command)
	
	# RUNTIME CHECK: Try to recover editor interface if null
	if not editor_interface and get_parent() is EditorPlugin:
		print("[MCP_CLIENT] Attempting runtime editor interface recovery...")
		var ei = get_parent().get_editor_interface()
		if ei:
			set_editor_interface(ei)
			print("[MCP_CLIENT] Runtime recovery successful!")
	
	if not editor_interface:
		print("[MCP_CLIENT] ERROR: No editor interface available for command: ", command)
		return {
			"success": false,
			"error": "Editor interface not available - Debug Info: " + str(get_parent())
		}
	
	match command:
		"get_scene_tree":
			return _cmd_get_scene_tree(params)
		"list_nodes":
			return _cmd_list_nodes(params)
		"create_node":
			return _cmd_create_node(params)
		"set_node_property":
			return _cmd_set_node_property(params)
		"get_node_properties":
			return _cmd_get_node_properties(params)
		"move_node":
			return _cmd_move_node(params)
		"save_scene":
			return _cmd_save_scene(params)
		"shutdown":
			return _cmd_shutdown(params)
		_:
			return {"success": false, "error": "Unknown command: " + command}

func _send_response(response: Dictionary):
	if not websocket or websocket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("[MCP Client] ERROR: Cannot send response - websocket not connected")
		_handle_connection_lost()
		return
	
	var json_string = JSON.stringify(response)
	if json_string.is_empty():
		print("[MCP Client] ERROR: Failed to stringify response")
		return
	
	var error = websocket.send_text(json_string)
	if error != OK:
		print("[MCP Client] ERROR: Failed to send response (error ", error, ")")
		
		# Check if this is a connection-related error
		if error == ERR_CONNECTION_ERROR or error == ERR_CANT_CONNECT:
			print("[MCP Client] Connection error detected during send")
			_handle_connection_lost()
	else:
		print("[MCP Client] Sent response for command successfully")

func _handle_connection_lost():
	"""Handle detected connection loss"""
	if connection_status != "disconnected":
		print("[MCP_CLIENT] 🔴 Connection loss detected - cleaning up")
		
		# Update status
		connection_status = "disconnected"
		
		# Close WebSocket if still open
		if websocket:
			websocket.close(1000, "Connection lost")
		
		# Clear any pending requests
		pending_requests.clear()
		
		# Notify other components
		disconnected_from_server.emit()
		connection_status_changed.emit("disconnected")

# Multi-client protocol handlers
func _handle_handshake(message: Dictionary):
	print("[MCP Client] Received handshake: ", message.get("clientId", "unknown"))
	# Send identification response
	var identify_msg = {
		"type": "identify",
		"clientType": "godot",
		"clientVersion": "1.0.1",
		"godotVersion": Engine.get_version_info().string
	}
	_send_raw_message(identify_msg)

func _handle_heartbeat(message: Dictionary):
	# Send heartbeat response
	var heartbeat_response = {
		"type": "heartbeat_response",
		"timestamp": message.get("timestamp", Time.get_unix_time_from_system())
	}
	_send_raw_message(heartbeat_response)

func _send_raw_message(message: Dictionary):
	if not websocket or websocket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json_string = JSON.stringify(message)
	websocket.send_text(json_string)

# Command implementations
func _cmd_get_scene_tree(_params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var tree_data = _build_node_tree(current_scene)
	return {"success": true, "data": {"root": tree_data}}

func _cmd_list_nodes(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var node_path = params.get("node_path", "")
	var current_scene = editor_interface.get_edited_scene_root()
	
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var nodes = []
	var start_node = current_scene
	
	if node_path != "":
		start_node = current_scene.get_node_or_null(node_path)
		if not start_node:
			return {"success": false, "error": "Node not found: " + node_path}
	
	_collect_nodes(start_node, nodes, _get_node_path(start_node))
	return {"success": true, "data": {"nodes": nodes}}

func _cmd_create_node(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var node_type = params.get("node_type", "")
	var node_name = params.get("node_name", "")
	var parent_path = params.get("parent_path", "")
	
	if node_type == "" or node_name == "":
		return {"success": false, "error": "node_type and node_name are required"}
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	# Find parent node
	var parent_node = current_scene
	if parent_path != "":
		parent_node = current_scene.get_node_or_null(parent_path)
		if not parent_node:
			return {"success": false, "error": "Parent node not found: " + parent_path}
	
	# Create new node
	var new_node = _create_node_by_type(node_type)
	if not new_node:
		return {"success": false, "error": "Unknown node type: " + node_type}
	
	# Set name and handle duplicates
	new_node.name = node_name
	parent_node.add_child(new_node)
	
	# Set owner for scene tree
	new_node.owner = current_scene
	
	# Validate the node was added successfully
	if not parent_node.has_node(NodePath(new_node.name)):
		return {"success": false, "error": "Failed to add node to parent"}
	
	var created_path = _get_node_path(new_node)
	return {
		"success": true, 
		"data": {
			"created_node": {
				"path": created_path,
				"type": node_type,
				"name": node_name
			}
		}
	}

func _cmd_set_node_property(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var node_path = params.get("node_path", "")
	var property_name = params.get("property_name", "")
	var property_value = params.get("property_value")
	
	if node_path == "" or property_name == "":
		return {"success": false, "error": "node_path and property_name are required"}
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var target_node = current_scene.get_node_or_null(node_path)
	if not target_node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	# IMMEDIATE FALLBACK: For position properties, always use move_node approach
	if property_name in ["position", "global_position"]:
		var x_val = 0.0
		var y_val = 0.0
		var z_val = null
		
		print("[DEBUG] Position property value type: ", typeof(property_value), " value: ", property_value)
		
		if property_value is Array and property_value.size() >= 2:
			# Direct array - this is the ideal case
			x_val = float(property_value[0])
			y_val = float(property_value[1])
			z_val = float(property_value[2]) if property_value.size() > 2 else null
			print("[DEBUG] Using direct array values: x=", x_val, " y=", y_val)
		else:
			# MCP sends arrays as strings - let's parse them!
			print("[DEBUG] Property value is string, attempting to parse as array: ", property_value)
			
			if property_value is String:
				# Parse string array like "[350, 175]"
				var cleaned = property_value.strip_edges().replace("[", "").replace("]", "")
				var parts = cleaned.split(",")
				
				if parts.size() >= 2:
					x_val = float(parts[0].strip_edges())
					y_val = float(parts[1].strip_edges())
					z_val = float(parts[2].strip_edges()) if parts.size() > 2 else null
					print("[DEBUG] Parsed string array values: x=", x_val, " y=", y_val)
				else:
					return {"success": false, "error": "Position string array must have at least 2 values: " + property_value}
			else:
				return {"success": false, "error": "Position property parsing not yet implemented for type: " + str(typeof(property_value))}
		
		print("[MCP_CLIENT] Using move_node fallback for position property: ", property_name)
		var move_params = {
			"node_path": node_path,
			"x": x_val,
			"y": y_val,
			"z": z_val
		}
		return _cmd_move_node(move_params)
	
	# For non-position properties, try basic assignment
	print("[MCP_CLIENT] Attempting basic property assignment: ", property_name, " = ", property_value)
	target_node.set(property_name, property_value)
	
	return {
		"success": true,
		"data": {
			"node_path": node_path,
			"property_name": property_name,
			"property_value": property_value
		}
	}

func _cmd_get_node_properties(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var node_path = params.get("node_path", "")
	
	if node_path == "":
		return {"success": false, "error": "node_path is required"}
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var target_node = current_scene.get_node_or_null(node_path)
	if not target_node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	var properties = {}
	var property_list = target_node.get_property_list()
	
	for prop in property_list:
		if prop.usage & PROPERTY_USAGE_EDITOR:
			var prop_name = prop.name
			properties[prop_name] = target_node.get(prop_name)
	
	return {
		"success": true,
		"data": {
			"node_path": node_path,
			"properties": properties
		}
	}

func _cmd_move_node(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var node_path = params.get("node_path", "")
	var x = params.get("x", 0.0)
	var y = params.get("y", 0.0)
	var z = params.get("z", null)
	
	if node_path == "":
		return {"success": false, "error": "node_path is required"}
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var target_node = current_scene.get_node_or_null(node_path)
	if not target_node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	# Set position based on node type
	if target_node.has_method("set_position"):
		if z != null and target_node.has_method("set_global_position"):
			target_node.global_position = Vector3(x, y, z)
		else:
			target_node.position = Vector2(x, y)
	else:
		return {"success": false, "error": "Node does not support position changes"}
	
	return {
		"success": true,
		"data": {
			"node_path": node_path,
			"new_position": {"x": x, "y": y, "z": z}
		}
	}

func _cmd_save_scene(params: Dictionary) -> Dictionary:
	if not editor_interface:
		return {"success": false, "error": "Editor interface not available"}
	
	var file_path = params.get("file_path", "")
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return {"success": false, "error": "No scene is currently open"}
	
	var scene_path = ""
	if file_path != "":
		scene_path = file_path
	else:
		scene_path = current_scene.scene_file_path
		if scene_path == "":
			return {"success": false, "error": "Scene has no file path, please specify file_path"}
	
	# Save the scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(current_scene)
	var error = ResourceSaver.save(packed_scene, scene_path)
	
	if error != OK:
		return {"success": false, "error": "Failed to save scene: " + str(error)}
	
	return {
		"success": true,
		"data": {
			"saved_path": scene_path
		}
	}

func _cmd_shutdown(params: Dictionary) -> Dictionary:
	print("[MCP_CLIENT] 🚫 SHUTDOWN command received from MCP server")
	var reason = params.get("reason", "unknown")
	var timestamp = params.get("timestamp", 0)
	
	print("[MCP_CLIENT] Shutdown reason: ", reason)
	print("[MCP_CLIENT] Shutdown timestamp: ", timestamp)
	
	# Send acknowledgment back to server immediately
	_send_shutdown_acknowledgment()
	
	# Perform graceful shutdown with a slight delay to ensure ack is sent
	call_deferred("_perform_graceful_shutdown")
	
	return {
		"success": true,
		"data": {
			"message": "Shutdown acknowledgment sent",
			"reason": reason
		}
	}

func _send_shutdown_acknowledgment():
	print("[MCP_CLIENT] Sending shutdown acknowledgment to server")
	
	var ack_message = {
		"command": "shutdown_ack",
		"timestamp": Time.get_unix_time_from_system(),
		"client_id": "godot_mcp_client"
	}
	
	if websocket and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_string = JSON.stringify(ack_message)
		var error = websocket.send_text(json_string)
		if error == OK:
			print("[MCP_CLIENT] ✅ Shutdown acknowledgment sent successfully")
		else:
			print("[MCP_CLIENT] ❌ Failed to send shutdown acknowledgment: ", error)
	else:
		print("[MCP_CLIENT] ⚠️ Cannot send shutdown ack - WebSocket not connected")

func _perform_graceful_shutdown():
	print("[MCP_CLIENT] 🔄 Performing graceful shutdown...")
	
	# Close WebSocket connection gracefully
	if websocket:
		websocket.close(1000, "Client shutting down gracefully")
		print("[MCP_CLIENT] WebSocket connection closed")
	
	# Update connection status
	connection_status = "disconnected"
	
	# Emit signals to notify other components
	disconnected_from_server.emit()
	
	# Clear any pending requests
	pending_requests.clear()
	
	print("[MCP_CLIENT] ✅ Graceful shutdown completed")

# PRIORITY 1 FIX: Property type conversion helper
func _convert_property_value(property_name: String, raw_value) -> Variant:
	"""Convert common problematic property types for Godot 4 compatibility"""
	
	# Add debug logging to track what we're converting
	print("[DEBUG] Converting property: ", property_name, " value: ", raw_value, " type: ", typeof(raw_value))
	
	# Vector2 properties (most common issue) - be EXPLICIT about type creation
	if property_name in ["position", "global_position", "size", "scale", "custom_minimum_size"]:
		if raw_value is Array and raw_value.size() >= 2:
			var result = Vector2(float(raw_value[0]), float(raw_value[1]))
			print("[DEBUG] Converted Array to Vector2: ", result, " type: ", typeof(result))
			return result
		elif raw_value is String:
			# Handle "Vector2(x, y)" format strings
			var regex = RegEx.new()
			regex.compile(r"Vector2\(([+-]?\d*\.?\d+),\s*([+-]?\d*\.?\d+)\)")
			var result = regex.search(raw_value)
			if result:
				var vec2_result = Vector2(result.get_string(1).to_float(), result.get_string(2).to_float())
				print("[DEBUG] Converted String to Vector2: ", vec2_result, " type: ", typeof(vec2_result))
				return vec2_result
	
	# Vector3 properties (for 3D nodes) - be EXPLICIT
	if property_name in ["position", "global_position", "scale"] and raw_value is Array and raw_value.size() >= 3:
		var result = Vector3(float(raw_value[0]), float(raw_value[1]), float(raw_value[2]))
		print("[DEBUG] Converted Array to Vector3: ", result, " type: ", typeof(result))
		return result
	
	# Color properties - be EXPLICIT
	if property_name in ["modulate", "self_modulate", "color"] and raw_value is Array:
		if raw_value.size() >= 3:
			var alpha = float(raw_value[3]) if raw_value.size() > 3 else 1.0
			var result = Color(float(raw_value[0]), float(raw_value[1]), float(raw_value[2]), alpha)
			print("[DEBUG] Converted Array to Color: ", result, " type: ", typeof(result))
			return result
	
	# Float properties (rotation, etc.) - be EXPLICIT
	if property_name in ["rotation", "rotation_degrees"]:
		if raw_value is String:
			var result = raw_value.to_float()
			print("[DEBUG] Converted String to float: ", result, " type: ", typeof(result))
			return result
		elif raw_value is int or raw_value is float:
			var result = float(raw_value)
			print("[DEBUG] Converted number to float: ", result, " type: ", typeof(result))
			return result
	
	# Boolean properties - be EXPLICIT
	if raw_value is String and raw_value.to_lower() in ["true", "false"]:
		var result = raw_value.to_lower() == "true"
		print("[DEBUG] Converted String to bool: ", result, " type: ", typeof(result))
		return result
	
	# Return original value if no conversion needed
	print("[DEBUG] No conversion applied, returning original: ", raw_value, " type: ", typeof(raw_value))
	return raw_value

# Helper functions
func _build_node_tree(node: Node) -> Dictionary:
	var result = {
		"name": node.name,
		"type": node.get_class(),
		"path": _get_node_path(node)
	}
	
	var children = []
	for child in node.get_children():
		children.append(_build_node_tree(child))
	
	if children.size() > 0:
		result["children"] = children
	
	return result

func _collect_nodes(node: Node, nodes: Array, base_path: String):
	nodes.append({
		"path": base_path,
		"type": node.get_class(),
		"name": node.name
	})
	
	for child in node.get_children():
		var child_path = base_path + "/" + child.name
		_collect_nodes(child, nodes, child_path)

func _get_node_path(node: Node) -> String:
	if not editor_interface:
		return node.name  # Fallback to just the node name
	
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return node.name
	
	if node == current_scene:
		return node.name
	else:
		return current_scene.get_path_to(node)

func _create_node_by_type(type_name: String) -> Node:
	match type_name:
		"Node": return Node.new()
		"Node2D": return Node2D.new()
		"Node3D": return Node3D.new()
		"Control": return Control.new()
		"Label": return Label.new()
		"Button": return Button.new()
		"VBoxContainer": return VBoxContainer.new()
		"HBoxContainer": return HBoxContainer.new()
		"ColorRect": return ColorRect.new()
		"Sprite2D": return Sprite2D.new()
		"Sprite3D": return Sprite3D.new()
		"RigidBody2D": return RigidBody2D.new()
		"RigidBody3D": return RigidBody3D.new()
		"CharacterBody2D": return CharacterBody2D.new()
		"CharacterBody3D": return CharacterBody3D.new()
		"CollisionShape2D": return CollisionShape2D.new()
		"CollisionShape3D": return CollisionShape3D.new()
		"Area2D": return Area2D.new()
		"Area3D": return Area3D.new()
		"StaticBody2D": return StaticBody2D.new()
		"StaticBody3D": return StaticBody3D.new()
		"Camera2D": return Camera2D.new()
		"Camera3D": return Camera3D.new()
		"AudioStreamPlayer": return AudioStreamPlayer.new()
		"AudioStreamPlayer2D": return AudioStreamPlayer2D.new()
		"AudioStreamPlayer3D": return AudioStreamPlayer3D.new()
		"Timer": return Timer.new()
		"HTTPRequest": return HTTPRequest.new()
		_:
			print("[MCP Client] Unknown node type: ", type_name)
			return null
