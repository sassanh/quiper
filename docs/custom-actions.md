# Custom Actions & JS Scripting

Custom Actions let you automate workflows inside Quiper's web views using JavaScript scripts executed on demand. You can bind these actions to global or app-specific shortcuts to perform tasks like clicking a "New Chat" button, toggling "Incognito/Private" mode, copying chat content, or opening history sidebars.

---

## Technical Overview

When you trigger a Custom Action, Quiper reads its corresponding `.js` file and wraps the execution inside an asynchronous JavaScript block evaluated directly in the active web view:

```javascript
try {
  const wrapper = async () => {
    // Your Custom Action Script Content Goes Here
  };
  await wrapper();
  return "ok";
} catch (err) {
  return { quiperError: (err && err.message) ? err.message : String(err) };
}
```

If the script throws an error, the catch block intercepts it, prints it to the macOS logs, and triggers a system error beep to notify you.

---

## Pre-Injected Library Helpers

To handle dynamic web layouts that load items asynchronously, Quiper injects a custom utility function called **`waitFor`** into the script execution environment.

### `waitFor` Function Signature
```javascript
function waitFor(check, timeoutMs = 10)
```
*   **`check`:** A callback function returning `true` (when the condition is met) or `false`.
*   **`timeoutMs`:** The time (in milliseconds) before the promise rejects with a timeout error (default is 10ms).
*   **Mechanism:** Uses `window.requestAnimationFrame` to loop efficiently without locking the browser thread.

### Example Usage of `waitFor`
```javascript
// Wait for the main menu side drawer to open before clicking an option
await waitFor(() => document.querySelector("mat-sidenav.mat-drawer-opened"));
document.querySelector('button[aria-label="Temporary chat"]').click();
```

---

## Configuration & Keyboard Shortcuts

1.  Open **Settings (`⌘ ,`)** and navigate to the **Actions** tab.
2.  Define a new Action template (e.g. "New Chat" or "Toggle Private Session") and assign it a global keyboard shortcut (e.g., `⌘ N`).
3.  Go to the **Engines** tab, select an engine, and bind that Action template to a specific JavaScript snippet.
4.  When you press the shortcut, Quiper will evaluate the script bound to the active service engine.

---

## External Script Editing

For large scripts or when using custom IDEs (like VS Code or Cursor), you can edit your scripts directly on your file system:
*   **Path:** `~/Library/Application Support/app.sassanh.quiper.Quiper/ActionScripts/[ServiceID]/[ActionID].js`
*   **Quick Access:** In the **Engines** tab, next to the script input box, click **Open in Editor** (opens the `.js` file in your default code editor) or **Reveal in Finder**.
*   Quiper loads the script directly from this file path when triggered, so edits saved in your external editor apply immediately without restarting the app.

---

## Real-World Action Script Examples

Below are standard templates for default operations:

### 1. New Chat (Gemini)
Clicks the "New chat" button in Google's layout:
```javascript
const newChat = document.querySelector('a[aria-label="New chat"]');
if (!newChat || newChat.disabled) { 
  throw new Error("New chat button not found or disabled"); 
}
newChat.click();
```

### 2. Toggle Incognito / Private Mode (Claude)
Swaps query parameters and redirects the view:
```javascript
const url = new URL(window.location.href);

function openIncognito() {
  window.history.pushState(null, "", window.location.pathname + "?incognito" + window.location.hash);
}

if (url.search.includes('incognito')) {
  url.searchParams.delete('incognito');
  history.pushState(null, "", url.pathname + url.search + url.hash);
  const newChat = document.querySelector('a[href="/new"]');
  if (newChat) newChat.click();
  window.requestAnimationFrame(openIncognito);
} else {
  openIncognito();
}
```

### 3. Open Search History (ChatGPT)
Forces the sidebar open and clicks the "Search chats" button:
```javascript
function getHistoryButton() {
  return [
    ...document
      .querySelector('nav div[data-sidebar-item="true"]')
      ?.querySelectorAll("div") || [],
  ].find((div) => (div.textContent || "").trim() === "Search chats");
}

if (!getHistoryButton()) {
  document.querySelector('button[data-testid="open-sidebar-button"]').click();
  await waitFor(() => getHistoryButton(), 300);
  getHistoryButton().click();
} else {
  getHistoryButton().click();
}
```
