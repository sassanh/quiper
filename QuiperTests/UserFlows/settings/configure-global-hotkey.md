# Global Hotkey Configuration

## Overview
Users configure the main global keyboard shortcut that activates Quiper from anywhere in macOS.

## User Flow

### Preconditions
- Quiper is installed
- User has opened Settings

### Steps

1. **Navigate to Shortcuts Settings**
   - User opens Settings (Cmd+,)
   - Clicks on "Shortcuts" tab
   - Sees "Global Hotkey" section at the top

2. **View Current Hotkey**
   - User sees current hotkey (default: Cmd+Shift+Space)
   - Reads description: "Activate Quiper from anywhere in macOS"

3. **Change Hotkey**
   - User clicks on the shortcut button
   - Button enters recording mode: "Press keys..."
   - User presses desired key combination (e.g., Cmd+Option+Q)

4. **Validate Shortcut**
   - System validates the shortcut:
     - Must include at least one modifier (Cmd, Ctrl, Option, Shift)
     - Cannot be a system reserved shortcut
     - Cannot conflict with service launch shortcuts
   - Shows validation feedback

5. **Save and Test**
   - Valid shortcut is saved immediately
   - User closes Settings
   - Tests new hotkey by pressing it
   - Quiper activates successfully

### Alternative Flows

#### A1: Reset to Default
- User clicks "Reset" button
- Hotkey returns to default (Cmd+Shift+Space)
- Confirmation message appears

#### A2: Invalid Shortcut
- User tries invalid combination (e.g., just "A" without modifiers)
- System shows error: "Shortcut must include at least one modifier key"
- Button returns to previous valid shortcut
- User can try again

#### A3: System Shortcut Conflict
- User tries to use Cmd+Tab (system reserved)
- System shows error: "This shortcut is reserved by the system"
- Cannot be saved

### Expected Results
- Global hotkey changes to user's preference
- Hotkey works system-wide (in any app, on any desktop)
- Hotkey persists across app restarts and system reboots
- Previous hotkey is immediately unregistered

### Error Handling
- Invalid shortcuts are rejected before saving
- System shortcuts cannot be captured
- If hotkey registration fails, user is notified
- Fallback to previous working shortcut on error
