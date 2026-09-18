# This script manages the lifecycle of guest pets residing in a room:
# handles guest arrivals, calculates scheduled checkout times, triggers intro/outro UI popups,
# evaluates care quality, awards review ratings/coins, and manages save/load state.
extends Node

# ==========================================
# EXPORTED CONFIGURATION
# ==========================================
# Pool of pet species resources that can randomly visit this room.
@export var guest_pet_resources: Array[petResource]

# Scheduled duration (in hours) for the guest pet's stay.
@export var stay_duration_hours: int  # Duration in hours

# ==========================================
# NODE PRELOADS & REFERENCES
# ==========================================
# Preloaded scenes for the introduction and checkout summary UI popups.
@onready var petIntroductionUI = preload("res://source/ui/pet_introduction_ui.tscn")
@onready var petOutroUI = preload("res://source/ui/pet_outro_ui.tscn")

# Path to external JSON file containing review comments organized by star ratings.
@onready var reviews_json_path = "res://source/data/reviews.json"

# References to core scene controllers and nodes.
@onready var timeUI = get_tree().get_first_node_in_group("TimeUI")
@onready var _pet = get_parent().get_node("Pet")
@onready var roomManager = get_tree().get_root().get_node("MainScene/RoomManager")
@onready var roomScene = get_parent()

# ==========================================
# STATE & VARIABLES
# ==========================================
var current_guest_pet_resource = null
var pet_introduction_ui = null
var pet_outro_ui = null
var HOURS_PER_DAY = 20

# Dictionary storing the exact day, hour, and minute when the guest pet's stay ends.
var pet_exit_time = { "day": 0, "hour": 0, "minute": 0 }

# Flag tracking if a guest pet is currently active in this room.
var pet_introduced = false

# Dictionary holding loaded review strings parsed from reviews.json.
var reviews_data: Dictionary = {}

# ==========================================
# INITIALIZATION
# ==========================================
func _ready():
	# Brief delay to allow parent room setup to finish initializing.
	await get_tree().create_timer(1).timeout
	
	# Load review templates from JSON disk storage.
	reviews_data = load_json_file(reviews_json_path)
	if reviews_data.is_empty():
		push_error("Failed to load reviews data.")
		return
		
	# Listen to in-game time progression to check for pet departure.
	timeUI.time_tick.connect(check_if_stay_over)
	
	# If no guest pet is active upon loading, bring in a new guest!
	if !pet_introduced:
		introduce_guest_pet()

# ==========================================
# SAVE / LOAD SYSTEM INTEGRATION
# ==========================================
# Packs up guest manager data into a SavedPetManager snapshot object.
func get_pet_manager_save_data():
	var my_data = SavedPetManager.new()
	my_data.pet_resource = current_guest_pet_resource
	my_data.pet_exit_time = pet_exit_time
	my_data.stay_duration_hours = stay_duration_hours
	my_data.pet_introduced = pet_introduced
	return my_data

# Restores guest manager state from a loaded SavedPetManager snapshot.
func update_to_save_data(saved_data: SavedData):
	current_guest_pet_resource = saved_data.pet_resource
	pet_exit_time = saved_data.pet_exit_time
	stay_duration_hours = saved_data.stay_duration_hours
	pet_introduced = saved_data.pet_introduced

# Helper function to open and parse a JSON text file into a GDScript Dictionary.
func load_json_file(file_path: String):
	if FileAccess.file_exists(file_path):
		var data_file = FileAccess.open(file_path, FileAccess.READ)
		var parsed_result = JSON.parse_string(data_file.get_as_text())
		if parsed_result is Dictionary:
			return parsed_result
		else:
			print("Error reading file")
	else:
		print("File dosen't exist")

# ==========================================
# TIMING & DEPARTURE CHECKS
# ==========================================
# Compares current game clock against scheduled exit time.
func check_if_stay_over(day, hour, minute):
	if pet_introduced and day == pet_exit_time.day and hour == pet_exit_time.hour and minute == pet_exit_time.minute:
		_stay_over()

# Calculates future departure day, hour, and minute based on stay_duration_hours and current game clock.
func set_pet_exit_time():
	var stay_duration_days = int(stay_duration_hours / HOURS_PER_DAY)
	var hours = stay_duration_hours % HOURS_PER_DAY
	pet_exit_time.day = timeUI.day + stay_duration_days
	pet_exit_time.hour = timeUI.hour + hours
	pet_exit_time.minute = timeUI.minute

