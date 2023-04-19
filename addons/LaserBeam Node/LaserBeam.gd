@icon("res://addons/BulletUpHell/Sprites/NodeIcons22.png")
@tool
extends Area2D
class_name LaserBeam

signal collided(position:Vector2, collider:Object, normal:Vector2)
signal ray_built

const INFINITE:float = -1

@export var button:bool = false : set = set_button
@export_range(0, 99999, 1.0, "suffix:px") var laser_length:float = 80 : set = set_laser_length
@export_range(0, 99999, 1.0, "suffix:px") var laser_width:float = 16 : set = set_laser_width
@export_range(-1, 99999, 1.0, "suffix:px") var max_whole_length:float = INFINITE
@export_range(INFINITE, 99999, 0.001, "suffix:sec") var max_shot_duration:float = INFINITE
@export_range(INFINITE, 99999, 0.001, "hide_slider", "suffix:px/sec") var speed:float = INFINITE : set = set_speed
enum SPEED {None, Length, Width}
@export var expand_on:SPEED = SPEED.None : set = set_speed_type

@export_range(INFINITE, 99999, 0.001, "suffix:sec") var update_cooldown:float = INFINITE : set = set_update_cooldown

@export_group("Collisions")
@export_range(0, 99999, 0.001, "suffix:sec") var delay_collide:float = 0
@export_file("*.tscn") var spawn_on_hit:String
@export var spawn_target:NodePath
@export_flags("Bodies", "Areas") var collide_with:int = 1 : set = set_collide_with
@export_flags_2d_physics var casting_mask:int = 1 : set = set_cast_mask

enum GROUPLIST {WhiteList, BlackList}
@export_group("Bounces", "bounce_")
@export_range(0, 99999, 1, "suffix:bounces") var bounce_count:int = 0
@export var bounce_groups:Array[String]
@export var bounce_group_list:GROUPLIST = GROUPLIST.WhiteList
@export_range(0, 99999, 0.001, "hide_slider", "suffix:sec") var bounce_cooldown:float = 0
@export_file("*.tscn") var bounce_spawn_on_bounce:String
@export_subgroup("Advanced")
@export_range(0, 99999, 1.0, "hide_slider", "suffix:px") var bounce_min_length:float = 0
@export_range(0, 99999, 0.1, "suffix:px") var BOUNCE_OFFSET:float = 10

enum END {Delete, Stay, ShrinkW} #  shrinkL
@export_group("On End")
@export_range(INFINITE, 99999, 0.001, "suffix:sec") var stay_duration:float = 3
@export var on_end:END = END.Delete
@export var can_end_midair:bool = true
@export_file("*.tscn") var spawn_on_end:String

enum TEXTUREMODE {None, Tile, Stretch}
enum CAP {None, Box, Round}
@export_category("Line2D")
@export var texture:Texture2D = null : set = set_texture
@export var texture_mode:TEXTUREMODE = TEXTUREMODE.None : set = set_texture_mode
@export var width_curve:Curve : set = set_width_curve
@export var begin_cap_mode:CAP = CAP.None : set = set_cap_mode

###

@onready var tween:Tween = create_tween()
var Phys = PhysicsServer2D

var points:Array[Vector2]
var shapes:Array[RectangleShape2D]

var update_idx = 0
var current_duration:float = 0
var spawn_parent:Node
var instance_end:Node
var instance_bounce:Node
var instance_hit:Node


func set_button(value):
	_ready()

func _ready():
	if spawn_on_end != "": instance_end = load(spawn_on_end).instantiate()
	if spawn_on_hit != "": instance_hit = load(spawn_on_hit).instantiate()
	if bounce_spawn_on_bounce != "": instance_bounce = load(bounce_spawn_on_bounce).instantiate()
	if spawn_target != NodePath():
		spawn_parent = get_node(spawn_target)
	elif spawn_parent == null: spawn_parent = self
	init_shapes()
	reset_cast()

#func _physics_process(delta):
#	if update_cooldown == INFINITE: return
#
#	update_idx += delta
#	if update_idx >= update_cooldown:
##		print(update_idx)
#		reset_cast()
#		update_idx = 0

