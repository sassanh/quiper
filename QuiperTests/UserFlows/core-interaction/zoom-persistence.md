# Zoom Level Persistence

**Goal**: Verify zoom levels are saved per service.

1.  **Precondition**: "LocalTest" service is active (default zoom 1.0).
2.  **Action**: User triggers **Zoom In** (e.g., `Cmd + +`).
3.  **Expected Result**: WebView content zooms in.
4.  **Action**: User switches to another service and back.
5.  **Expected Result**: "LocalTest" zoom level remains zoomed in.
