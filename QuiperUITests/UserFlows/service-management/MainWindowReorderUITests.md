# Main Window Engine Reordering

**Goal**: Verify that users can reorder services directly within the Main Window's Service Selector using drag-and-drop.

1.  **Precondition**: 
    - App Main Window is visible.
    - Multiple engines are configured (Engine 1, 2, 3, 4).
2.  **Action**:
    - User drags the 3rd item (Engine 3) to the 1st position (Engine 1).
3.  **Expected Result**:
    - The items swap positions.
    - The 1st item is now verified to be Engine 3.
4.  **Action**:
    - User drags the 2nd item (Engine 1) to the 3rd position (Engine 2).
5.  **Expected Result**:
    - The items swap positions again.
    - The order reflects the change (Verified physically via coordinate tapping/checking labels).
