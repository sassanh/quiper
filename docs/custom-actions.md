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
  const result = await wrapper();
  if (result && result.ephemeral === true) {
    return { ephemeral: true };
  }
  return "ok";
} catch (err) {
  return { quiperError: (err && err.message) ? err.message : String(err) };
}
```

If the script throws an error, the catch block intercepts it, prints it to the macOS logs, and triggers a system error beep to notify you.

A script can ask for an ephemeral tab by returning `{ ephemeral: true }`.
Quiper opens one with no beep, exactly as if you had pressed `Cmd+P`. The
runner forwards only that flag; every other return value collapses to `"ok"`.
Template guideline: return it when the website can't honor the request but an
anonymous tab can (for example logged-out soft temporary); keep throwing on
transient failures such as timeouts, where falling back risks duplicates.

---

## Temporary Tabs

Quiper distinguishes two temporary modes with separate owners.

* **Hard temporary (Quiper-level).** `Cmd+P` opens an isolated ephemeral
tab in the current engine. The tab is temporary by construction: it runs on a
separate non-persistent store that is never saved. Quiper owns this record;
pages never participate. Ephemeral tabs receive no injected scripts or message
handlers, so websites cannot detect Quiper through them. Ephemeral loads also
drop Quiper's referral query item while keeping every other parameter. They
never flip in
place: leaving one means opening a normal tab or closing it. Engine shortcuts
don't run inside them; the notice offers a normal tab instead. The topbar
title carries an ephemeral badge while one is active, the window outline turns
dashed, and the session
tooltip shows `(Temporary)`.
* **Soft temporary (website-level).** The `New Temporary Session` action
(`Cmd+Shift+N` by default) only runs provider automation, such as clicking the
site's own temporary-chat button. Whether the site is actually in its private
mode is the site's business; Quiper neither tracks nor reports it. If the
script throws, it beeps as any failed action does. When the site can't honor
the request but an anonymous tab can — for example you're logged out — the
script returns `{ ephemeral: true }` and Quiper opens an ephemeral tab with
no beep.

## Script Resolution

For each engine and action, the script that runs is the first non-empty value
in this order: a synced template default, your custom script, the action's
engine-independent global default (Share copies the page URL; New Temporary
Session opens an ephemeral tab when the engine has no automation), and finally
nothing — which logs "Action not implemented" and beeps. A script that throws
still beeps; the global default only fires when no script exists.

---

## Pre-Injected Library Helpers

To handle dynamic web layouts that load items asynchronously, Quiper injects a custom utility function called **`waitFor`** into the script execution environment.

### `waitFor` Function Signature
```javascript
function waitFor(check, timeoutMs = 1000)
```
*   **`check`:** A callback function returning `true` (when the condition is met) or `false`.
*   **`timeoutMs`:** The time (in milliseconds) before the promise rejects with a timeout error (default is 1000ms).
*   **Mechanism:** Uses `window.requestAnimationFrame` to loop efficiently without locking the browser thread.

### Example Usage of `waitFor`
```javascript
// Wait for the main menu side drawer to open before clicking an option
await waitFor(() => document.querySelector("mat-sidenav.mat-drawer-opened"));
document.querySelector('button[aria-label="Temporary chat"]').click();
```

---

## Configuration & Keyboard Shortcuts

1.  Open **Settings (`⌘ ⇧ ,`)** and navigate to the **Actions** tab.
2.  Define a new Action template (e.g. "New Chat" or "Toggle Private Session") and assign it a global keyboard shortcut (e.g., `⌘ N`).
3.  Go to the **Engines** tab, select an engine, and bind that Action template to a specific JavaScript snippet.
4.  When you press the shortcut, Quiper will evaluate the script bound to the active service engine.

---

## Auditing Default Templates

Default service templates and built-in action scripts change as provider web apps evolve. Use the local audit command before and after changing defaults:

```bash
node scripts/audit-default-templates.js
```

This reads `Quiper/Settings.swift`, lists every default service template, and validates the JavaScript syntax of each embedded default action. Add `--network` to perform anonymous header-only endpoint checks without using your Quiper WebKit profiles or browser cookies:

```bash
node scripts/audit-default-templates.js --network
```

Selector behavior still needs manual validation in a clean or test account when a provider only renders controls after login.

---

## External Script Editing

For large scripts or when using custom IDEs (like VS Code or Cursor), you can edit your scripts directly on your file system:
*   **Path:** `~/Library/Application Support/app.sassanh.quiper.Quiper/ActionScripts/[ServiceID]/[ActionID].js`
*   **Quick Access:** In the **Engines** tab, next to the script editor, click **Open Externally** (opens the `.js` file in your default code editor) or **Reveal in Finder**.
*   Quiper loads the script directly from this file path when triggered. Saved external edits also appear live in the Settings editor without restarting the app.
*   If Quiper and an external editor change the same revision simultaneously, Settings lets you choose **Load External** or **Keep Mine** instead of silently discarding either version.

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
