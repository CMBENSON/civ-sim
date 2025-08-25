# src/core/player/ProficiencySystem.gd
extends RefCounted
class_name ProficiencySystem

signal proficiency_gained(skill: Skill, amount: float, new_level: float)
signal trait_unlocked(trait_name: String, description: String)
signal breakthrough_achieved(skill: Skill, combination: Array)

enum Skill {
	MINING, CRAFTING, HUNTING, GATHERING, 
	BUILDING, TRADING, EXPLORING, SURVIVAL,
	COMBAT, FARMING, COOKING, LEADERSHIP
}

var proficiencies: Dictionary = {}
var traits: Dictionary = {}
var action_counts: Dictionary = {}
var recent_actions: Array = []
var breakthrough_combinations: Dictionary = {}

# Proficiency curves - diminishing returns
var base_gain_rates: Dictionary = {
	Skill.MINING: 1.0,
	Skill.CRAFTING: 1.2,
	Skill.HUNTING: 0.8,
	Skill.GATHERING: 1.5,
	Skill.BUILDING: 0.9,
	Skill.TRADING: 0.7,
	Skill.EXPLORING: 1.1,
	Skill.SURVIVAL: 0.8,
	Skill.COMBAT: 0.6,
	Skill.FARMING: 1.0,
	Skill.COOKING: 1.3,
	Skill.LEADERSHIP: 0.5
}

func _init():
	_initialize_proficiencies()
	_setup_breakthrough_combinations()
	_setup_trait_system()

func _initialize_proficiencies():
	"""Initialize all skills at level 0"""
	for skill in Skill.values():
		proficiencies[skill] = 0.0
		action_counts[skill] = 0

func _setup_breakthrough_combinations():
	"""Define combinations that give bonus XP"""
	breakthrough_combinations = {
		"stone_tools": [Skill.MINING, Skill.CRAFTING],
		"hunting_tools": [Skill.HUNTING, Skill.CRAFTING],
		"advanced_farming": [Skill.FARMING, Skill.CRAFTING, Skill.GATHERING],
		"trade_routes": [Skill.TRADING, Skill.EXPLORING],
		"fortification": [Skill.BUILDING, Skill.COMBAT],
		"survival_expert": [Skill.SURVIVAL, Skill.HUNTING, Skill.GATHERING]
	}

func _setup_trait_system():
	"""Define behavioral traits that emerge from actions"""
	# Traits are unlocked based on action patterns
	pass

func gain_proficiency(skill: Skill, base_amount: float = 1.0, context: Dictionary = {}):
	"""Gain proficiency in a skill with diminishing returns"""
	var current_level = proficiencies.get(skill, 0.0)
	
	# Calculate diminishing returns
	var diminishing_factor = 1.0 / (1.0 + current_level * 0.1)
	var base_rate = base_gain_rates.get(skill, 1.0)
	
	# Apply context modifiers
	var context_modifier = _calculate_context_modifier(skill, context)
	
	# Calculate final gain
	var gain = base_amount * base_rate * diminishing_factor * context_modifier
	
	# Apply gain
	proficiencies[skill] += gain
	action_counts[skill] += 1
	
	# Record recent action for pattern detection
	_record_recent_action(skill, context)
	
	# Check for breakthroughs
	_check_for_breakthroughs()
	
	# Check for trait unlocks
	_check_for_trait_unlocks()
	
	proficiency_gained.emit(skill, gain, proficiencies[skill])

func _calculate_context_modifier(skill: Skill, context: Dictionary) -> float:
	"""Calculate modifier based on context (biome, tools, etc.)"""
	var modifier = 1.0
	
	# Biome modifiers
	var biome = context.get("biome", WorldData.Biome.PLAINS)
	match skill:
		Skill.MINING:
			if biome == WorldData.Biome.MOUNTAINS:
				modifier += 0.2  # Better mining in mountains
		Skill.HUNTING:
			if biome == WorldData.Biome.FOREST or biome == WorldData.Biome.PLAINS:
				modifier += 0.15  # More animals to hunt
		Skill.GATHERING:
			if biome == WorldData.Biome.FOREST or biome == WorldData.Biome.JUNGLE:
				modifier += 0.25  # More resources to gather
		Skill.SURVIVAL:
			if biome == WorldData.Biome.TUNDRA or biome == WorldData.Biome.DESERT:
				modifier += 0.3  # Harsh biomes teach survival
	
	# Tool modifiers
	var tool_quality = context.get("tool_quality", 1.0)
	modifier *= tool_quality
	
	# Group modifier for some skills
	var group_size = context.get("group_size", 1)
	match skill:
		Skill.BUILDING, Skill.LEADERSHIP:
			if group_size > 1:
				modifier += min(group_size * 0.1, 0.5)  # Cap at 50% bonus
	
	return modifier

