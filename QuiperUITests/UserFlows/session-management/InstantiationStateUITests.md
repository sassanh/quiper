# Session Instantiation State

**Goal**: Verify that uninstantiated sessions appear visually grayed out and that Cmd+W uninstantiates the current session and navigates to the nearest instantiated one.

1.  **Precondition**:
    - App launched with at least one service. Only the first session (1) is active and instantiated.
2.  **Expected Result (initial state)**:
    - Session 1 segment appears in normal color (instantiated).
    - Sessions 2–0 segments appear visually grayed out (uninstantiated).
3.  **Action (instantiate a second session)**:
    - User switches to Session 2.
4.  **Expected Result**:
    - Session 2 segment updates to normal color.
    - Sessions 3–0 remain grayed out.
5.  **Action (Cmd+W on Session 2)**:
    - User presses **Cmd+W** while Session 2 is active.
6.  **Expected Result**:
    - Session 2 is uninstantiated (grayed out again).
    - App navigates to Session 1 (nearest instantiated session to the left).
    - Session 1 is selected and shown.
7.  **Action (Cmd+W with only one instantiated session)**:
    - Only Session 1 is instantiated. User presses **Cmd+W**.
8.  **Expected Result**:
    - Session 1 is uninstantiated.
    - App falls back to Session 1 (session index 0) even though it is now uninstantiated.
    - All session segments appear grayed out.
9.  **Action (Cmd+W navigates across services)**:
    - Service A / Session 1 is the only instantiated session on Service A.
    - Service B / Session 3 is instantiated.
    - User presses **Cmd+W** on Service A / Session 1.
10. **Expected Result**:
    - Service A / Session 1 is uninstantiated.
    - App switches to Service B and selects Session 3 (nearest instantiated session on an adjacent service).
