# Daily Workflow & Keyboard Reference

Quiper is designed to be operated almost entirely from your keyboard, letting you summon, navigate, and dismiss your AI tools in seconds without breaking your workflow focus.

---

## Summoning and Dismissing the Overlay

*   **To Summon:** Press **`⌥ Space`** (Option + Space) on any screen. The Quiper window will slide into focus immediately over your active workspace.
*   **To Hide / Dismiss:**
    *   Press **`⌥ Space`** again.
    *   Or press **`⌘ H`** (Command + H).
    *   Or press **`⌘ Q`** (Command + Q).
*   **Workflow Focus Restoration:** When Quiper is dismissed, it automatically returns keyboard focus to the application you were using immediately before summoning it, allowing you to resume typing without clicking back.

> [!NOTE]
> Standard `⌘ Q` is intercepted to *hide* the overlay rather than quit the application, preventing you from accidentally shutting down your background AI assistant. To quit the application completely, see the System actions below.

---

## Core Concepts: Engines vs. Sessions

Quiper divides your workspaces into two hierarchical layers:

1.  **Engines (Services):** These represent distinct AI models/websites (e.g., Gemini, Claude, ChatGPT, or local Ollama instances). You can configure up to 10 active engines in your main selector bar.
2.  **Sessions (Slots):** Each engine maintains **10 independent persistent sessions** (also referred to as slots). Unlike typical browser tabs that discard state when closed, all 10 slots remain active in memory. This lets you keep separate conversations open concurrently without page refreshes.

---

## Prompt History HUD

It happens to the best of us: you write a masterpiece of a prompt, hit submit, and it vanishes into thin air because of a network error or connection timeout. Quiper has your back.

Through its native Prompt History Heads-Up Display (HUD) overlay, Quiper preserves your prompts in real-time. You can quickly search, copy, restore, or delete your previous prompts in a flash.

*   **To Open/Close HUD:** Press **`⌘ Y`** (Command + Y) while the overlay is visible.
*   **Search:** Simply type into the search bar at the top to filter past prompts in real-time.
*   **Restore Prompt:** Use the Up/Down arrow keys to highlight a prompt and press **`Enter`** (or click the row) to insert it back into the active chat session's input field.
*   **Copy to Clipboard:** Highlight a prompt and press **`⌘ C`** (or click the copy pill `[ 📄 ⌘C ]`) to copy the text.
*   **Delete Entry:** Highlight a prompt and press **`⌘ ⌫`** (or click the trash pill `[ 🗑️ ⌘⌫ ]`) to permanently remove it from history.
*   **Clear All History:** Press **`⌘ K`** (or click the "Clear All" button) to wipe out the history for the active session.

---

## Complete Keyboard Shortcuts Reference

Below is the exhaustive reference of Quiper's keyboard shortcuts, grouped by category.

### 1. Global & Overlay Control

| Action | Shortcut | Scope | Description |
| :--- | :--- | :--- | :--- |
| **Summon / Dismiss Window** | `⌥ Space` | Global | Toggles the visibility of the overlay window. |
| **Toggle Window Size** | `⌘ M` | In-App | Switches between a centered Standard layout and a top-right Compact layout. |
| **Open Settings** | `⌘ ,` | In-App | Opens the native SwiftUI Settings panel. |
| **Toggle Prompt History HUD** | `⌘ Y` | In-App | Toggles the native Prompt History HUD overlay. |
| **Quit Quiper** | `⌘ ⌃ ⇧ Q` | In-App | Completely shuts down the Quiper application. |

*Note: When running under Xcode debugger, standard `⌘ Q` will quit the application directly.*

### 2. Session Navigation & Slots

Each engine has 10 independent tabs (slots) kept hot in memory.

| Action | Shortcut | Alternate | Description |
| :--- | :--- | :--- | :--- |
| **Switch Session Slot** | `⌘ 1` … `⌘ 0` | — | Switches to session slots 1 through 10 (`⌘ 0` maps to Slot 10). |
| **Next Session** | `⌘ ⇧ →` | `⌘ L` | Moves to the session slot to the right. |
| **Previous Session** | `⌘ ⇧ ←` | `⌘ H` | Moves to the session slot to the left. |
| **Close Session** | `⌘ W` | — | Closes the active session slot, clearing its web view state. |

