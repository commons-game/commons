## MergeRouter — gates merge proposals on reputation state.
##
## Routing rule (no bans — only pool matching):
##   Normal + Normal → allowed
##   Chaos  + Chaos  → allowed
##   Mixed           → blocked
##
## Unknown players default to Normal (clean slate).
class_name MergeRouter

func can_merge(player_a_id: String, player_b_id: String, store: Object) -> bool:
	var a_chaos: bool = store.is_in_chaos_pool(player_a_id)
	var b_chaos: bool = store.is_in_chaos_pool(player_b_id)
	return a_chaos == b_chaos
