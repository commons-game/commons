## Backend.gd — autoload singleton. The sole IBackend access point.
## Phase 1: LocalBackend. Phase 6: swap LocalBackend to FreenetBackend.
## Nothing outside this file instantiates IBackend.
extends Node

const LocalBackendScript := preload("res://backend/local/LocalBackend.gd")
const FreenetBackendScript := preload("res://backend/freenet/FreenetBackend.gd")

## Set to true to use FreenetBackend instead of LocalBackend.
## In production this will be driven by a project setting or command-line flag.
var use_freenet: bool = false

var _backend: IBackend

func _ready() -> void:
	if use_freenet:
		_backend = FreenetBackendScript.new()
	else:
		_backend = LocalBackendScript.new()
	_backend.initialize()

func _process(_delta: float) -> void:
	_backend.poll()

## Test-only: replace the active backend with one supplied by a test harness
## (e.g. PuppetCluster swapping in an InMemoryBackend so two peers share
## isolated in-process storage). Production code never calls this.
func override(backend: IBackend) -> void:
	_backend = backend
	_backend.initialize()

func store_chunk(coords: Vector2i, data: PackedByteArray) -> void:
	_backend.store_chunk(coords, data)

func retrieve_chunk(coords: Vector2i) -> PackedByteArray:
	return _backend.retrieve_chunk(coords)

func delete_chunk(coords: Vector2i) -> void:
	_backend.delete_chunk(coords)

func save_reputation(data: Dictionary) -> void:
	_backend.save_reputation(data)

func load_reputation() -> Dictionary:
	return _backend.load_reputation()

func save_equipment(data: Dictionary) -> void:
	_backend.save_equipment(data)

func load_equipment() -> Dictionary:
	return _backend.load_equipment()

## Submit an opt-in error telemetry report.
## Returns true if the report was acknowledged by the proxy.
## Only FreenetBackend sends this over the wire; LocalBackend silently returns false.
func report_error(entry: Dictionary) -> bool:
	if _backend.has_method("report_error"):
		return await _backend.report_error(entry)
	return false

## Fetch the version manifest from Freenet.
## Returns a Dictionary on success, empty Dictionary if not found or not connected.
## Only FreenetBackend supports this; LocalBackend returns {}.
func get_version_manifest() -> Dictionary:
	if not _backend.has_method("request_version_manifest"):
		return {}
	# Connect one-shot to the version_manifest_ready signal.
	_backend.request_version_manifest()
	var result = await (_backend as Object).version_manifest_ready
	return result if result is Dictionary else {}
