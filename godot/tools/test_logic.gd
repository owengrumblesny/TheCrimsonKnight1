extends SceneTree
## Headless logic tests: godot --headless --path . --script res://godot/tools/test_logic.gd
## Inventory (select/cycle/assign/consume/restock/save round trip), Vitals, key rebinding, synthesized
## audio and the item data links.

var fails := 0
var passes := 0


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		printerr("FAIL ", what)


func _init() -> void:
	var inv := Inventory.new()
	check(inv.items.size() == 29, "29 catalog items (got %d)" % inv.items.size())
	var equippable := inv.order.filter(func(id): return inv.def(id).get("canEquip", false))
	check(inv.hotbar.size() == equippable.size() and inv.hotbar.all(func(id): return id in equippable), "belt holds every equippable item (%d)" % inv.hotbar.size())
	check(inv.hotbar[0] == "batarang" and inv.hotbar[2] == "phantom_sidearm", "belt order: core gadgets and guns on the number keys")
	check(inv.select_slot(8) == "" and inv.selected_item() == "scanner", "select belt key 9")
	inv.cycle(1)
	check(inv.selected_slot == 9, "cycle steps along the belt (got %d)" % inv.selected_slot)
	inv.cycle(-1)
	inv.select_slot(0)
	var last := inv.hotbar.size() - 1
	var far_item: String = inv.hotbar[last]
	check(inv.assign(far_item, 1) == "" and inv.hotbar[1] == far_item and inv.hotbar[last] == "grapple", "assign swaps an item onto a key")
	check(inv.selected_item() == "batarang", "selection follows its item through a swap")
	check(inv.assign("citadel_keycard", 0) != "", "quest item can't go on the hotbar")
	check(inv.consume("batarang") and inv.quantity("batarang") == 11, "consume stackable")
	inv.tick(0)
	inv.tick(4001)
	check(inv.quantity("batarang") == 12, "restock after restockMs")
	inv.start_cooldown("scanner", 1000)
	check(inv.cooldown_remaining("scanner", 2000) == 3000, "cooldown remaining")
	var snap := inv.snapshot()
	var inv2 := Inventory.new()
	inv2.load_state(JSON.parse_string(JSON.stringify(snap)))
	check(inv2.hotbar == inv.hotbar and inv2.selected_slot == inv.selected_slot, "save round trip")
	var before := inv2.hotbar.duplicate()
	inv2.load_state({"owned": {"nonexistent": {"quantity": 3}}, "hotbar": [{"itemId": "nope"}]})
	check(inv2.hotbar == before, "a foreign / old 8-slot hotbar in a save is ignored")

	var v := Vitals.new()
	check(v.impact(-10, 0, 11) == 0.0, "soft landing: no damage")
	var dmg := v.impact(-15, 0, 11)
	check(is_equal_approx(dmg, 4 * 7 * 0.3) and is_equal_approx(v.armor, 100 - 4 * 7 * 0.7), "armour absorbs 70%")
	v.shield_until = 5000
	check(v.impact(-30, 1000, 11) == 0.0, "shield blocks impact")
	check(is_equal_approx(v.restore("energy", 10), 0.0), "restore caps at max")

	var ck: Node = load("res://godot/scripts/core/ck_input.gd").new()
	ck._ready()
	check(ck.code("interact") == "KeyE" and ck.code("slot1") == "Digit1", "default bindings")
	ck.rebind("jump", "KeyE")
	check(ck.code("jump") == "KeyE" and ck.code("interact") == "Space", "rebind swaps the conflicting action")
	check(InputMap.action_get_events("jump")[0].physical_keycode == KEY_E, "InputMap updated")
	ck.reset_bindings()
	check(ck.code("jump") == "Space", "reset bindings")
	ck.free()

	var au := CKAudio.new()
	au._ready()
	for ev in ["ui.click", "ui.select", "ui.open", "ui.close", "ui.deny", "armor.step", "armor.jump", "armor.land",
			"armor.activate", "gadget.deploy", "gadget.throw", "gadget.pulse", "vehicle.summon"]:
		var w: AudioStreamWAV = au._streams[ev][0]
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		check(peak > 1000 and peak <= 32767 and w.get_length() > 0.04 and w.get_length() < 1.0,
			"sound %s: peak %d, %.2f s" % [ev, peak, w.get_length()])
	check(AudioServer.get_bus_index("SFX") > 0 and AudioServer.get_bus_index("UI") > 0, "audio buses")
	au.free()

	for id in inv.order:
		var d := inv.def(id)
		check(CKUI.has_icon(d["iconId"]), "icon for " + id)
		if d.get("modelId"):
			check(CKData.model_path(d["modelId"]) != "", "model for " + id)
		if d.get("artId"):
			check(CKData.board_image_path(d["artId"]) != "", "art for " + id)
	print("test_logic: %d passed, %d failed" % [passes, fails])
	quit(1 if fails else 0)
