# This script attaches to a CharacterBody2D node, which is meant for 2D objects that move.
extends CharacterBody2D

# This registers "Pet" as a custom type in your project. 
# Other scripts can now refer to this simply as "Pet" instead of "CharacterBody2D".
class_name Pet 

# ==========================================
# NODE REFERENCES
# ==========================================
# @onready tells Godot to wait until the game actually starts before finding these nodes.
# The "$" is a shortcut for get_node(). It looks for children of this Pet node in the scene tree.
@onready var shakeTween = $ShakeTween
@onready var pet_stats = $PetStats
@onready var pet_actions = $PetActions
@onready var anim_player = $AnimationPlayer
@onready var sprite = $Sprite2D
@onready var petDebugLabel = $PetDebugLabel

# ==========================================
# VARIABLES & SETTINGS
# ==========================================
# @export makes this variable visible in the Godot Inspector panel.
@export var resource: Resource:
	# This is a "setter". Whenever "resource" is changed (either in code or the inspector),
	# this block of code runs automatically.
	set(new_resource):
		resource = new_resource # Save the new resource
		# If the sprite node is ready and loaded, update its image.
		if sprite:
			update_resource()
		# If it's not ready yet, call_deferred tells Godot to "wait until it's safe" then update.
		else:
			call_deferred("update_resource")
		
# A signal is like a megaphone. When the pet gains XP, it "shouts" this signal.
# Other scripts (like your UI/Health bars) can listen for this shout and update the screen.
signal xpGained(experience_level, experience, experience_required)

# A constant (const) never changes. This is the exact pixel coordinate for the center of the screen.
const CENTER_POS = Vector2(256, 318)

# ==========================================
# STATE MACHINE
# ==========================================
# An enum is a way to create a list of named numbers. (IDLE = 0, WALKING = 1, etc.)
# It makes code much easier to read than trying to remember what "state 1" means.
enum PetState { IDLE, WALKING, EATING, SLEEPING }
var state: PetState = PetState.IDLE

# ==========================================
# EXPERIENCE (XP) SYSTEM
# ==========================================
var experience = 0
var collected_experience = 0
var speed := 150.0
@export var experience_level = 1
# Calculates how much XP is needed for the NEXT level right when the pet is created.
var experience_required = get_required_experience(experience_level + 1)

# _physics_process runs constantly (usually 60 times a second). 
# It's normally used for movement/gravity, but here it's just updating debug text.

# Feature Branch Edit: Added by Madeleine Banaszak for Assignment 2
@onready var exercise_bar = null
var exercise_value := 0.0
var exercise_fill_rate := 20.0
var exercise_decay_rate := 10.0

func _ready():
	call_deferred("_find_exercise_bar")
	
func _find_exercise_bar():
	exercise_bar = get_tree().get_root().get_node("MainScene/StatusUI/HBoxContainer/VBoxContainer/ExerciseBar")	

func _physics_process(_delta):
	# Converts the current state number (like 0) back into its text name (like "IDLE") for debugging
	var direction := 0

	# Movement input
	if Input.is_action_pressed("move_left"):
		direction = -1
	elif Input.is_action_pressed("move_right"):
		direction = 1
	else:
		direction = 0

	# Apply movement
	velocity.x = direction * speed
	move_and_slide()

	# Flip sprite
	if direction == -1:
		sprite.flip_h = true
	elif direction == 1:
		sprite.flip_h = false
	
	# Fill when moving, drain when idle
	if direction != 0:
		exercise_value += exercise_fill_rate * _delta
	else:
		exercise_value -= exercise_decay_rate * _delta

	# Clamp between 0 and 100
	exercise_value = clamp(exercise_value, 0, 100)

	# Update UI bar
	if exercise_bar:
		exercise_bar.value = exercise_value

	# Update debug label
	petDebugLabel.text = PetState.keys()[state]

# ==========================================
# SAVING AND LOADING
# ==========================================
# Packages all the pet's current data into a new "SavedPet" object to be saved to your hard drive.
func get_pet_save_data():
	var my_data = SavedPet.new()
	my_data.pet_resource =  resource
	my_data.hunger = pet_stats.hunger
	my_data.happiness = pet_stats.happiness
	my_data.hygiene = pet_stats.hygiene
	my_data.fun = pet_stats.fun
	my_data.social = pet_stats.social
	my_data.tiredness = pet_stats.tiredness
	my_data.cumulative_avg_stats = pet_stats.cumulative_avg_stats
	my_data.update_stats_count = pet_stats.update_stats_count
	my_data.feed_counter = pet_actions.feed_counter
	my_data.pet_counter = pet_actions.pet_counter
	my_data.poop_counter = pet_actions.poop_counter
	return my_data

