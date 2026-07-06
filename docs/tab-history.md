# Tab History Switcher

Quiper keeps a **Most-Recently-Used (MRU) ring** of your active tabs across engines, giving you lightning-fast keyboard access to whichever tabs you visited most recently — without losing your current focus.

---

## How It Works

Every time you switch to a new tab, Quiper pushes the previously active tab to the front of a history ring. The ring size is configurable (2–10 tabs) and persists across app launches.

Holding **`` ⌘ ` ``** cycles forward through the ring, previewing each past tab inside a floating HUD card grid. Releasing the key immediately commits the switch.

---

## Opening the Tab History HUD

| Action | Shortcut | Description |
| :--- | :--- | :--- |
| **Cycle Forward (MRU)** | `` ⌘ ` `` | Opens the HUD and moves the selection to the next most-recently-used tab. Hold to keep advancing. |
| **Cycle Backward** | `` ⌘ ⇧ ` `` | Moves the selection back toward the most-recently-used tab. Hold to keep rewinding. |
| **Cancel Without Switching** | `⌘ ⎋` | Dismisses the HUD and cancels the cycle session with no tab switch performed. |

> [!NOTE]
> The HUD only appears when you have **3 or more tabs** in your history ring (i.e., ring size ≥ 3, or you have visited at least 3 distinct tabs). With only 2 entries in the ring, Quiper toggles directly between the two tabs without showing any HUD.

---

## The HUD Interface

When the HUD appears it floats above the Quiper overlay window, centered over it. It is never cropped by the window edge — the HUD panel overflows the Quiper window bounds when needed and automatically clamps to stay fully within the current monitor's visible screen area.

### Card Layout

The HUD arranges tabs in a responsive grid:

- **3 items per row** when displaying up to 5 tabs in total.
- **4 items per row** when displaying 6–8 tabs.
- **5 items per row** when displaying 9–10 tabs.

The item width is fixed regardless of the row count, so the HUD grows wider to accommodate more columns rather than squeezing cards together.

### Card Contents

Each card shows:

- **Preview thumbnail** — a live screenshot of the tab captured the last time it was active.
- **Shortcut digit** — a bold number (1–10) displayed in the bottom-left corner of the card, matching the position within the history ring.
- **Page title** — displayed in two lines beside the digit, truncated to fit.

> [!TIP]
> If no preview screenshot is available for a tab (e.g., it was never fully visible on screen), the card renders with a transparent background so the HUD's glass blur shines through instead of showing a blank dark tile.

### Selection Highlight

The currently selected card is outlined with a solid 3pt accent border. Text elements within the selected card are tinted with the same accent color for maximum legibility.

---

## Committing and Cancelling

- **Commit:** Release the `⌘` modifier key at any time to immediately switch to the currently highlighted tab.
- **Cancel:** Press `⌘ ⎋` while the HUD is open. This dismisses the HUD and leaves the active tab unchanged.
- **Auto-stop at boundaries:** Holding `` ⌘ ` `` will stop auto-repeating when the selection reaches the oldest card. Holding `` ⌘ ⇧ ` `` will stop repeating when the selection wraps back to the most-recent card.

---

## HUD Repositioning

The HUD window tracks the Quiper overlay in real-time. If you drag or resize the Quiper window while the HUD is open, the HUD repositions itself immediately — centering over the new window position and adjusting if the new position would push part of the HUD off-screen.

---

## Mutual HUD Dismissal

Opening the Tab History HUD automatically closes any other Quiper HUD that may be open (Prompt History or Control Center), and vice versa — so you never end up with two overlapping overlays.

---

## Configuring the History Ring Size

You can control how many past tabs Quiper remembers in **Settings (`⌘ ,`) ➔ Behavior ➔ Tab History Ring Size**.

- **Range:** 2–10 tabs.
- **Default:** 2 (toggle mode — no HUD, direct switch between current and previous tab).
- **Persistence:** The ring is saved when Quiper exits and restored on next launch (subject to your Session Survival Policy setting).

> [!TIP]
> Setting the ring size to **2** is the leanest option — it gives you a single-shortcut "jump back to the previous tab" action with no HUD overhead. Increase the size to 3 or more whenever you find yourself needing to reach further back in your tab history.
