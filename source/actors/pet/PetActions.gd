# This script manages all interactive actions you can perform on your pet (feeding, petting, cleaning, sleeping).
# It inherits from Node because it doesn't need its own 2D position or visual appearance.
extends Node

# Registers "PetActions" as a custom class name so other scripts can recognize it.
class_name PetActions

# ==========================================
# NODE REFERENCES & PRELOADS
# ==========================================
# get_parent() grabs the node directly above this one in the Scene Tree (which is the main Pet node).
@onready var pet = get_parent()

# "preload" loads scenes into memory as templates BEFORE the game even runs.
# We use .instantiate() on these later to spawn new items into the world.
@onready var itemScene = preload("res://source/objects/itemScene.tscn")
@onready var reactionScene = preload("res://source/utility/reaction.tscn")
@onready var poopItem = preload("res://source/objects/poop.tscn")

# Finds the main inventory UI node across the whole game using Godot's Group system.
@onready var inventoryUI = get_tree().get_first_node_in_group("InventoryUI")

# ==========================================
# COUNTERS & LIMITS
# ==========================================
# Keeps track of how many times actions have been spammed recently.
var feed_counter = 0
var pet_counter = 0
var poop_counter = 0

# Maximum action limits before negative consequences happen (like overfeeding making the pet sick).
var feed_limit = 4
var pet_limit = 10 # CHANGE - raised pet limit

# ==========================================
# SIGNALS
# ==========================================
# Emitted to inform other parts of the game (like UI/lighting) when the pet sleeps or eats.
signal sleepingToggled(sleeping)
signal itemConsumed(item)

# ==========================================
# INITIALIZATION
# ==========================================
# _ready() runs automatically once the node enters the scene.
func _ready():
	# Connects the inventory UI's signal to this script's feed() function.
	# When a player clicks food in the inventory, the feed() function fires automatically.
	inventoryUI.foodSelected.connect(feed)

# ==========================================
# ACTION ROUTER
# ==========================================
# Takes an action name (e.g. "feed", "love") and runs the corresponding function if the pet is ready.
func pet_action(action):
	# If the pet is currently sleeping, ignore all actions UNLESS the player is waking it up.
	if pet.state == pet.PetState.SLEEPING:
		if action == "sleep":
			toggle_sleep()
		return
		
	# Block new actions if the pet is busy walking or eating.
	if pet.state != pet.PetState.IDLE:
		print('pet not idle')
		return
		
	# Match statement acts like a clean switch/if-else tree based on the action string.
	match action:
		"feed":
			#feed() # Currently commented out here because feed() is triggered via inventoryUI signal instead
			pass
		"love":
			petting()
		"clean":
			clean()
		"fun":
			play()
		"social":
			socialize()
		"sleep":
			toggle_sleep()

# ==========================================
# FEEDING LOGIC
# ==========================================
func feed(food_item):
	# Don't allow eating while walking or already eating.
	if pet.state in [pet.PetState.WALKING, pet.PetState.EATING]:
		print('pet cant eat now')
		return
		
	# Spawn the physical food object on screen.
	var food = spawn_food(food_item)
	
	# Lock the pet in EATING state and play the animation.
	pet.state = pet.PetState.EATING
	pet.anim_player.play("Eating")
	
	# 'await' pauses this function execution right here until the animation fully completes.
	await pet.anim_player.animation_finished
	
	# Return pet back to IDLE state once done eating.
	pet.state = pet.PetState.IDLE
	
	# Delete the spawned food object from the scene tree.
	food.queue_free()
	
	# Roll dice for a chance to spawn poop after eating.
	random_poop_chance()
	
	# Tell the rest of the game the food item was consumed (so inventory can subtract 1).
	emit_signal("itemConsumed", food_item)
	
	# Calculate stat changes and reaction popups based on how full/overfed the pet is.
	handle_food_reaction()

# Spawns the visual 2D food node into the world near the pet.
func spawn_food(food_item):
	# Create a new instance (copy) of the item scene template.
	var food = itemScene.instantiate()
	food.item = food_item
	
	# Add the food object into the main scene tree alongside the pet.
	pet.get_parent().add_child(food)
	
	# Position the food slightly to the left of the pet's horizontal center.
	food.position = Vector2(pet.global_position.x - 35, 340)
	
	# Play a bobbing/bounce animation on the spawned item.
	food.bobble_anim()
	return food

