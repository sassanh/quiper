# Adding a Service

**Goal**: Verify a user can add a new service configuration.

1.  **Precondition**: Settings window is open.
2.  **Action**: User clicks **Add Service**.
3.  **Action**: User fills in details:
    -   Name: "NewService"
    -   URL: "http://localhost:8000/new"
    -   Focus Selector: "#input"
4.  **Action**: User saves.
5.  **Expected Result**:
    -   "NewService" appears in the service list.
    -   User can switch to "NewService" in the overlay.
