# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "Living Planet Civ Sim," a multiplayer voxel-based civilization simulation built with Godot 4.3+. The game focuses on emergent storytelling, where players spawn scattered across a dynamic, evolving planet and build societies through organic gameplay—no scripted quests or lore, all history emerges from player actions and environmental systems.

## Core Architecture

The project uses a **modular Component-Entity system** with the following key architectural patterns:

### World Generation System
- **ModularWorldGenerator** (`src/core/world/ModularWorldGenerator.gd`) - Main interface combining all generation components
- **Specialized Generators** in `src/core/world/generation/`:
  - `NoiseManager.gd` - Handles all noise generation with proper cylindrical wrapping
  - `BiomeGenerator.gd` - Temperature/moisture-based biome classification  
  - `HeightGenerator.gd` - Terrain height generation with continent/mountain systems
  - `ClimateGenerator.gd` - Climate patterns and seasonal variations
  - `ContinentGenerator.gd` - Large-scale landmass distribution

### Core Systems
- **WorldData** (`src/core/WorldData.gd`) - Autoload singleton containing global enums (Biome types)
- **Chunk System** - 16x16x256 voxel chunks with streaming for performance
- **Player System** - Modular player components in `src/core/player/`:
  - `PlayerController.gd` - Input handling and coordination
  - `PlayerMovement.gd` - Physics and movement (walking/flying modes)
  - `PlayerInteraction.gd` - World interaction and terrain editing
  - `ProficiencySystem.gd` - Skill progression through actions

### Simulation Layer
Components in `src/core/world/simulation/`:
- **WorldSimulation.gd** - Orchestrates all world systems
- **ChunkManager.gd** - Handles chunk loading/unloading around players
- **ThreadManager.gd** - Manages background processing for performance
- **GeneratorProxy.gd** - Thread-safe interface to world generators

### Advanced Systems
- **PlanetaryCycles** (`src/core/world/systems/`) - Environmental changes and events
- **ResourceSystem** - Dynamic resource spawning and depletion
- **Editor Plugins** in `addons/` - Development tools for world analysis and preview

## Development Commands

Since this is a Godot project, development is primarily done through the Godot Editor:

### Running the Project
```bash
# Open in Godot Editor (primary development method)
godot project.godot

# Run directly (headless/testing)
godot --main-scene scenes/main.tscn
```

### Key Development Tools
- **World Analyzer Plugin** - Analyze biome distribution and generation quality
- **World Preview Plugin** - Generate 2D previews of world generation
- **Setup Script** - `setup_project.sh` creates directory structure

## Key Architectural Decisions

### World Representation
- **Cylindrical World**: East-west wrapping for circumnavigation, no north-south wrap
- **Finite Grid**: 1024x1024 voxels (configurable, expandable via mods)
- **Organic Voxels**: Blended edges and curves, not blocky Minecraft-style
- **Sea Level**: Consistent at 28.0 units with dynamic ocean/land generation

### Generation Philosophy
- **Noise-Driven**: All generation uses FastNoiseLite with careful frequency tuning
- **Modular Components**: Each generator is independent but coordinated through ModularWorldGenerator
- **Performance-Conscious**: Preview modes and LOD systems for different quality levels
- **Deterministic**: Same seed produces identical worlds for multiplayer consistency

### Player Progression
- **Proficiency System**: Skills improve through repetition, not XP points
- **Emergent Traits**: Behavioral patterns unlock bonuses (e.g., frequent migration = speed boost)
- **Legacy Mechanics**: Player death leaves ruins and artifacts for future discovery

## Important Implementation Notes

### Coordinate Systems
- **World Coordinates**: Global x,z positions that wrap east-west
- **Chunk Coordinates**: 16x16 grid positions within chunks
- **Cylindrical Wrapping**: Use `fmod()` for east-west coordinate normalization

### Performance Considerations
- Always use **preview_mode** during development for faster iteration
- Chunk streaming loads/unloads based on player proximity
- Thread-safe generation through GeneratorProxy
- Verbose logging disabled by default (`verbose_logging = false`)

### Biome System
Current biomes (from WorldData.Biome enum):
- OCEAN, MOUNTAINS, TUNDRA, PLAINS, DESERT, JUNGLE, FOREST, SWAMP
- Classification based on temperature/moisture/height thresholds
- Ocean detection via continent noise threshold (-0.3)

### Integration Points
- **Main Scene**: `scenes/main.tscn` coordinates Player, World, and UI
- **Autoloads**: WorldData provides global access to enums and constants
- **Editor Plugins**: Use for development analysis and debugging

## Testing and Debugging

### Player Controls (for testing)
- WASD - Movement
- F - Toggle walking/flying mode  
- Left/Right Click - Terrain editing
- Q/E - Adjust edit strength
- T - Debug terrain editing

### Debug Information
- ModularWorldGenerator provides `get_debug_info()` for any world position
- Use `analyze_world_generation()` for statistical analysis
- World preview data available via `get_world_preview_data()`

## Common Development Tasks

### Adding New Biomes
1. Add enum value to `WorldData.Biome`
2. Update biome classification logic in `BiomeGenerator.gd`
3. Add visual materials in `assets/materials/`

### Modifying World Generation
1. Adjust noise parameters in respective generators
2. Use ModularWorldGenerator's tuning parameter system
3. Test with world analyzer plugin for balance

### Player System Extensions
1. Add new components to `src/core/player/`
2. Integrate through PlayerController coordination
3. Follow existing modular pattern

This codebase emphasizes **emergent complexity through simple, well-coordinated systems** rather than monolithic architectures.