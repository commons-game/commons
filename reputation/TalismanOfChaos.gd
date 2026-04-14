## TalismanOfChaos — item that voluntarily opts a player into the chaos merge pool.
## Idempotent: applying to an already-chaos player is a no-op.
class_name TalismanOfChaos

var id: String = "talisman_of_chaos"

func apply_to(player_id: String, reputation_store: Object) -> void:
	reputation_store.opt_into_chaos_pool(player_id)
