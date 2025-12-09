# Receiving Notifications

**Goal**: Verify web notifications are delivered as system notifications.

1.  **Precondition**: Permission granted.
2.  **Action**: Web page creates `new Notification("Title", { body: "Body" })`.
3.  **Expected Result**:
    -   macOS system notification appears with "Title" and "Body".
    -   Notification is attributed to Quiper.
