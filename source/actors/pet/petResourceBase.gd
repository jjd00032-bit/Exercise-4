# This script extends "Resource" instead of a Node or Node2D.
# Resources are data containers used to store and save data in Godot (like pet types, items, or stats).
extends Resource

# Registers "petResource" as a custom resource type in Godot.
# This allows you to right-click in your FileSystem panel and select "New Resource..." -> "petResource".
class_name petResource

# An enum (enumeration) creates a list of named values.
# Godot stores these internally as numbers (Monkey = 0, Capybara = 1),
# but enums let you select them by name in the Inspector panel.
enum AnimalType { Monkey, Capybara, Calcifer }

# ==========================================
# EXPORTED DATA PROPERTIES
# ==========================================
# @export displays these variables directly in the Godot Inspector panel, 
# making it easy to create different pets without writing new code.

# Allows choosing the animal species from the dropdown menu defined in AnimalType.
@export var animal: AnimalType

# Holds the 2D image/sprite texture for this specific pet type.
@export var texture: Texture2D

# Gives this pet species a default starting name.
@export var name: String = 'Grumpel'

# ==========================================
# HELPER FUNCTIONS
# ==========================================
# Converts the internal numerical ID of the enum (like 0 or 1) 
# into a human-readable text string (like "Monkey" or "Capybara").
func get_animal_type_name():
	return AnimalType.keys()[animal]