> [!TIP]
> - Pressing **`⌘ W`** on the last open session of an engine will close it and automatically switch you to the nearest engine with active sessions (if *Automatically Switch Engine on Last Session Close* is enabled in Settings).
> - You can also close any session by **middle-clicking** its tab segment.

### 3. Engine Navigation

| Action | Shortcut | Alternate | Description |
| :--- | :--- | :--- | :--- |
| **Switch Engine** | `⌘ ⌃ 1` … `⌘ ⌃ 0` | `⌘ ⌥ 1` … `⌘ ⌥ 0` | Instantly switches to service engines 1 through 10. |
| **Next Engine** | `⌘ ⌃ →` | `⌘ ⌃ L` | Switches to the next configured service engine. |
| **Previous Engine** | `⌘ ⌃ ←` | `⌘ ⌃ H` | Switches to the previous configured service engine. |

> [!TIP]
> You can **middle-click** any engine segment to close all active sessions for that service (requires confirmation if multiple sessions are active).

### 4. Web View Control & Zoom

Standard web controls mapped to your native WebKit view contexts.

| Action | Shortcut | Alternate | Description |
| :--- | :--- | :--- | :--- |
| **Reload Page** | `⌘ R` | — | Reloads the active web view session. |
| **Force Reload** | `⌘ ⇧ R` | — | Re-instantiates the active WebKit context from scratch. |
| **Reload from Origin** | `⌘ ⌥ R` | — | Bypasses cached files and reloads the page. |
| **Toggle Web Inspector** | `⌘ ⌥ I` | — | Opens the WebKit Developer Tools / Safari Web Inspector. |
| **Zoom In** | `⌘ +` (or `⌘ =`) | `⌘ [Keypad +]` | Increases the text and element size of the active web view. |
| **Zoom Out** | `⌘ -` | `⌘ [Keypad -]` | Decreases the text and element size of the active web view. |
| **Reset Zoom** | `⌘ ⇧ Delete` | `⌘ ⇧ ⌫` | Resets the zoom level back to the default 100%. |

### 5. Find in Page

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Find in Page** | `⌘ F` | Opens the native search panel at the top of the chat web view. |
| **Find Next** | `⌘ G` | Jumps to the next search result. |
| **Find Previous** | `⌘ ⇧ G` | Jumps to the previous search result. |

### 6. Standard Text Editing

These standard macOS text manipulation shortcuts are fully supported inside the chat web views:

*   **Undo:** `⌘ Z`
*   **Redo:** `⌘ ⇧ Z`
*   **Cut:** `⌘ X`
*   **Copy:** `⌘ C`
*   **Paste:** `⌘ V`
*   **Select All:** `⌘ A`

### 7. Default Custom Actions (JS Scripts)

Quiper comes pre-configured with four powerful custom scripts triggered by default keyboard shortcuts. You can customize the JavaScript for these scripts on a per-engine basis under **Settings ➔ Actions**:

| Custom Action | Shortcut | Default Intent |
| :--- | :--- | :--- |
| **New Session** | `⌘ N` | Resets/clears the active chat or starts a new thread. |
| **New Temporary Session** | `⌘ ⇧ N` | Starts a temporary, non-persisted chat slot. |
| **Share** | `⌘ ⇧ S` | Generates a shareable URL link for the active thread. |
| **History** | `⌘ ⇧ H` | Toggles or opens the conversation history list of the engine. |

---

## Customizing Keyboard Shortcuts

If you prefer to use your own shortcuts, open **Settings (`⌘ ,`) ➔ Shortcuts**:

*   **Global Summon Hotkey:** Bind a custom key combination to open Quiper from any screen.
*   **App Shortcuts:** Modify the primary and alternate bindings for next/prev session/engine commands.
*   **Digit Modifiers:** Swap out the modifier keys used to jump directly to session slots and engine numbers.
*   **Engine Hotkeys:** Register custom global or in-app hotkeys to launch or focus specific engines directly.
*   **Custom Action Shortcuts:** Remap or assign keys to trigger your custom JavaScript macros.
