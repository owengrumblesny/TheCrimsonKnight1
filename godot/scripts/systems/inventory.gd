class_name Inventory
extends RefCounted
## The one source of truth for owned items, hotbar slots and the selected slot (port of ui/uiState.ts
## InventoryService). Item definitions come from godot/data/items.json (exported from inventoryData.ts).
## Times are milliseconds on the Time.get_ticks_msec() clock.

signal changed

var items := {} # id -> definition
var order: Array = [] # catalog order
var owned := {} # id -> quantity
var hotbar: Array = [] # 8 item ids (or "")
var selected_slot := 0
var _cooldown_until := {}
var _restock_at := {}


func _init() -> void:
	var data: Dictionary = CKData.data("items")
	var over: Dictionary = CKData.data("items_godot")["items"]
	for d in data["items"]:
		d = d.duplicate()
		d.merge(over.get(d["id"], {}), true) # Godot-only overrides (weapons and vehicles are playable here)
		if d.get("unavailableReason") == null:
			d.erase("unavailableReason")
		items[d["id"]] = d
		order.append(d["id"])
	reset()


func reset() -> void:
	owned.clear()
	for id in order:
		owned[id] = int(items[id]["maxStack"])
	hotbar.clear()
	for s in CKData.data("items")["defaultHotbar"]:
		hotbar.append(s["itemId"])
	while hotbar.size() < 8:
		hotbar.append("")
	selected_slot = 0
	_cooldown_until.clear()
	_restock_at.clear()
	changed.emit()


func def(id: String) -> Dictionary:
	return items.get(id, {})


func quantity(id: String) -> int:
	return owned.get(id, 0)


func has(id: String) -> bool:
	return quantity(id) > 0


func selected_item() -> String:
	return hotbar[selected_slot]


## Select a slot (never uses the item). Returns a reason when it can't be selected, else "".
func select_slot(i: int) -> String:
	if i < 0 or i > 7:
		return "No such slot"
	var id: String = hotbar[i]
	if id == "":
		return "Slot %d is empty. Assign an item from the inventory (Tab)" % (i + 1)
	if not has(id):
		return "%s: none left" % def(id).get("displayName", "Item")
	if selected_slot != i:
		selected_slot = i
		changed.emit()
	return ""


## Step to the next/previous non-empty slot.
func cycle(dir: int) -> void:
	for k in range(1, 9):
		var idx := posmod(selected_slot + dir * k, 8)
		if hotbar[idx] != "":
			select_slot(idx)
			return


## Put an item in a slot (an item lives in at most one slot).
func assign(id: String, i: int) -> String:
	if i < 0 or i > 7:
		return "No such slot"
	if id != "":
		var d := def(id)
		if d.is_empty():
			return "Unknown item"
		if not d.get("canEquip", false):
			return "%s cannot be placed on the hotbar" % d["displayName"]
		for k in 8:
			if hotbar[k] == id:
				hotbar[k] = ""
	hotbar[i] = id
	changed.emit()
	return ""


func cooldown_remaining(id: String, now: int) -> int:
	return maxi(0, _cooldown_until.get(id, 0) - now)


func cooldown_fraction(id: String, now: int) -> float:
	var total: float = def(id).get("cooldownMs", 0)
	return cooldown_remaining(id, now) / total if total > 0 else 0.0


func start_cooldown(id: String, now: int) -> void:
	var ms: int = def(id).get("cooldownMs", 0)
	if ms:
		_cooldown_until[id] = now + ms


func consume(id: String, n := 1) -> bool:
	var d := def(id)
	if d.is_empty() or quantity(id) < n:
		return false
	if d.get("stackable", false):
		owned[id] -= n
		changed.emit()
	return true


## Consumables refill slowly over time (sandbox: no shop).
func tick(now: int) -> void:
	var any := false
	for id in owned:
		var d := def(id)
		var restock: int = d.get("restockMs", 0)
		if restock == 0 or owned[id] >= int(d["maxStack"]):
			_restock_at.erase(id)
			continue
		if not _restock_at.has(id):
			_restock_at[id] = now + restock
		elif now >= _restock_at[id]:
			owned[id] += 1
			_restock_at.erase(id)
			any = true
	if any:
		changed.emit()


## Persistable snapshot, same shape as the web save's `inventory` field.
func snapshot() -> Dictionary:
	var o := {}
	for id in owned:
		o[id] = {"itemId": id, "quantity": owned[id]}
	var hb := []
	for i in 8:
		hb.append({"index": i, "itemId": hotbar[i] if hotbar[i] != "" else null, "keyCode": "Digit%d" % (i + 1)})
	return {"owned": o, "hotbar": hb, "selectedSlot": selected_slot}


## Apply saved data, dropping unknown ids instead of failing.
func load_state(saved: Dictionary) -> void:
	for id in saved.get("owned", {}):
		var d := def(id)
		var st = saved["owned"][id]
		if d.is_empty() or not st is Dictionary:
			continue
		owned[id] = clampi(int(st.get("quantity", 0)), 0, int(d["maxStack"]))
	var hb = saved.get("hotbar", [])
	for i in mini(8, hb.size()):
		var id = hb[i].get("itemId") if hb[i] is Dictionary else null
		hotbar[i] = id if id is String and def(id).get("canEquip", false) else ""
	var sel = saved.get("selectedSlot", 0)
	if (sel is float or sel is int) and sel >= 0 and sel < 8:
		selected_slot = int(sel)
	changed.emit()