func _record_recent_action(skill: Skill, context: Dictionary):
	"""Record action for pattern detection"""
	var action = {
		"skill": skill,
		"timestamp": Time.get_unix_time_from_system(),
		"context": context
	}
	
	recent_actions.append(action)
	
	# Keep only last 100 actions
	if recent_actions.size() > 100:
		recent_actions.pop_front()

func _check_for_breakthroughs():
	"""Check if player discovered any breakthrough combinations"""
	for breakthrough_name in breakthrough_combinations:
		var required_skills = breakthrough_combinations[breakthrough_name]
		
		# Check if all required skills have been used recently
		var recent_skill_usage = {}
		var cutoff_time = Time.get_unix_time_from_system() - 300  # Last 5 minutes
		
		for action in recent_actions:
			if action.timestamp >= cutoff_time:
				recent_skill_usage[action.skill] = true
		
		# Check if breakthrough is achieved
		var breakthrough_achieved = true
		for required_skill in required_skills:
			if not recent_skill_usage.has(required_skill):
				breakthrough_achieved = false
				break
		
		if breakthrough_achieved and not traits.has(breakthrough_name):
			_unlock_breakthrough(breakthrough_name, required_skills)

func _unlock_breakthrough(breakthrough_name: String, skills: Array):
	"""Unlock a breakthrough combination"""
	traits[breakthrough_name] = {
		"type": "breakthrough",
		"skills": skills,
		"unlocked_at": Time.get_unix_time_from_system(),
		"bonus": 1.2  # 20% bonus when using these skills together
	}
	
	# Give bonus XP for the discovery
	for skill in skills:
		gain_proficiency(skill, 5.0)
	
	breakthrough_achieved.emit(skills[0], skills)
	print("ProficiencySystem: Breakthrough unlocked - ", breakthrough_name)

func _check_for_trait_unlocks():
	"""Check for behavioral traits based on action patterns"""
	var total_actions = 0
	for count in action_counts.values():
		total_actions += count
	
	if total_actions < 50:  # Need some actions before traits emerge
		return
	
	# Nomad trait - lots of exploring
	if not traits.has("nomad"):
		var explore_ratio = float(action_counts.get(Skill.EXPLORING, 0)) / total_actions
		if explore_ratio > 0.3:  # 30% of actions are exploring
			_unlock_trait("nomad", "Gains +10% movement speed from frequent travel", {
				"movement_speed_bonus": 0.1
			})
	
	# Specialist trait - focused on one skill
	if not traits.has("specialist"):
		for skill in proficiencies:
			var skill_ratio = float(action_counts.get(skill, 0)) / total_actions
			if skill_ratio > 0.5:  # 50% of actions in one skill
				_unlock_trait("specialist", "Gains +25% proficiency in primary skill", {
					"primary_skill": skill,
					"proficiency_bonus": 0.25
				})
				break
	
	# Social trait - lots of trading/leadership
	if not traits.has("social"):
		var social_actions = action_counts.get(Skill.TRADING, 0) + action_counts.get(Skill.LEADERSHIP, 0)
		var social_ratio = float(social_actions) / total_actions
		if social_ratio > 0.25:
			_unlock_trait("social", "Gains bonuses when working in groups", {
				"group_bonus": 0.15
			})

func _unlock_trait(trait_name: String, description: String, effects: Dictionary):
	"""Unlock a new behavioral trait"""
	traits[trait_name] = {
		"type": "behavioral",
		"description": description,
		"effects": effects,
		"unlocked_at": Time.get_unix_time_from_system()
	}
	
	trait_unlocked.emit(trait_name, description)
	print("ProficiencySystem: Trait unlocked - ", trait_name, ": ", description)

func get_skill_level(skill: Skill) -> float:
	"""Get current skill level"""
	return proficiencies.get(skill, 0.0)

func get_skill_modifier(skill: Skill, context: Dictionary = {}) -> float:
	"""Get total modifier for a skill including traits and breakthroughs"""
	var modifier = 1.0
	var skill_level = get_skill_level(skill)
	
	# Base skill bonus (higher level = better performance)
	modifier += skill_level * 0.01  # 1% per level
	
	# Trait bonuses
	for trait_name in traits:
		var trait_data = traits[trait_name]
		match trait_data.type:
			"behavioral":
				var effects = trait_data.get("effects", {})
				if effects.has("primary_skill") and effects.primary_skill == skill:
					modifier += effects.get("proficiency_bonus", 0.0)
				if effects.has("movement_speed_bonus") and skill == Skill.EXPLORING:
					modifier += effects.movement_speed_bonus
			"breakthrough":
				if skill in trait_data.skills:
					modifier += trait_data.get("bonus", 1.0) - 1.0  # Convert to additive
	
	return modifier

func get_proficiency_summary() -> Dictionary:
	"""Get summary of all proficiencies and traits"""
	return {
		"proficiencies": proficiencies.duplicate(),
		"traits": traits.duplicate(),
		"action_counts": action_counts.duplicate(),
		"total_actions": _get_total_actions()
	}

func _get_total_actions() -> int:
	var total = 0
	for count in action_counts.values():
		total += count
	return total
