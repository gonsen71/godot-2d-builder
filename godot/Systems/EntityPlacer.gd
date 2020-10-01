# TileMap that handles user input and places entities in the world.
class_name EntityPlacer
extends TileMap

const MAXIMUM_WORK_DISTANCE := 275.0
const POSITION_OFFSET := Vector2(0, 25)

export var GroundEntityScene: PackedScene

var gui: Control
var last_hovered: Node2D = null

var _simulation: Simulation
var _flat_entities: Node2D
var _current_deconstruct_location := Vector2(INF, INF)
var _ground: TileMap

onready var _deconstruct_timer := $Timer
onready var _deconstruct_tween := $Tween


func _unhandled_input(event: InputEvent) -> void:
	# Abort deconstruction by stopping timer if the mouse moves/clicks/releases
	if event is InputEventMouseButton:
		_abort_deconstruct()

	var global_mouse_position := get_global_mouse_position()
	var has_placeable_blueprint: bool = gui.blueprint and gui.blueprint.placeable
	var is_close_to_player := (
		global_mouse_position.distance_to(_simulation.player.global_position)
		< MAXIMUM_WORK_DISTANCE
	)

	# Place entities that have a placeable blue print on left button, if there is space.
	if event.is_action_pressed("left_click"):
		var cellv := world_to_map(global_mouse_position)

		var is_on_ground: bool = _ground.get_cellv(cellv) == 0

		if has_placeable_blueprint:
			if not _simulation.is_cell_occupied(cellv) and is_close_to_player and is_on_ground:
				if Library.get_filename_from(gui.blueprint) == "Wire":
					_place_entity(cellv, _get_powered_neighbors(cellv))
				else:
					_place_entity(cellv)
				_update_neighboring_flat_entities(cellv)
		elif _simulation.is_cell_occupied(cellv) and is_close_to_player:
			var entity := _simulation.get_entity_at(cellv)
			if entity.is_in_group(Types.GUI_ENTITIES):
				gui.open_entity_gui(entity)
				_clear_hover_entity()
	# Do hold-and-release entity removal using a yielded timer. If interrupted by
	# another event, stop the timer.
	elif event.is_action_pressed("right_click") and not has_placeable_blueprint:
		var cellv := world_to_map(global_mouse_position)
		if _simulation.is_cell_occupied(cellv) and is_close_to_player:
			_deconstruct(global_mouse_position, cellv)
	# Move or highlight devices and blueprints.
	elif event is InputEventMouseMotion:
		var cellv := world_to_map(global_mouse_position)
		if cellv != _current_deconstruct_location:
			_abort_deconstruct()

		if has_placeable_blueprint:
			move_blueprint_in_world(cellv)
		else:
			_update_hover(cellv)
	elif event.is_action_pressed("rotate_blueprint") and has_placeable_blueprint:
		gui.blueprint.rotate_blueprint()
	elif event.is_action_pressed("drop") and gui.blueprint and is_close_to_player:
		var is_on_ground: bool = _ground.get_cellv(world_to_map(global_mouse_position)) == 0

		if is_on_ground:
			_drop_entity(gui.blueprint, global_mouse_position)
			gui.blueprint = null
	elif event.is_action_pressed("sample") and not gui.blueprint:
		_sample_entity_at(world_to_map(global_mouse_position))


func _process(_delta: float) -> void:
	var has_placeable_blueprint: bool = gui.blueprint and gui.blueprint.placeable
	if (
		has_placeable_blueprint
		and (
			Input.is_action_pressed("left")
			or Input.is_action_pressed("right")
			or Input.is_action_pressed("down")
			or Input.is_action_pressed("up")
		)
	):
		move_blueprint_in_world(world_to_map(get_global_mouse_position()))


func setup(simulation: Simulation, flat_entities: Node2D, _gui: Control, ground: TileMap) -> void:
	gui = _gui
	_simulation = simulation
	_flat_entities = flat_entities
	_ground = ground

	var existing_entities := flat_entities.get_children()

	for child in get_children():
		if child is Node2D or child is StaticBody2D:
			existing_entities.push_back(child)

	for entity in existing_entities:
		_simulation.place_entity(entity, world_to_map(entity.global_position))


# Sets the sprite for a given wire
func replace_wire(wire: Node2D, directions: int) -> void:
	wire.sprite.region_rect = WireBlueprint.get_region_for_direction(directions)


func move_blueprint_in_world(cellv: Vector2) -> void:
	gui.blueprint.make_world()
	gui.blueprint.global_position = get_viewport_transform().xform(
		map_to_world(cellv) + POSITION_OFFSET
	)
	var is_close_to_player := (
		get_global_mouse_position().distance_to(_simulation.player.global_position)
		< MAXIMUM_WORK_DISTANCE
	)
	var is_on_ground: bool = _ground.get_cellv(cellv) == 0

	if not _simulation.is_cell_occupied(cellv) and is_close_to_player and is_on_ground:
		gui.blueprint.modulate = Color.white
	else:
		gui.blueprint.modulate = Color.red

	if Library.get_filename_from(gui.blueprint) == "Wire":
		gui.blueprint.set_sprite_for_direction(_get_powered_neighbors(cellv))


