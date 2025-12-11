# Service Order & Deletion Sync

**Goal**: Verify that reordering and deleting services in the Settings window correctly synchronizes with the Main Window state.

1.  **Precondition**: 
    - App launched with multiple engines (Engine 1, 2, 3, 4).
2.  **Action (Reorder in Settings)**:
    - User opens Settings > Engines.
    - User drags Engine 3 to the top.
    - User drags Engine 2 to the top.
    - Final Order in list: Engine 2, Engine 3, Engine 1, Engine 4.
3.  **Action (Verify Sync)**:
    - User closes Settings.
    - User checks the Main Window Service Selector.
4.  **Expected Result**:
    - The Service Selector segments match the new order (Active: Engine 2 at index 0, etc.).
5.  **Action (Delete)**:
    - User opens Settings > Engines.
    - User deletes Engine 4.
6.  **Expected Result**:
    - Engine 4 is removed from the list.
    - (Implicit) Engine 4 is removed from Main Window selector upon refresh.
