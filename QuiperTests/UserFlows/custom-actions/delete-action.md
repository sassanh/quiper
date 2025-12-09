# Delete Custom Action

## Overview
Users remove custom actions they no longer need.

## User Flow

### Preconditions
- At least one custom action exists
- Settings is open to Actions tab

### Steps

1. **Select Action**
   - User clicks on action to delete

2. **Initiate Deletion**
   - User clicks "−" button at bottom of list
   - Confirmation dialog appears:
     - "Delete action '[Action Name]'?"
     - "This action and all its scripts will be removed."

3. **Confirm Deletion**
   - User clicks "Delete"
   - Action is removed from list
   - Detail pane clears

4. **Verify Deletion**
   - Action no longer appears in list
   - Keyboard shortcut is unregistered
   - Scripts are deleted from storage

### Alternative Flow

#### A1: Cancel Deletion
- User clicks "Cancel" in confirmation dialog
- Action remains unchanged

### Expected Results
- Action is permanently deleted
- Shortcut is freed for reuse
- Storage is cleaned up
