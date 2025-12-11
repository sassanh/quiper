# Template Management

**Goal**: Verify that users can add engines/actions from templates (individually or en masse) and erases them correctly.

1.  **Precondition**: 
    - Settings window is open.
    - Application state may contain existing engines/actions.
2.  **Action (Setup)**:
    - User interacts with "Erase All Engines" and "Erase All Actions" in General settings.
3.  **Expected Result**:
    - Engines and Actions lists are empty.
4.  **Action (Individual Add)**:
    - User adds each Engine template (ChatGPT, Gemini, Grok, etc.) one by one.
    - User adds each Action template (New Session, Share, etc.) one by one.
5.  **Expected Result**:
    - All added items appear in their respective lists.
6.  **Action (Bulk Add)**:
    - User erases all items again.
    - User clicks "Add All Templates" for Engines.
    - User clicks "Add All Templates" for Actions.
7.  **Expected Result**:
    - All default templates are populated simultaneously.