# Applies stat penalties or bonuses based on overfeeding.
func handle_food_reaction():
	feed_counter += 1
	
	# Case 1: Overfed past limit or already at 0 hunger (pet pukes/gets sad).
	if feed_counter > feed_limit or pet.pet_stats.hunger == 0:
		print('feed counter 4: puke')
		pet.pet_stats.happiness -= 15
		pet.pet_stats.tiredness += 10
		reaction_popup('sad')
		return
		
	# Case 2: Hit exact feed limit or pet is nearly full.
	if feed_counter == feed_limit or pet.pet_stats.hunger < 10:
		reaction_popup('sick')
		pet.pet_stats.hunger -= 10
		pet.pet_stats.happiness -= 5
		pet.pet_stats.tiredness += 5
		return
		
	# Case 3: Normal successful feeding.
	reaction_popup('happy')
	pet.pet_stats.hunger -= 25 # Lowers hunger stat (closer to 0 is full)
	pet.pet_stats.happiness += 5
	pet.gain_experience(2)

# ==========================================
# INTERACTION ACTIONS
# ==========================================
func petting():
	pet_counter += 1
	
	# Penalty for over-petting (pet gets annoyed).
	if pet_counter > pet_limit:
		print('dont want pets now')
		reaction_popup('sick')
		pet.pet_stats.happiness -= 5
		return
		
	if pet_counter == pet_limit:
		reaction_popup('sick')
		print('enough pets')
		pet.pet_stats.happiness += 5
		return
		
	# Normal successful petting.
	reaction_popup('love')
	pet.pet_stats.happiness += 5 # CHANGE - lowered happiness amount per pet
	pet.gain_experience(2)

func clean():
	# If pet is already clean (>90 or >70), cleaning annoys them slightly.
	if pet.pet_stats.hygiene > 90:
		pet.pet_stats.fun -= 15
		pet.pet_stats.happiness -= 10
	elif pet.pet_stats.hygiene > 70:
		pet.pet_stats.fun -= 10
	# If pet was dirty (<30), cleaning makes them very happy!
	elif pet.pet_stats.hygiene < 30:
		pet.pet_stats.happiness += 15
		
	# Reset hygiene back to max (100).
	pet.pet_stats.hygiene = 100
	pet.gain_experience(1)
	pet_counter -= 3 # CHANGE - cleaning decreases pet counter

func play():
	pet.pet_stats.fun += 25
	pet.pet_stats.tiredness += 5
	pet.gain_experience(1)
	pet_counter -= 2 # CHANGE - playing decreases pet counter

func socialize():
	pet.pet_stats.social += 25
	pet.pet_stats.tiredness += 5
	pet.pet_stats.hunger += 5
	pet.gain_experience(1)

# Toggles the sleeping state back and forth.
func toggle_sleep():
	# Prevent sleeping if walking or eating.
	if pet.state in [pet.PetState.WALKING, pet.PetState.EATING]:
		return
		
	# Toggle state logic.
	if pet.state == pet.PetState.SLEEPING:
		pet.state = pet.PetState.IDLE
		pet_counter = 0 # CHANGE - sleeping resets pet counter
	else:
		pet.state = pet.PetState.SLEEPING
		
	# Signal out to notify other systems (like turning off room lights).
	emit_signal("sleepingToggled", pet.state)

# ==========================================
# POOP & REACTION SPAWNING
# ==========================================
# Determines if eating triggers a poop spawn.
func random_poop_chance():
	# The more poop already exists, the lower the chance of spawning another (1 in 3 + poop_counter).
	if randi_range(1, 3 + poop_counter) == 1:
		spawn_poop()

# Spawns a physical poop node on the floor.
func spawn_poop():
	pet.pet_stats.hygiene -= 10
	poop_counter += 1
	
	# Instantiate poop scene into the world.
	var poop = poopItem.instantiate()
	pet.get_parent().add_child(poop)
	
	# Connect the poop's internal signal to decrement the counter when the player cleans it up.
	poop.poop_removed.connect(poop_removed)
	
	# Position the poop near the pet's X coordinate with random variation.
	poop.position = Vector2(pet.global_position.x + randf_range(-200, 200), 355)

# Triggered when a poop object is clicked/cleaned by the player.
func poop_removed():
	poop_counter -= 1
	pet.pet_stats.happiness += 5

# Spawns floating emotion/reaction icons above the pet's head (e.g. hearts, angry face, sad face).
func reaction_popup(reaction):
	var reaction_instance = reactionScene.instantiate()
	pet.get_parent().add_child(reaction_instance)
	
	# Position reaction slightly above and offset from the pet's head.
	reaction_instance.position = Vector2(pet.global_position.x + randf() * 20, pet.global_position.y - randf_range(50, 80))
	
	# Pass the reaction type name (e.g., 'happy', 'sad') to set its icon/animation.
	reaction_instance.set_reaction(reaction)
