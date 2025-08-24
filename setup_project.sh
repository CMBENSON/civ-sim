#!/bin/bash

# Living Planet Civ Sim - Project Setup Script

echo "Setting up Living Planet Civ Sim project structure..."

# Create main directory structure
mkdir -p src/{main,world,entities,systems,networking,persistence,ui,audio,utils}
mkdir -p src/world/{chunks,generation,environment,resources}
mkdir -p src/entities/{player,animals,items,structures}
mkdir -p src/