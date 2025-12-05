# WaterSalute Resources

This folder should contain the following OBJ models:

1. `firetruck.obj` - Fire truck 3D model
2. `waterjet.obj` - Animated water stream model (RECOMMENDED)
3. `waterdrop.obj` - Water particle 3D model (fallback)

## Model Requirements

### firetruck.obj
- 8x8 fire truck model
- Origin at center bottom
- Facing +Z direction (forward)
- Scale: 1 unit = 1 meter
- Size: approximately 10m long, 2.5m wide, 4m tall

### waterjet.obj (RECOMMENDED - Better Performance)
The plugin will first try to load this animated water stream model.
This approach uses a single OBJ per truck with dataref-driven animations,
which is more performant than spawning hundreds of particle instances.

Requirements:
- Water stream/jet model
- Origin at nozzle base (where water exits)
- Stream pointing in +Z direction (will be rotated to match cannon)
- Animations controlled by these datarefs:
  - `watersalute/waterjet/active` (float 0-1): Controls visibility
  - `watersalute/waterjet/intensity` (float 0-1): Controls spray width/volume
- Scale: 1 unit = 1 meter
- Stream length: approximately 30-40m (to create arch effect)

Animation Tips:
- Use SHOW/HIDE dataref animation for active state
- Use SCALE or similar for intensity variation
- Consider using multiple mesh layers with different opacity for spray effect

### waterdrop.obj (Fallback - Particle System)
If waterjet.obj is not found, the plugin falls back to a particle system
using this water droplet model. Many instances are spawned and animated.

Requirements:
- Small water droplet/sphere
- Origin at center
- Size: approximately 0.1-0.2m diameter
- Semi-transparent blue material recommended

## Performance Comparison

| Method | Instances | Performance | Visual Quality |
|--------|-----------|-------------|----------------|
| waterjet.obj (animated stream) | 2 (one per truck) | Excellent | High (smooth stream) |
| waterdrop.obj (particles) | ~400 (200 per truck) | Moderate | Good (individual drops) |

## Obtaining Models

You can use the models from the WaterSalute C++ plugin (fountains.zip) 
or create your own compatible models.

The plugin will log which water effect mode is being used on startup.
If no water models are found, trucks will still move but won't spray water.
