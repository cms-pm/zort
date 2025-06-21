# Dev Mode Instructions

## Overview
The pool system includes a global dev mode toggle for controlling logging output.

## Usage

### Development Mode (Default)
```gdscript
PoolManager.dev_mode = true  # Shows all debug output
```

### Production Mode
```gdscript
PoolManager.dev_mode = false  # Silent operation
```

## Where to Set
Place this line early in your main scene or autoload:

```gdscript
# For production builds
PoolManager.dev_mode = false
```

## What It Controls
- Pool creation messages
- Object activation/deactivation logs
- Emitter status updates
- Player targeting confirmations
- Pool exhaustion warnings
- Statistics summaries

## Example Output

### Dev Mode ON:
```
🚀 SETTING UP POOL SYSTEM! 🚀
PoolManager: Ready
GamePoolSetup: Creating game pools... 🚀
Pool 'invisible_colliders' ready with 1500 objects
EmitterController: Starting up at (100, 100) 🎯
EmitterController: Found target! 🎮
✅ Pool system ready!
```

### Dev Mode OFF:
```
(Silent operation - no pool system logs)
```

## Recommendation
- Keep `dev_mode = true` during development
- Set `dev_mode = false` for production releases