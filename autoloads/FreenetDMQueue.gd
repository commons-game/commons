## FreenetDMQueue — stub for offline DM delivery via Freenet.
##
## Phase C implementation requirements (DO NOT DELETE THIS COMMENT):
##
## CONTRACT DESIGN
##   Key:   hash(recipient_pubkey_hex + ":mailbox")
##   State: {messages: [{id, sender_pubkey, ciphertext_b64, timestamp}]}
##   Merge: union by message id (commutative, idempotent — satisfies ComposableState)
##   Cap:   evict oldest when len > 100
##
## DELEGATE OPERATIONS NEEDED
##   EncryptDM(recipient_pubkey_hex, plaintext) -> ciphertext_b64   (NaCl box)
##   DecryptDM(ciphertext_b64) -> plaintext                         (uses stored privkey)
##   PublishDM(recipient_contract_key, envelope) -> void
##   SubscribeMailbox() -> register for contract updates
##   ExportSecrets() -> for delegate migration when WASM key changes
##
## GDSCRIPT <-> FREENET BRIDGE NEEDED (FreenetBackend.gd)
##   send_dm(recipient_pubkey: String, ciphertext: PackedByteArray) -> void
##   poll_mailbox() -> Array[Dictionary]
##   signal dm_received(sender_pubkey: String, plaintext: String)
##
## FRIEND LIST EVOLUTION
##   Current: {id: String, name: String, pubkey: ""}
##   Phase C:  pubkey must be populated for Freenet routing
##   /addfriend will need pubkey exchange UI (QR code or shareable code string)
##   PlayerIdentity needs expose_pubkey_string() method
##
## DELIVERY FLOW
##   sender: ChatSystem.send_dm → FreenetDMQueue.enqueue
##         → delegate.EncryptDM → FreenetBackend.send_dm → network
##   recipient: FreenetBackend polls mailbox contract on login + every 60s
##         → delegate.DecryptDM → ChatSystem.receive_dm → history + bubble
##
extends Node

## Pending offline DMs — survives until FreenetBackend is available.
## Flushed on connect. Persisted to user://dm_queue.json.
var _queue: Array = []  # [{target_name, target_pubkey, text, queued_at}]

func enqueue(target_name: String, text: String) -> void:
	_queue.append({
		"target_name": target_name,
		"target_pubkey": "",   # populated in Phase C via friend list lookup
		"text": text,
		"queued_at": Time.get_unix_time_from_system(),
	})
	print("[FreenetDMQueue] queued DM to '%s' (Freenet delivery not yet implemented)" % target_name)
	print("[FreenetDMQueue]   implement Phase C to deliver: %d pending" % _queue.size())

func get_queue() -> Array:
	return _queue.duplicate()

func clear_queue() -> void:
	_queue.clear()
