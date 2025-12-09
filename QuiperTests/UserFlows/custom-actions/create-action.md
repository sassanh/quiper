# Create Custom Action

## Overview
Users create custom JavaScript actions that can be triggered via keyboard shortcuts to automate tasks within services.

## User Flow

### Preconditions
- Quiper is running
- User has opened Settings
- At least one service is configured

### Steps

1. **Navigate to Actions Settings**
   - User opens Settings (Cmd+,)
   - Clicks on "Actions" tab
   - Sees list of existing custom actions (if any)

2. **Create New Action**
   - User clicks "+" button at bottom of actions list
   - New action appears in list with default name "Untitled Action"
   - Action detail pane opens on right side

3. **Configure Action Name**
   - User clicks on name field
   - Types descriptive name (e.g., "Start New Chat")
   - Name updates in the list

4. **Set Keyboard Shortcut**
   - User clicks "Record Shortcut" button
   - Presses desired key combination (e.g., Cmd+N)
   - System validates shortcut isn't already in use
   - Shortcut is saved

5. **Write Action Script for Service**
   - User sees service tabs (one for each configured service)
   - Clicks on first service tab (e.g., "ChatGPT")
   - Enters JavaScript code in the script editor:
     ```javascript
     document.querySelector('[data-testid="new-chat-button"]').click();
     ```
   - Script is auto-saved on blur

6. **Configure Additional Services** (Optional)
   - User switches to other service tabs
   - Writes service-specific scripts for each
   - Each service can have different implementation

7. **Test the Action**
   - User closes Settings
   - Opens Quiper to a service
   - Presses the configured shortcut (Cmd+N)
   - Action executes (e.g., new chat starts)

### Alternative Flows

#### A1: Delete Action
- User selects action from list
- Clicks "−" (delete) button
- Confirmation dialog appears
- User confirms deletion
- Action is removed

#### A2: Edit Existing Action
- User clicks on existing action in list
- Detail pane shows current configuration
- User modifies name, shortcut, or scripts
- Changes auto-save

#### A3: Shortcut Conflict
- User tries to assign shortcut already in use
- System shows error with conflict details
- User chooses different shortcut

### Expected Results
- Custom action is created and saved
- Action triggers correctly on shortcut press
- Different implementations work on different services
- Actions persist across app restarts

### Error Handling
- Invalid JavaScript shows error in console (if inspector enabled)
- Shortcut conflicts are prevented
- Empty action names are allowed but discouraged
- Script syntax errors don't crash the app
