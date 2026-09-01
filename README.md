# BehindTheWalls

A Roblox game project scaffold for a stealth-focused "behind the walls" survival or hide-and-seek style experience.

## Project structure

- `src/ServerScriptService/` - server-side game logic and bootstrapping
- `src/StarterPlayer/StarterPlayerScripts/` - client-side game UI and input handling
- `src/ReplicatedStorage/Shared/` - shared modules and configuration
- `default.project.json` - Rojo project sync configuration

## Current foundation

This repo now includes:

- a shared game configuration module
- a server bootstrap that handles matchmaking and round state
- a client bootstrap that creates a basic HUD
- a standard Roblox project layout ready for Studio / Rojo syncing

## Getting started

1. Install Rojo and sync this folder into a Roblox place.
2. Open the game in Roblox Studio.
3. Start with the server bootstrap in `src/ServerScriptService/Main.server.lua`.
4. Extend the shared config and gameplay systems under `src/ReplicatedStorage/Shared/`.

## Suggested next systems

- round timer and win conditions
- player spawn logic
- map generation or prebuilt arena layout
- chase / hide mechanics
- combat or interaction systems
- store / progression / lobby flow

## Notes

This repo is a clean development base and is ready for the actual game build to be added on top.
