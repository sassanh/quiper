# Notification Permission Request

**Goal**: Verify web pages can request notification permissions.

1.  **Precondition**: "LocalTest" service is active.
2.  **Action**: Web page executes `Notification.requestPermission()`.
3.  **Expected Result**:
    -   System prompts user for notification permission for Quiper.
    -   Web page receives the result ('granted' or 'denied').
