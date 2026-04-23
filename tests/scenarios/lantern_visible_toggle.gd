## Scenario: toggling the lantern must produce a visible pixel change on the
## rendered viewport. Closes the "I don't see the diff" feedback gap — prior
## lantern iterations all required a user round-trip to confirm the visual;
## this asserts the delta programmatically.
##
## Must run under a real display (xvfb or xpra). Use dev/run-scenario.sh
## which wraps with xvfb-run; --headless uses the dummy renderer and
## get_viewport().get_texture() comes back blank.
##
## Usage:
##   dev/run-scenario.sh tests/scenarios/lantern_visible_toggle.gd
extends Node

const REGION_HALF := 20   # pixels around the player centre to sample
const MIN_DIFF    := 50   # require ≥N differing pixels for a pass

func _run(p: Node) -> void:
	await p.wait_ready()
	# Let the first chunk(s) render so the viewport isn't black.
	await p.wait_seconds(0.5)

	p.select_tool(0)
	p.check(p.active_tool_id() == "lantern",
		"expected active tool lantern, got " + p.active_tool_id())

	var lantern: Node = p.player().get_node_or_null("Lantern")
	p.check(lantern != null, "player has no Lantern child")
	if bool(lantern.is_on):
		lantern.set_on(false)
		await p.wait_seconds(0.1)

	# Baseline screenshot — lantern off.
	var img_off: Image = await _viewport_image(p)
	p.check(img_off != null and img_off.get_width() > 8,
		"viewport image unavailable — is the scenario running under a display?")

	# Flip lantern on and capture. Direct set_on isolates rendering from
	# click-dispatch: we're testing "does is_on=true look different?".
	lantern.set_on(true)
	await p.wait_seconds(0.1)
	var img_on: Image = await _viewport_image(p)

	var w: int = img_off.get_width()
	var h: int = img_off.get_height()
	var cx: int = w / 2
	var cy: int = h / 2

	var diff: int = 0
	for dy in range(-REGION_HALF, REGION_HALF + 1):
		for dx in range(-REGION_HALF, REGION_HALF + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var a: Color = img_off.get_pixel(x, y)
			var b: Color = img_on.get_pixel(x, y)
			if _color_dist(a, b) > 0.02:
				diff += 1

	if diff < MIN_DIFF:
		var dir := DirAccess.open("user://")
		if dir != null and not dir.dir_exists("screenshots"):
			dir.make_dir("screenshots")
		img_off.save_png("user://screenshots/lantern_off_debug.png")
		img_on.save_png("user://screenshots/lantern_on_debug.png")
		p.fail("lantern toggle produced only %d differing pixels (need ≥%d). Debug PNGs saved." % [diff, MIN_DIFF])
		return

	p.pass_scenario("lantern toggle changed %d pixels in a %dx%d region" % [
		diff, REGION_HALF * 2 + 1, REGION_HALF * 2 + 1])

## Euclidean colour distance in RGBA space.
func _color_dist(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	var da := a.a - b.a
	return sqrt(dr * dr + dg * dg + db * db + da * da)

## Fetch the current rendered viewport as an Image. Blocks one frame to let
## the GPU commit the latest state before read-back.
func _viewport_image(p: Node) -> Image:
	await p.wait_frames(1)
	var vp: Viewport = p.player().get_viewport()
	if vp == null:
		return null
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()