# ==========================================
# PET ARRIVAL & DEPARTURE FLOWS
# ==========================================
# Handles bringing a new random guest pet into the sanctuary.
func introduce_guest_pet():
	# Wait if another room is currently animating an entrance/exit queue.
	while roomManager.queue_processing:
		await get_tree().create_timer(1).timeout
	roomManager.queue_processing = true
	
	# Pick a random pet species from the guest resources array.
	current_guest_pet_resource = guest_pet_resources[randi() % guest_pet_resources.size()]
	
	# Assign random stay duration between 1 and 10 hours.
	stay_duration_hours = randi_range(1, 10)
	set_pet_exit_time()
	print('exit time:', pet_exit_time)
	
	# Display introduction UI dialog.
	show_pet_intro(current_guest_pet_resource)
	
	# Configure pet node with species data and reset stats.
	_pet.resource = current_guest_pet_resource
	_pet.pet_stats.reset_stats()
	
	# Play entrance animation.
	await _pet.walk_into_scene()
	
	pet_introduced = true
	roomManager.queue_processing = false
	
	# Record visitor species in global tracking history.
	Global.add_visitor_to_array(_pet.resource.get_animal_type_name())

# Spawns and configures the introduction popup UI dialog.
func show_pet_intro(pet_data):
	roomManager.switch_to_room(roomScene)
	var pet_details = {
		"image": pet_data.texture,
		"name": pet_data.name,
		"animal": pet_data.get_animal_type_name(),
		"days": int(stay_duration_hours / HOURS_PER_DAY),
		"hours": stay_duration_hours % HOURS_PER_DAY
	}
	pet_introduction_ui = petIntroductionUI.instantiate()
	get_tree().get_root().add_child.call_deferred(pet_introduction_ui)
	await pet_introduction_ui.ready
	pet_introduction_ui.set_pet_info(pet_details)

# Spawns and displays checkout summary UI dialog showing star rating and coins awarded.
func show_pet_outro(pet_details):
	roomManager.switch_to_room(roomScene)
	pet_outro_ui = petOutroUI.instantiate()
	get_tree().get_root().add_child(pet_outro_ui)
	pet_outro_ui.set_pet_info(pet_details)
	await pet_outro_ui.tree_exited

# Triggered when checkout time arrives: calculates care review, awards payout, and spawns next guest.
func _stay_over():
	while roomManager.queue_processing:
		await get_tree().createtimer(1).timeout
	roomManager.queue_processing = true
	
	# Evaluate pet care quality based on average stats during stay.
	var pet_stay_details = get_pet_stay_details(current_guest_pet_resource)
	
	# Store review entry in global review list.
	Global.reviewsInfo.append(pet_stay_details)
	
	# Display departure summary UI and animate exit.
	await show_pet_outro(pet_stay_details)
	await _pet.walk_out_of_scene()
	
	pet_introduced = false
	roomManager.queue_processing = false
	
	# Automatically queue up the next visiting pet!
	introduce_guest_pet()

# ==========================================
# EVALUATION & REWARD COMPUTATION
# ==========================================
# Compiles overall care metrics (stars, review string, and coin payout) into a single dictionary.
func get_pet_stay_details(pet_data):
	var average_stats = _pet.pet_stats.get_overall_average_stats()
	var star_rating = get_star_rating(average_stats)
	var review = evaluate_care(star_rating)
	var coin_amount = calculate_coins_reward(star_rating)
	
	var pet_details = {
		"image": pet_data.texture,
		"name": pet_data.name,
		"animal": pet_data.get_animal_type_name(),
		"days": int(stay_duration_hours / HOURS_PER_DAY),
		"hours": stay_duration_hours % HOURS_PER_DAY,
		"stats": round(average_stats),
		"review": review,
		"star_rating": star_rating,
		"coins": coin_amount
	}
	return pet_details

# Selects a random review string from reviews.json matching the earned star rating.
func evaluate_care(rating: int) -> String:
	var all_rating_reviews = reviews_data[str(rating)]
	return all_rating_reviews[randi() % all_rating_reviews.size()]

# Converts overall average stat percentage (0-100%) into a 1 to 5 star rating.
func get_star_rating(average_stats):
	return int(average_stats / 20) + 1

# Calculates coin payout based on stay length and star rating performance (3 stars = baseline 100%).
func calculate_coins_reward(star_rating):
	var precentage_per_star = 20
	var reward = int(stay_duration_hours * (1 + (star_rating - 3) * precentage_per_star / 100))
	return reward
