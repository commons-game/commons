## ProcessManager — auto-starts the Freenet backend processes.
##
## Launch sequence:
##   1. Check if port 7510 is already open (dev mode — skip everything)
##   2. Find freenet binary (bundled → ~/.local/bin → PATH)
##   3. Find commons-proxy binary (bundled → exe dir)
##   4. Start freenet network, wait up to 8s for port 7509
##   5. Start commons-proxy, wait up to 5s for port 7510
##   6. Emit backend_ready or backend_failed(reason)
##
## Export layout expected:
##   <exe>/bin/freenet          (Linux) or bin/freenet.exe (Windows)
##   <exe>/bin/commons-proxy   (Linux) or bin/commons-proxy.exe (Windows)
##
## Headless mode: skips startup (CI / dedicated server).
extends Node

signal backend_ready
signal backend_failed(reason: String)
signal status_changed(message: String)

## Set to true once the backend is confirmed reachable.
var is_ready: bool = false

var _freenet_pid:  int = -1
var _proxy_pid:    int = -1

func _ready() -> void:
	if "--no-managed-backend" in OS.get_cmdline_user_args():
		is_ready = true
		backend_ready.emit()
		return
	if DisplayServer.get_name() == "headless":
		is_ready = true
		backend_ready.emit()
		return
	_start_backend.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_shutdown()

func _shutdown() -> void:
	if _proxy_pid > 0:
		OS.kill(_proxy_pid)
		_proxy_pid = -1
	if _freenet_pid > 0:
		OS.kill(_freenet_pid)
		_freenet_pid = -1

# ---------------------------------------------------------------------------
# Binary discovery
# ---------------------------------------------------------------------------

func _find_binary(name: String) -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var suffix  := ".exe" if OS.get_name() == "Windows" else ""
	var fname   := name + suffix
	var candidates := [
		exe_dir.path_join("bin").path_join(fname),
		exe_dir.path_join(fname),
		OS.get_environment("HOME").path_join(".local/bin").path_join(fname),
	]
	# Also search PATH entries
	var path_env := OS.get_environment("PATH")
	for dir in path_env.split(":" if OS.get_name() != "Windows" else ";"):
		candidates.append(dir.path_join(fname))
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""

# ---------------------------------------------------------------------------
# Port check
# ---------------------------------------------------------------------------

func _port_open(port: int) -> bool:
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host("127.0.0.1", port)
	if err == OK:
		tcp.disconnect_from_host()
		return true
	return false

# ---------------------------------------------------------------------------
# Proxy startup (handles env vars via /usr/bin/env on Linux/macOS)
# ---------------------------------------------------------------------------

func _start_proxy(proxy_bin: String) -> int:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var contract_path := exe_dir.path_join("bin").path_join("commons_chunk_contract")
	var lobby_path    := exe_dir.path_join("bin").path_join("commons_lobby_contract")
	var pairing_path  := exe_dir.path_join("bin").path_join("commons_pairing_contract")
	var delegate_path := exe_dir.path_join("bin").path_join("commons_player_delegate")
	var error_path    := exe_dir.path_join("bin").path_join("commons_error_contract")
	var version_path  := exe_dir.path_join("bin").path_join("commons_version_manifest")

	if OS.get_name() == "Windows":
		# Windows: env var support TODO — launch directly for now
		return OS.create_process(proxy_bin, [])
	else:
		# Linux/macOS: use env(1) to pass variables
		var args := [
			"FREENET_NODE_URL=ws://[::1]:7509/v1/contract/command?encodingProtocol=native",
			"COMMONS_PROXY_ADDR=127.0.0.1:7510",
		]
		# Only add contract paths if the files exist
		for pair in [
			["COMMONS_CONTRACT_PATH",         contract_path],
			["COMMONS_LOBBY_CONTRACT_PATH",    lobby_path],
			["COMMONS_PAIRING_CONTRACT_PATH",  pairing_path],
			["COMMONS_PLAYER_DELEGATE_PATH",   delegate_path],
			["COMMONS_ERROR_CONTRACT_PATH",    error_path],
			["COMMONS_VERSION_CONTRACT_PATH",  version_path],
		]:
			if FileAccess.file_exists(pair[1]):
				args.append("%s=%s" % [pair[0], pair[1]])
		args.append(proxy_bin)
		return OS.create_process("/usr/bin/env", args)

# ---------------------------------------------------------------------------
# Main startup coroutine
# ---------------------------------------------------------------------------

func _start_backend() -> void:
	# Already running? Skip everything.
	if _port_open(7510):
		is_ready = true
		backend_ready.emit()
		return

	status_changed.emit("Finding Freenet...")

	var freenet_bin := _find_binary("freenet")
	if freenet_bin.is_empty():
		backend_failed.emit("Freenet not found. Run: curl -fsSL https://freenet.org/install.sh | sh")
		return

	var proxy_bin := _find_binary("commons-proxy")
	if proxy_bin.is_empty():
		backend_failed.emit("commons-proxy not found alongside game executable.")
		return

	status_changed.emit("Starting Freenet...")
	_freenet_pid = OS.create_process(freenet_bin, ["network"], false)
	if _freenet_pid <= 0:
		backend_failed.emit("Failed to start Freenet.")
		return

	# Wait up to 8s for freenet to bind port 7509
	var waited := 0.0
	while not _port_open(7509) and waited < 8.0:
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	if not _port_open(7509):
		backend_failed.emit("Freenet failed to start (timeout).")
		return

	status_changed.emit("Starting proxy...")
	_proxy_pid = _start_proxy(proxy_bin)
	if _proxy_pid <= 0:
		backend_failed.emit("Failed to start commons-proxy.")
		return

	# Wait up to 5s for proxy to bind port 7510
	waited = 0.0
	while not _port_open(7510) and waited < 5.0:
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	if not _port_open(7510):
		backend_failed.emit("Proxy failed to start (timeout).")
		return

	is_ready = true
	backend_ready.emit()
	status_changed.emit("Connected")
