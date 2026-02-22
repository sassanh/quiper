# Window Size Toggle UI Tests

## Overview
Tests for the window size toggle feature - a fixed (non-configurable) keyboard shortcut to toggle between two window sizes and positions.

## Shortcut
**Cmd+M** - Toggles between compact and large window modes (M for minimize)

## Window Modes

### Compact Mode  
- **Size:** 550×400 pixels (fixed)
- **Position:** Top-right corner with 20px padding from screen edges
- **Use case:** Keep window accessible while working with other apps

### Previous Mode
- **Size:** Restores to whatever size/position the window had before entering compact mode
- **Fallback:** If no previous frame exists, uses default 800×620 centered
- **Use case:** Return to your preferred working size

## Implementation Details

### Files Modified
- `Quiper/MainWindowController.swift`

### Changes Made

1. **Added window toggle state tracking:**
   ```swift
   // Window size toggle state
   private var isCompactMode = false
   private var previousWindowFrame: NSRect?
   ```

2. **Added keyboard shortcut handler:**
   ```swift
   switch key {
   case "m":
       toggleWindowSize()
       return true
   ```
   ```

3. **Implemented `toggleWindowSize()` method:**
   ```swift
   func toggleWindowSize() {
       guard let window = window else { return }
       
       let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
       
       if isCompactMode {
           // Restore to previous size/position, or use default if no previous frame
           let targetFrame: NSRect
           if let previous = previousWindowFrame {
               targetFrame = previous
           } else {
               // Default fallback size (800x620, centered)
               let width: CGFloat = 800
               let height: CGFloat = 620
               let x = screenFrame.midX - (width / 2)
               let y = screenFrame.midY - (height / 2)
               targetFrame = NSRect(x: x, y: y, width: width, height: height)
           }
           
           window.setFrame(targetFrame, display: true, animate: true)
           isCompactMode = false
           previousWindowFrame = nil // Clear saved frame after restoration
       } else {
           // Save current frame before switching to compact mode
           previousWindowFrame = window.frame
           
           // Switch to compact mode: 550x400, positioned at top-right
           let width: CGFloat = 550
           let height: CGFloat = 400
           let padding: CGFloat = 20
           let x = screenFrame.maxX - width - padding
           let y = screenFrame.maxY - height - padding
           
           let newFrame = NSRect(x: x, y: y, width: width, height: height)
           window.setFrame(newFrame, display: true, animate: true)
           isCompactMode = true
       }
       
       // Update layout after resize
       layoutSelectors()
   }
   ```

## Testing Instructions

1. Build and run the app
2. Press **Cmd+M** to toggle between window modes
3. Verify:
   - First toggle: Window moves to top-right corner and becomes smaller
   - Second toggle: Window returns to center and becomes larger
   - Animation is smooth
   - Layout adjusts correctly after each toggle

## Notes

- This is a **fixed shortcut** and is **not configurable** in Settings as requested
- The shortcut works whenever the main window is focused
- Uses smooth animation when transitioning between modes
- Automatically calls `layoutSelectors()` to ensure UI elements are properly positioned after resize
- Screen bounds are detected automatically to position the compact mode correctly on any display