func init_shapes():
	var shape:RectangleShape2D
	for s in bounce_count+1:
		shape = RectangleShape2D.new()
		shapes.append(shape)
		Phys.area_add_shape(self.get_rid(), shape.get_rid(), Transform2D(0, Vector2(10,0)))

func reset_cast():
	print($Line2D.get_point_count())
	current_duration = 0
	set_laser_length(laser_length)
	$Line2D.clear_points()
	points.clear()
	$RayCast2D.position = Vector2.ZERO
	$RayCast2D.rotation = 0
	for s in shapes.size():
		Phys.area_set_shape_disabled(self.get_rid(), s, true)
	ray_cast()
	$Line2D.rotation = -rotation

func ray_cast():
	$RayCast2D.position = Vector2.ZERO
	$RayCast2D.enabled = true
	points.append(Vector2.ZERO)
	
	# cast to get the laser endpoint
	$RayCast2D.force_shapecast_update()
	var current_length:float = 0; var col_count = $RayCast2D.get_collision_count()-1;
	var max_while:int = 0; var pos:Vector2; var angle:Vector2; var ray_length:float;
	while $RayCast2D.is_colliding() and max_while <= bounce_count:
		# one iteration per bounce
		if not can_bounce_on($RayCast2D.get_collider(col_count)): break
		
		max_while += 1
		pos = $RayCast2D.get_collision_point(col_count)
		angle = $RayCast2D.get_collision_normal(col_count)
		ray_length = $RayCast2D.target_position.x#$RayCast2D.global_position.distance_to(pos)
		points.append(pos-global_position)
		collided.emit(pos-global_position, $RayCast2D.get_collider(), angle)
		
		if max_whole_length > 0:
			current_length += ray_length
			if current_length + $RayCast2D.target_position.x > max_whole_length:
				$RayCast2D.target_position.x = max_whole_length-current_length
		
		if not make_ray(ray_length): break
		if speed > 0:
			await ray_built
		if max_whole_length > 0 and current_length >= max_whole_length-bounce_min_length:
			break
		if bounce_cooldown > 0:
			await get_tree().create_timer(bounce_cooldown).timeout
		
		# put the shapecast at the endpoint and rotate it to bounce of the collider for the next iteration
		$RayCast2D.global_rotation = ($RayCast2D.global_position-pos).bounce(angle).angle()+PI
		$RayCast2D.global_position = pos + Vector2(BOUNCE_OFFSET,0).rotated($RayCast2D.global_rotation)
		$RayCast2D.force_shapecast_update()
	
	# if last laser segment doesnt hit a wall, still draw it
	if can_end_midair and max_while < bounce_count:
		points.append(($RayCast2D.target_position).rotated($RayCast2D.global_rotation)-global_position+$RayCast2D.global_position)
		make_ray($RayCast2D.target_position.x)
	
	$RayCast2D.enabled = false
	if points.size() > 1 and can_expand_width():
		expand_width()
		await tween.finished
	
	end_cast()

func can_bounce_on(collider:Node):
	if bounce_groups.is_empty(): return true
	for group in collider.get_groups():
		if group in bounce_groups: return (bounce_group_list == GROUPLIST.WhiteList)
	return (bounce_group_list == GROUPLIST.BlackList)

func make_ray(ray_length:float):
	if points.size() <= 1: return
	
	var p_idx:int = $Line2D.get_point_count()
	var start_pos:Vector2 = $Line2D.get_point_position(p_idx-1)
	var angle:float = start_pos.angle_to_point($Line2D.get_point_position(p_idx))
	if expand_on == SPEED.None:#speed <= 0:
		# instantly build the ray (laser segment)
		$Line2D.add_point(points[-1])
		# setup the ray's collision shape
		
#		var curr_shape:RectangleShape2D = shapes[p_idx-1]
#		var demi_pos:Vector2 = (start_pos - $Line2D.get_point_position(p_idx))/2
#		Phys.area_set_shape_transform(self.get_rid(), p_idx-1, Transform2D(angle, demi_pos))
		Phys.shape_set_data(shapes[p_idx-1].get_rid(), Vector2(ray_length,laser_width/2))
	
	elif expand_on == SPEED.Length:
		var duration = ray_length/speed#start_pos.distance_to(points[-1])/speed
		if current_duration + duration > max_shot_duration:
			duration = max_shot_duration - current_duration
		current_duration += duration
		$Line2D.add_point(start_pos)
		tween.tween_method(build_ray.bind(p_idx), start_pos, points[-1], duration)
		tween.play()
		
	else:
		$Line2D.add_point(points[-1])
	
	# move collision shape at right place
	Phys.area_set_shape_transform(self.get_rid(), p_idx-1, Transform2D(angle, start_pos+(Vector2(10,0)).rotated(angle)))
	
	ray_is_built(p_idx-1)
	return (current_duration > max_shot_duration)
	