# Takes a loaded save file ("saved_data") and unpacks it, overwriting the pet's current stats.
func update_to_save_data(saved_data:SavedData):
	resource = saved_data.pet_resource
	pet_stats.hunger = saved_data.hunger
	pet_stats.happiness = saved_data.happiness
	pet_stats.hygiene = saved_data.hygiene
	pet_stats.fun = saved_data.fun
	pet_stats.social = saved_data.social
	pet_stats.tiredness = saved_data.tiredness
	pet_stats.cumulative_avg_stats = saved_data.cumulative_avg_stats
	pet_stats.update_stats_count = saved_data.update_stats_count
	pet_actions.feed_counter = saved_data.feed_counter
	pet_actions.pet_counter = saved_data.pet_counter
	pet_actions.poop_counter = saved_data.poop_counter
	
# Applies the image stored inside the custom resource to the actual Sprite2D node.
func update_resource():
	sprite.texture = resource.texture

# ==========================================
# LEVELING MATH & LOGIC
# ==========================================
# Calculates the XP needed for a specific level using a math formula.
func get_required_experience(level):
	# pow(level, 1.2) means "level to the power of 1.2". 
	# The "+ 10" ensures even level 1 requires some XP.
	return round(pow(level, 1.2) + level * 2 + 10) 
	
# Called whenever the pet does something to earn XP.
func gain_experience(amount):
	collected_experience += amount
	experience += amount
	
	# We use a 'while' loop instead of 'if' just in case the pet gained a massive 
	# amount of XP at once and needs to level up multiple times in a row.
	while experience >= experience_required:
		experience -= experience_required # Deduct the required amount
		level_up() # Trigger a level up
		
	# Broadcast the new XP totals so UI bars can update.
	emit_signal('xpGained', experience_level, experience, experience_required)
		
# Increases the level, calculates the new XP requirement, and gives a reward.
func level_up():
	experience_level += 1
	experience_required = get_required_experience(experience_level + 1)
	award_coins_for_level_up(experience_level)
	
# Adds currency to a global script (an Autoload) based on the new level.
func award_coins_for_level_up(level):
	Global.coins += 3 + level
		
# Passive XP gain based on how well the player is taking care of the pet.
func gain_xp_based_on_stats(average_stats):
	# If average stats are below 50, the pet is unhappy/unhealthy, so no passive XP is given.
	if average_stats < 50:
		return
	# Formula to give more xp depending on average stat level. (1 xp at 50, up to 8 xp max).
	gain_experience(average_stats / 7 - 6)

# ==========================================
# MOVEMENT / ANIMATION
# ==========================================
# Brings the pet onto the screen smoothly using a "Tween".
func walk_into_scene():
	state = PetState.WALKING
	
	# Teleport the pet off-screen to the right (X: 600)
	global_position = Vector2(600, CENTER_POS.y)
	
	# Create a Tween. Tweens smoothly transition a value from A to B over time.
	var tween = get_tree().create_tween()
	# Smoothly slide the pet's position to CENTER_POS over 1 second.
	tween.tween_property(self, "global_position", CENTER_POS, 1)
	
	# Pause this specific function here until the movement is completely finished.
	await tween.finished
	
	# Now that it has arrived, stand still.
	state = PetState.IDLE
	
# Takes the pet off the screen smoothly.
func walk_out_of_scene():
	# If the pet is asleep, wake them up first.
	if state == PetState.SLEEPING:
		pet_actions.toggle_sleep()
		
	state = PetState.WALKING
	
	# Calculate a new position off-screen to the left (X: -50)
	var new_position = Vector2(-50, position.y)
	
	# Create a Tween to slide them to the left over 1 second.
	var tween = get_tree().create_tween()
	tween.tween_property(self, "global_position", new_position, 1)
	
	# Wait for the slide to finish.
	await tween.finished
	state = PetState.IDLE
