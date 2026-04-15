## GameConfig — carries configuration from MainMenu → World.
##
## Set by MainMenu before changing scene, read by World._ready() to decide
## whether to host, join, or run single-player.
extends Node

var mode: String = ""        # "host" | "join" | "" (single-player)
var host_ip: String = "127.0.0.1"
var port: int = 7777