func build_ray(new_pos:Vector2, idx:int):
	if points.size() <= 1: return
	# line
	$Line2D.set_point_position(idx, new_pos)
	# shape
	Phys.shape_set_data(shapes[idx-1].get_rid(), Vector2($Line2D.get_point_position(idx-1).distance_to(new_pos),laser_width/2))

func ray_is_built(p_idx):
	await tween.finished
	ray_built.emit()
	
	# spawn scene at collision points
	if bounce_spawn_on_bounce != "":
		for p in points.size():
			if p == points.size()-1: continue
			instance_bounce.global_position = points[p]+global_position
			spawn_parent.call_deferred("add_child", instance_bounce.duplicate())
	
	if delay_collide > 0: await get_tree().create_timer(delay_collide).timeout
	Phys.area_set_shape_disabled(self.get_rid(), p_idx, false)

func expand_width(end:float=laser_width):
	$Line2D.width = 0
	tween.tween_property($Line2D, "width", end, laser_width/speed)
	tween.play()

func end_cast():
	if spawn_on_end != "":
		instance_end.global_position = points[-1]+global_position
		spawn_parent.call_deferred("add_child", instance_end.duplicate())
	
	if stay_duration == INFINITE or Engine.is_editor_hint(): return
	elif stay_duration > 0: await get_tree().create_timer(stay_duration).timeout
	
	match on_end:
		END.Delete: queue_free()
		END.ShrinkW:
			expand_width(0)
			await tween.finished
			queue_free()
		END.Stay: pass


func _on_area_shape_entered(area_rid, area, area_shape_index, local_shape_index):
	Spawning.bullet_collide_area(area_rid, area, area_shape_index, local_shape_index, self)
	hit(area)

func _on_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	Spawning.bullet_collide_body(body_rid, body, body_shape_index, local_shape_index, self)
	hit(body)

func hit(collider):
	if spawn_on_hit != "":
		instance_hit.global_position #todo
		spawn_parent.call_deferred("add_child", instance_hit.duplicate())

func can_expand_width():
	return (expand_on == SPEED.Width and speed > 0) and (max_shot_duration == INFINITE and bounce_cooldown == 0)

## SETGETS

func set_collide_with(value):
	collide_with = value
	$RayCast2D.collide_with_areas = (collide_with > 1)
	$RayCast2D.collide_with_bodies = (collide_with%2 == 1)

func set_laser_length(value):
	if max_whole_length != INFINITE:
		value = min(value, max_whole_length)
	laser_length = value
	$RayCast2D.target_position = Vector2(laser_length,0)

func set_laser_width(value):
	laser_width = value
	$Line2D.width = laser_width

func set_cast_mask(value):
	casting_mask = value
	$RayCast2D.collision_mask = casting_mask

func set_texture(value):
	texture = value
	$Line2D.texture = texture

func set_texture_mode(value):
	texture_mode = value
	$Line2D.texture_mode = texture_mode

func set_cap_mode(value):
	begin_cap_mode = value
	$Line2D.begin_cap_mode = begin_cap_mode

func set_speed_type(value):
	expand_on = value
	if speed <= 0 and expand_on != SPEED.None: speed = 10
	elif speed > 0 and expand_on == SPEED.None: speed = -1

func set_speed(value):
	speed = value
	if speed > 0 and expand_on == SPEED.None: expand_on = SPEED.Length 
	elif speed <= 0 and expand_on != SPEED.None: expand_on = SPEED.None

func set_width_curve(value):
	width_curve = value
	$Line2D.width_curve = width_curve

func set_update_cooldown(value):
	update_cooldown = value
	if update_idx >= update_cooldown:
		update_idx = 0
