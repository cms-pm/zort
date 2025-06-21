# Pool System Troubleshooting Memory

## Issue: Objects Returning to Previous Positions After Pool Reuse

**Date**: 2025-01-20  
**Problem**: Objects being fired from emitter were starting from their last known position instead of emitter position when retrieved from pool after being returned.

---

## Key Learnings & Solutions

### 🎯 **#1 CRITICAL: RigidBody2D Position Property (MAJOR FIX)**
**Problem**: Using `position = start_pos` instead of `global_position` for RigidBody2D objects  
**Root Cause**: RigidBody2D objects require `global_position` for proper positioning, `position` property doesn't work reliably  
**Fix**: Changed all launch methods to use `global_position = start_pos`  
**Impact**: This was likely the primary cause of position persistence issues  

```gdscript
// WRONG:
position = start_pos

// CORRECT:
global_position = start_pos
reset_physics_interpolation()  // Clear interpolation memory
```

### 🔧 **#2: Duplicate Pool Manager Detection**
**Problem**: Two pool managers were being created (scene + script)  
**Symptom**: Objects would appear to vanish immediately after firing  
**Fix**: Use existing scene node instead of creating new one  
**Lesson**: Always check for existing scene nodes before creating programmatically  

### 🔧 **#3: Physics Interpolation Memory**
**Problem**: RigidBody2D "remembers" previous positions through physics interpolation  
**Fix**: Call `reset_physics_interpolation()` in launch methods and pool reset  
**Lesson**: Physics bodies need explicit interpolation clearing when teleporting  

### 🔧 **#4: Immediate Velocity Stopping**
**Problem**: Objects continued moving after pool return causing position drift  
**Fix**: Stop velocity immediately in `pool_deactivate()` before deferred operations  
**Lesson**: Stop physics movement immediately, don't rely on deferred operations for critical state  

### 🔧 **#5: Activation/Deactivation Timing**
**Problem**: Objects not properly unfrozen when retrieved from pool  
**Fix**: Immediate unfreeze in activation, proper deferred reset in deactivation  
**Lesson**: Activation should be immediate, deactivation can be deferred for safety  

---

## Files Modified

- `scripts/main_pool_integration.gd` - Removed duplicate pool creation
- `scripts/pool_system/pool_manager.gd` - Improved activation/deactivation sequence  
- `scripts/pool_system/invisible_collider.gd` - **Fixed position property usage**
- `scripts/pool_system/emitter_controller.gd` - Added debugging

---

## Key Debugging Techniques Used

1. **Pool state tracking** - Monitor active vs available object counts
2. **Position tracking** - Log object positions at key lifecycle points  
3. **Velocity monitoring** - Track linear_velocity persistence
4. **Timing analysis** - Test immediate vs deferred operations
5. **Race condition testing** - Force immediate object reuse

---

## Important Notes for Future

- **Always use `global_position` for RigidBody2D positioning**
- **Call `reset_physics_interpolation()` when teleporting physics objects**
- **Stop physics movement immediately, don't defer critical state changes**
- **Check for existing scene nodes before creating programmatically**
- **Test both collision and timeout scenarios for pool objects**

---

## Verification Commands

```bash
# Test pool system
timeout 10 godot --headless scenes/Main.tscn

# Look for these success indicators:
# - "Position reset working correctly" 
# - Objects start at emitter position (100.0, 100.0)
# - Objects reset to off-screen (0.0, 999999.0) when returned
# - No velocity persistence between cycles
```

---

**Bottom Line**: The `global_position` fix was the primary solution, with supporting fixes for timing, interpolation, and state management ensuring robust object reuse.