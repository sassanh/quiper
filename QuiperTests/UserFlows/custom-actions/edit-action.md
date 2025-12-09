# Edit Custom Action

## Overview
Users modify existing custom actions to change their name, keyboard shortcut, or JavaScript implementation.

## User Flow

### Preconditions
- Quiper is running with at least one custom action created
- User has opened Settings

### Steps

1. **Select Action to Edit**
   - User opens Settings → Actions tab
   - Sees list of custom actions
   - Clicks on action to edit (e.g., "Start New Chat")

2. **Modify Action Name**
   - User clicks on the name field
   - Changes name (e.g., "Start Fresh Conversation")
   - Name updates immediately

3. **Change Keyboard Shortcut**
   - User clicks on current shortcut display
   - Enters recording mode
   - Presses new key combination
   - Shortcut updates if valid

4. **Update Script Implementation**
   - User switches to service tab
   - Modifies JavaScript code
   - Code auto-saves on blur or tab switch

5. **Test Changes**
   - User closes Settings
   - Presses updated shortcut
   - Verifies new implementation works

### Expected Results
- Action updates are applied immediately
- Old shortcut is unregistered
- New shortcut triggers updated script
- Changes persist across app restarts
