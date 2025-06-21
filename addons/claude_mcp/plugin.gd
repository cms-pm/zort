@tool
extends EditorPlugin

## Claude MCP Integration Plugin
## Connects Godot Editor to Claude Desktop via WebSocket MCP server

const MCPClient = preload("res://addons/claude_mcp/mcp_client.gd")

var mcp_client: MCPClient
var dock_ui: Control

func _enter_tree():
	print("[Claude MCP] Plugin starting...")
	
	# Create and start MCP client with error handling
	mcp_client = MCPClient.new()
	if not mcp_client:
		print("[PLUGIN] CRITICAL: Failed to create MCP client")
		return
	
	add_child(mcp_client)
	
	# DEBUG: Check editor interface availability
	var ei = get_editor_interface()
	print("[PLUGIN] Editor interface: ", ei)
	print("[PLUGIN] Editor interface type: ", typeof(ei))
	print("[PLUGIN] Editor interface null?: ", ei == null)
	
	if ei:
		print("[PLUGIN] Editor interface methods available: ", ei.get_method_list().size())
		mcp_client.set_editor_interface(ei)
		print("[PLUGIN] Editor interface set successfully")
	else:
		print("[PLUGIN] ERROR: Editor interface is null! Trying delayed setup...")
		# Try delayed initialization
		call_deferred("_delayed_editor_setup")
	
	# Create dock UI with error handling
	var dock_scene = load("res://addons/claude_mcp/mcp_dock.tscn")
	if not dock_scene:
		print("[PLUGIN] ERROR: Could not load dock UI scene")
		return
	
	dock_ui = dock_scene.instantiate()
	if not dock_ui:
		print("[PLUGIN] ERROR: Could not instantiate dock UI")
		return
	
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock_ui)
	
	# Connect dock to client with validation
	if dock_ui.has_method("setup"):
		dock_ui.setup(mcp_client)
	else:
		print("[PLUGIN] ERROR: Dock UI missing setup method")
	
	# DO NOT auto-connect here - let user choose when to connect
	print("[PLUGIN] Plugin initialized - ready for manual connection")
	print("[Claude MCP] Plugin initialized successfully")

func _delayed_editor_setup():
	print("[PLUGIN] Attempting delayed editor setup...")
	await get_tree().process_frame
	var ei = get_editor_interface()
	print("[PLUGIN] Delayed editor interface: ", ei)
	if ei:
		mcp_client.set_editor_interface(ei)
		print("[PLUGIN] Delayed setup successful")
	else:
		print("[PLUGIN] ERROR: Editor interface still null after delay")
		# Try one more time with a longer delay
		get_tree().create_timer(0.5).timeout.connect(_final_editor_setup)

func _final_editor_setup():
	print("[PLUGIN] Final editor setup attempt...")
	var ei = get_editor_interface()
	if ei:
		mcp_client.set_editor_interface(ei)
		print("[PLUGIN] Final setup successful")
	else:
		print("[PLUGIN] CRITICAL: Editor interface permanently unavailable")

func _exit_tree():
	print("[Claude MCP] Plugin shutting down...")
	
	if mcp_client:
		mcp_client.disconnect_from_server()
		mcp_client.queue_free()
	
	if dock_ui:
		remove_control_from_docks(dock_ui)
		dock_ui.queue_free()
	
	print("[Claude MCP] Plugin shut down")

func _has_main_screen():
	return false

func _get_plugin_name():
	return "Claude MCP"
