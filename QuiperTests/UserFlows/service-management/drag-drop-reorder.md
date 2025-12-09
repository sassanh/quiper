# Visual Service Reordering (Drag & Drop)

## Overview
Users can reorder services by dragging and dropping service tabs in the main window, providing a visual and intuitive way to organize services.

## User Flow

### Preconditions
- Quiper is open with at least 2 services configured
- Services are displayed as tabs/segments in the window

### Steps

1. **Identify Service to Move**
   - User sees service tabs in the header (e.g., "ChatGPT", "Claude", "Gemini")
   - Wants to change the order (e.g., move "Gemini" to first position)

2. **Initiate Drag**
   - User clicks and holds on "Gemini" tab
   - Cursor changes to closed hand (grabbing cursor)
   - Tab visually responds to mouse down

3. **Drag to New Position**
   - User drags the tab left or right
   - As mouse moves over other tabs, they shift to make room
   - Visual feedback shows where tab will be dropped

4. **Drop in New Position**
   - User releases mouse button
   - Tab settles into new position
   - Other tabs adjust to final arrangement
   - Cursor returns to normal

5. **Verify New Order**
   - Services are now in new order
   - Active service remains the same (or respects the reorder)
   - New order persists across app restarts

### Alternative Flows

#### A1: Cancel Drag
- User presses Escape during drag
- Tab returns to original position
- No reordering occurs

#### A2: Drag Outside Window
- User drags tab outside the window bounds
- Drag is cancelled
- Tab returns to original position

### Expected Results
- Service order matches user's preference
- Visual feedback makes drag operation clear
- Order persists in settings
- Keyboard shortcuts (Cmd+1, Cmd+2, etc.) reflect new order

### Technical Notes
- This is the visual UI version of the reorder flow
- Complements the programmatic `reorder-services.md` flow
- Both flows should result in the same data model changes
