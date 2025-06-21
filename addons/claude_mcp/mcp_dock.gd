@tool
extends Control

## UI Dock for Claude MCP Plugin
## Shows connection status and provides manual controls

var mcp_client: MCPClient

# UI References - will be set manually to avoid @onready issues in tool scripts
var status_label: Label
var connect_button: Button
var info_label: Label

func _ready():
	# Get UI references safely
	var vbox = get_node_or_null("VBox")
	if vbox:
		status_label = vbox.get_node_or_null("StatusLabel")
		connect_button = vbox.get_node_or_null("ConnectButton")
		info_label = vbox.get_node_or_null("InfoLabel")
	else:
		print("[DOCK] ERROR: VBox container not found")
		return
	
	# Connect button signal with error handling
	if connect_button and not connect_button.pressed.is_connected(_on_connect_pressed):
		connect_button.pressed.connect(_on_connect_pressed)
	else:
		print("[DOCK] ERROR: Connect button not found or signal already connected")

func setup(client: MCPClient):
	if not client:
		print("[DOCK] ERROR: Null MCP client provided to setup")
		return
	
	mcp_client = client
	
	# Connect signals with error checking
	if mcp_client.connected_to_server and not mcp_client.connected_to_server.is_connected(_on_connected):
		mcp_client.connected_to_server.connect(_on_connected)
	if mcp_client.disconnected_from_server and not mcp_client.disconnected_from_server.is_connected(_on_disconnected):
		mcp_client.disconnected_from_server.connect(_on_disconnected)
	if mcp_client.command_executed and not mcp_client.command_executed.is_connected(_on_command_executed):
		mcp_client.command_executed.connect(_on_command_executed)
	if mcp_client.connection_status_changed and not mcp_client.connection_status_changed.is_connected(_on_connection_status_changed):
		mcp_client.connection_status_changed.connect(_on_connection_status_changed)
	
	_update_ui()

func _on_connected():
	print("[DOCK] MCP server connected")
	if info_label:
		info_label.text = "Connected - Ready for commands"
	_update_ui()

func _on_disconnected():
	print("[DOCK] MCP server disconnected")
	if info_label:
		info_label.text = "Server disconnected"
	_update_ui()

func _on_command_executed(command: String, result: Dictionary):
	if info_label:
		var success_icon = "✅" if result.get("success", false) else "❌"
		info_label.text = success_icon + " Last: " + command

func _on_connection_status_changed(status: String):
	print("[DOCK] Connection status changed to: ", status)
	
	# Update UI based on the new status
	if status_label:
		var status_text = "Status: "
		var status_color = Color.GRAY
		
		match status:
			"connecting":
				status_text += "Connecting..."
				status_color = Color.YELLOW
			"connected":
				status_text += "Connected"
				status_color = Color.GREEN
			"disconnecting":
				status_text += "Disconnecting..."
				status_color = Color.ORANGE
			"disconnected":
				status_text += "Disconnected"
				status_color = Color.RED
			_:
				status_text += "Unknown"
				status_color = Color.GRAY
		
		status_label.text = status_text
		status_label.modulate = status_color
	
	# Update info label with contextual messages
	if info_label:
		match status:
			"connecting":
				info_label.text = "Establishing connection..."
			"connected":
				info_label.text = "Ready for Claude commands"
			"disconnecting":
				info_label.text = "Closing connection..."
			"disconnected":
				info_label.text = "Connection lost - check MCP server"
	
	# Update connect button
	if connect_button:
		match status:
			"connecting":
				connect_button.text = "Cancel"
				connect_button.disabled = false
			"connected":
				connect_button.text = "Disconnect"
				connect_button.disabled = false
			"disconnecting":
				connect_button.text = "Disconnecting..."
				connect_button.disabled = true
			"disconnected":
				connect_button.text = "Connect"
				connect_button.disabled = false

func _on_connect_pressed():
	if not mcp_client:
		print("[DOCK] ERROR: No MCP client available for connection")
		return
	
	# Get current status to make decision
	var current_status = mcp_client.connection_status
	print("[DOCK] Connect button pressed - current status: ", current_status)
	
	match current_status:
		"connected":
			print("[DOCK] Disconnecting from server...")
			mcp_client.disconnect_from_server()
		"disconnected":
			print("[DOCK] Attempting to connect to server...")
			var success = mcp_client.connect_to_server()
			if not success:
				print("[DOCK] ERROR: Failed to initiate connection")
				if info_label:
					info_label.text = "Connection failed - check server"
		"connecting":
			print("[DOCK] Canceling connection attempt...")
			# Cancel ongoing connection
			mcp_client.disconnect_from_server()
		"disconnecting":
			print("[DOCK] Already disconnecting - please wait...")
			# Do nothing, let the disconnection complete
		_:
			print("[DOCK] Unknown connection status: ", current_status)

func _update_ui():
	if not mcp_client:
		print("[DOCK] WARNING: Trying to update UI without MCP client")
		return
		
	var connected = mcp_client.is_server_connected()
	
	# Update status label with error handling
	if status_label:
		status_label.text = "Status: " + ("Connected" if connected else "Disconnected")
		status_label.modulate = Color.GREEN if connected else Color.RED
	else:
		print("[DOCK] WARNING: Status label not available for update")
	
	# Update connect button with error handling
	if connect_button:
		connect_button.text = "Disconnect" if connected else "Connect"
		connect_button.disabled = false
	else:
		print("[DOCK] WARNING: Connect button not available for update")
	
	# Update info label with error handling
	if info_label:
		if connected:
			info_label.text = "Ready for Claude commands"
		else:
			info_label.text = "Start MCP server first"
	else:
		print("[DOCK] WARNING: Info label not available for update")