# Gets neighbors that are in the power groups around the given cell
func _get_powered_neighbors(cellv: Vector2) -> int:
	var direction := 0

	for neighbor in Types.NEIGHBORS.keys():
		var key: Vector2 = cellv + Types.NEIGHBORS[neighbor]

		if _simulation.is_cell_occupied(key):
			var entity: Node = _simulation.get_entity_at(key)

			if (
				entity.is_in_group(Types.POWER_MOVERS)
				or entity.is_in_group(Types.POWER_RECEIVERS)
				or entity.is_in_group(Types.POWER_SOURCES)
			):
				direction |= neighbor

	return direction


# Finds all wires and replaces them so they point towards powered entities
func _update_neighboring_flat_entities(cellv: Vector2) -> void:
	for neighbor in Types.NEIGHBORS.keys():
		var key: Vector2 = cellv + Types.NEIGHBORS[neighbor]
		var object = _simulation.get_entity_at(key)

		if object and object is WireEntity:
			var tile_directions := _get_powered_neighbors(key)
			replace_wire(object, tile_directions)


# Places an entity or wire and informs the simulation
func _place_entity(cellv: Vector2, directions := 0) -> void:
	var new_entity: Node2D = Library.entities[Library.get_filename_from(gui.blueprint)].instance()

	if Library.get_filename_from(gui.blueprint) == "Wire":
		_flat_entities.add_child(new_entity)
		new_entity.sprite.region_rect = WireBlueprint.get_region_for_direction(directions)
	else:
		add_child(new_entity)

	new_entity.global_position = map_to_world(cellv) + POSITION_OFFSET

	_simulation.place_entity(new_entity, cellv)
	new_entity._setup(gui.blueprint)

	if gui.blueprint.stack_count == 1:
		gui.destroy_blueprint()
	else:
		gui.blueprint.stack_count -= 1
		gui.update_label()


func _drop_entity(entity: BlueprintEntity, location: Vector2) -> void:
	if entity.get_parent():
		entity.get_parent().remove_child(entity)
	var ground_entity := GroundEntityScene.instance()
	add_child(ground_entity)
	ground_entity.setup(entity, location)


func _deconstruct(event_position: Vector2, cellv: Vector2) -> void:
	var entity := _simulation.get_entity_at(cellv)
	if (
		not entity.deconstruct_filter.empty()
		and (
			not gui.blueprint
			or not Library.get_filename_from(gui.blueprint) in entity.deconstruct_filter
		)
	):
		return

	gui.deconstruct_bar.rect_global_position = get_viewport_transform().xform(event_position)
	gui.deconstruct_bar.show()

	var modifier := 1.0
	if Library.get_filename_from(gui.blueprint).find("Crude") != -1:
		modifier = 10.0

	_deconstruct_tween.interpolate_property(gui.deconstruct_bar, "value", 0, 100, 0.2 * modifier)
	_deconstruct_tween.start()

	var _error := _deconstruct_timer.connect(
		"timeout", self, "_finish_deconstruct", [cellv], CONNECT_ONESHOT
	)
	_deconstruct_timer.start(0.2 * modifier)
	_current_deconstruct_location = cellv


func _finish_deconstruct(cellv: Vector2) -> void:
	var entity := _simulation.get_entity_at(cellv)
	var entity_name := Library.get_filename_from(entity)

	var location := map_to_world(cellv)

	if entity and Library.blueprints.has(entity_name):
		var Blueprint: PackedScene = Library.blueprints[entity_name]

		for _i in entity.pickup_count:
			_drop_entity(Blueprint.instance(), location)

	if entity.is_in_group(Types.GUI_ENTITIES):
		var inventories: Array = gui.find_inventory_bars_in(gui.get_gui_component_from(entity))
		var inventory_items := []
		for inventory in inventories:
			inventory_items += inventory.get_inventory()

		for item in inventory_items:
			_drop_entity(item, location)

	_simulation.remove_entity(cellv)
	_update_neighboring_flat_entities(cellv)
	gui.deconstruct_bar.hide()
	Events.emit_signal("hovered_over_entity", null)


func _abort_deconstruct() -> void:
	if _deconstruct_timer.is_connected("timeout", self, "_finish_deconstruct"):
		_deconstruct_timer.disconnect("timeout", self, "_finish_deconstruct")
	_deconstruct_timer.stop()
	gui.deconstruct_bar.hide()


func _update_hover(cellv: Vector2) -> void:
	var is_close_to_player := (
		get_global_mouse_position().distance_to(_simulation.player.global_position)
		< MAXIMUM_WORK_DISTANCE
	)

	if _simulation.is_cell_occupied(cellv) and is_close_to_player:
		_hover_entity(cellv)
	else:
		_clear_hover_entity()


func _hover_entity(cellv: Vector2) -> void:
	_clear_hover_entity()
	var entity: Node2D = _simulation.get_entity_at(cellv)
	entity.toggle_outline(true)
	last_hovered = entity
	Events.emit_signal("hovered_over_entity", entity)


func _clear_hover_entity() -> void:
	if last_hovered:
		last_hovered.toggle_outline(false)
		last_hovered = null
		Events.emit_signal("hovered_over_entity", null)


func _sample_entity_at(cellv: Vector2) -> void:
	var entity: Node = _simulation.get_entity_at(cellv)
	if not entity:
		return

	var inventories_with: Array = gui.find_panels_with(Library.get_filename_from(entity))
	if inventories_with.empty():
		return

	var input := InputEventMouseButton.new()
	input.button_index = BUTTON_LEFT
	input.pressed = true
	inventories_with.front()._gui_input(input)
