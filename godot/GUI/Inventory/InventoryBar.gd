# Class that represents a bar of inventory slots. Transmits blueprint events up
# to the preview controller.
class_name InventoryBar
extends HBoxContainer

signal inventory_changed(panel, held_item)

export var InventoryPanelScene: PackedScene
export var slot_count := 10
export var item_filters := ""

var panels := []
onready var _filter_list := item_filters.split(" ", false)


func _ready() -> void:
	_make_panels()


func setup(gui: Control) -> void:
	for panel in panels:
		panel.setup(gui, _filter_list)
		if not panel.is_connected("held_item_changed", self, "_on_Panel_held_item_changed"):
			Log.log_error(
				panel.connect("held_item_changed", self, "_on_Panel_held_item_changed"),
				"Inventory Bar"
			)


func find_panels_with(item_id: String) -> Array:
	var output := []
	for panel in panels:
		if panel.held_item and Library.get_entity_name_from(panel.held_item) == item_id:
			output.push_back(panel)

	return output


func get_inventory() -> Array:
	var output := []
	for panel in panels:
		if panel.held_item:
			output.push_back(panel.held_item)

	return output


func update_labels() -> void:
	for panel in panels:
		panel._update_label()


func add_to_first_available_inventory(item: BlueprintEntity) -> bool:
	var item_name := Library.get_entity_name_from(item)
	
	if not Library.is_valid_filter(_filter_list, item_name):
		return false

	for panel in panels:
		if (
			panel.held_item
			and Library.get_entity_name_from(panel.held_item) == item_name
			and panel.held_item.stack_count < panel.held_item.stack_size
		):
			var available_space: int = panel.held_item.stack_size - panel.held_item.stack_count
			if item.stack_count > available_space:
				var transfer_count := item.stack_count - available_space
				panel.held_item.stack_count += transfer_count
				item.stack_count -= transfer_count
			else:
				panel.held_item.stack_count += item.stack_count
				item.queue_free()
				return true

		elif not panel.held_item:
			panel.held_item = item
			return true

	return false


func _make_panels() -> void:
	for _i in slot_count:
		var panel := InventoryPanelScene.instance()
		add_child(panel)
		panels.append(panel)


func _on_Panel_held_item_changed(panel: Control, held_item: BlueprintEntity) -> void:
	emit_signal("inventory_changed", panel, held_item)
