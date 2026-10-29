class_name Inventory
extends RefCounted
## The one source of truth for owned items, hotbar slots and the selected slot (port of ui/uiState.ts
## InventoryService). Item definitions come from godot/data/items.json (exported from inventoryData.ts).
## Times are milliseconds on the Time.get_ticks_msec() clock.

signal changed

var items := {} # id -> definition
var order: Array = [] # catalog order
var owned := {} # id -> quantity
## the utility belt: every equippable item, always on the bar (no inventory juggling). The first
## KEYED positions have number keys (1-9, 0); the wheel / Q / R cycle the whole belt.
var hotbar: Array = []
const KEYED := 10
const BELT_ORDER := ["batarang", "grapple", "phantom_sidearm", "crimson_carbine", "energy_launcher", "energy_cannon",
	"smoke", "shield", "scanner", "energy_blade",
	"drone", "decoy", "emp", "sonic", "cloak", "beacon", "holoprojector", "flashlight",
	"first_aid", "power_cell", "repair", "comms", "forensics", "photo_camera"]
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
	for id in BELT_ORDER:
		if def(id).get("canEquip", false):
			hotbar.append(id)
	for id in order: # anything equippable not in the list goes on the end
		if def(id).get("canEquip", false) and not id in hotbar:
			hotbar.append(id)
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
	if i < 0 or i >= hotbar.size():
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
	for k in range(1, hotbar.size() + 1):
		var idx := posmod(selected_slot + dir * k, hotbar.size())
		if hotbar[idx] != "":
			select_slot(idx)
			return


## Move an item to belt position i (swapping with whatever was there): how you put an item on a number key.
func assign(id: String, i: int) -> String:
	if i < 0 or i >= hotbar.size():
		return "No such slot"
	var d := def(id)
	if d.is_empty():
		return "Unknown item"
	if not d.get("canEquip", false):
		return "%s can't go on the belt" % d["displayName"]
	var from := hotbar.find(id)
	if from < 0:
		return "Not on the belt"
	var sel_id: String = hotbar[selected_slot]
	hotbar[from] = hotbar[i]
	hotbar[i] = id
	selected_slot = hotbar.find(sel_id)
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
## Citadel suit station: every consumable back to a full stack.
func restock_all() -> void:
	for id in owned:
		owned[id] = maxi(owned[id], int(def(id)["maxStack"]))
	_restock_at.clear()
	changed.emit()


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
	for i in hotbar.size():
		hb.append({"index": i, "itemId": hotbar[i], "keyCode": "Digit%d" % ((i + 1) % 10) if i < KEYED else ""})
	return {"owned": o, "hotbar": hb, "selectedSlot": selected_slot}


## Apply saved data, dropping unknown ids instead of failing.
func load_state(saved: Dictionary) -> void:
	for id in saved.get("owned", {}):
		var d := def(id)
		var st = saved["owned"][id]
		if d.is_empty() or not st is Dictionary:
			continue
		owned[id] = clampi(int(st.get("quantity", 0)), 0, int(d["maxStack"]))
	# a saved belt order is kept only if it holds exactly the current belt (older 8-slot saves are ignored)
	var hb = saved.get("hotbar", [])
	var ids := []
	for e in hb:
		if e is Dictionary and e.get("itemId") is String:
			ids.append(e["itemId"])
	var same := ids.size() == hotbar.size()
	for id in ids:
		same = same and id in hotbar
	if same:
		hotbar = ids
	var sel = saved.get("selectedSlot", 0)
	if (sel is float or sel is int) and sel >= 0 and sel < hotbar.size():
		selected_slot = int(sel)
	changed.emit()
