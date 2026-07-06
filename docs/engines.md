# Managing Engines

Quiper does not restrict you to a single AI ecosystem. You can manage and organize cloud services (like ChatGPT, Claude, and Gemini) alongside local AI instances (like Ollama or Open WebUI) in a single unified list.

---

## Service Configuration Settings

To add or configure an engine:
1.  Open **Settings (`⌘ ,`)** and navigate to the **Engines** tab.
2.  Select an existing engine to edit, or click **Add Engine** at the bottom of the list.
3.  Each engine exposes the following properties:
    *   **Name:** The label displayed in the switcher tab (e.g., "ChatGPT").
    *   **URL:** The target web address (e.g., `https://chatgpt.com`).
    *   **Focus Selector:** The CSS selector identifying the prompt input field.
    *   **Custom CSS:** Overrides to style the web elements (see the Custom CSS Injection section below).
    *   **Domain Routing Rules:** An ordered list of regex patterns that decide how outbound links from this engine are handled (see below).
    *   **Activation Shortcut:** A dedicated hotkey that summons the window and immediately opens this engine.

---

## Engine Icons

Every engine in your selector bar displays an icon. Quiper provides three ways to manage these icons under **Settings ➔ Engines ➔ [Select Engine]**:

### 1. Automatic Fetching
*   When you enter or change an engine's URL in settings, Quiper automatically attempts to fetch the website's favicon in the background using a built-in resolver.
*   You can manually trigger this by clicking the engine icon box, opening the drop-down menu, and selecting **Fetch Automatically**.

### 2. Custom Files
*   If you want to use a high-resolution icon or a customized graphic, click the icon box and select **Choose File...**.
*   Quiper supports standard image formats (`.png`, `.jpg`, `.jpeg`). Once selected, the image is automatically resized, encoded as a Base64 string, and saved directly into your settings file, ensuring it is portable.

### 3. Manual Reset/Removal
*   To remove a custom icon, open the icon box menu and select **Remove Icon**.
*   This removes the icon from the settings structure and reverts the engine to the default **Globe icon** (`globe` SF Symbol).

---

## Focus Selectors Explained

One of the key usability features in Quiper is **auto-focus**. When you summon the overlay or switch to an engine, Quiper automatically places your keyboard focus inside the text input box so you can start typing immediately without using your mouse.

To do this, Quiper evaluates a short script:
```javascript
document.querySelector("[your-focus-selector]")?.focus();
```

### Finding the Correct Focus Selector
If you add a custom web service and notice that your keyboard focus doesn't land in the input box, you need to find the element's CSS selector:
1.  Summon the engine inside Quiper.
2.  Press **`⌘ ⌥ I`** to open the **Web Inspector**.
3.  Click the **Inspect Element** pointer icon at the top-left of the inspector.
4.  Hover over the input area on the page and click it.
5.  In the inspector's HTML structure pane, right-click the highlighted input element (usually a `textarea` or a `div` with `contenteditable="true"`).
6.  Select **Copy ➔ SelectorPath** (or **Copy ➔ CSS Selector**).
7.  Paste this string into the **Focus Selector** field in settings.

### Default Selectors for Common Services

| Service | Focus Selector |
| :--- | :--- |
| **Gemini** | `rich-textarea .textarea, .textarea, div[contenteditable='true'], textarea` |
| **Claude** | `[data-testid='chat-input'] div[contenteditable='true'], div[contenteditable='true'], textarea` |
| **Grok** | `textarea[aria-label='Ask Grok anything'], textarea, div[contenteditable='true']` |
| **ChatGPT** | `#prompt-textarea, textarea, div[contenteditable='true']` |
| **X (Grok)** | `div[contenteditable='true'], textarea` |
| **Open WebUI** | `#chat-input[contenteditable='true'], textarea, div[contenteditable='true']` |
| **Z.ai** | `textarea, div[contenteditable='true'], [role='textbox']` |
| **DeepSeek** | `textarea, div[contenteditable='true'], [role='textbox']` |

---

## Custom CSS Injection

Since Quiper runs AI interfaces inside `WKWebView` wrappers, you can inject custom CSS styles directly into any engine's document head. This is most commonly used to hide sidebars, change scrollbars, and make backgrounds transparent so that your native macOS blur effects shine through.

### Setting Up Custom CSS
1.  Open **Settings (`⌘ ,`) ➔ Engines**.
2.  Select the engine you want to style.
3.  Scroll down to the **Custom CSS** text box.
4.  Paste your CSS rules and click **Save**.
5.  Press **`⌘ R`** to reload the active web view and see your styles applied live.

### Custom CSS Templates
Below are ready-to-use CSS configurations to make the backgrounds transparent for the default engines:

#### Gemini
```css
body, 
mat-sidenav-container, 
response-container>* {
  background-color: transparent !important;
}

input-container::before {
  background: transparent !important;
}
```

#### Claude
```css
body, 
.bg-bg-500, 
.bg-bg-400, 
.bg-bg-300 {
  background-color: transparent !important;
}
```

#### Grok
```css
body {
  background-color: transparent !important;
}

.chat-input-backdrop {
  background-image: none;
}
```

#### ChatGPT
```css
html, 
body {
  background-color: transparent !important;
}
```

#### X (Grok)
```css
body, 
div[data-testid="primaryColumn"] {
  background-color: transparent !important;
}
```

### Finding Classes for Overrides
If you want to write your own overrides (e.g. hiding a specific left-hand menu sidebar):
1.  Summon the active service in Quiper.
2.  Press **`⌘ ⌥ I`** to open the **Web Inspector**.
3.  Click the inspection cursor and highlight the sidebar you wish to hide.
4.  Identify its CSS class or element type (e.g., `<div class="sidebar-container-xyz">`).
5.  Add the rule to your Custom CSS text area:
    ```css
    .sidebar-container-xyz {
      display: none !important;
    }
    ```
6.  Reload the view (`⌘ R`).

---

## Integrating Local Engines

You can easily point Quiper to local web applications running LLM interfaces:

### Open WebUI (Local Docker Instance)
1.  Ensure your Docker container is running (`http://localhost:8080`).
2.  Create a new engine in settings.
3.  Set the URL to: `http://localhost:8080`.
4.  Set the Focus Selector to: `#chat-input[contenteditable='true']` (or `#chat-input`).

### Ollama / Llama.cpp Web Servers
*   If you run custom GUI interfaces for Ollama or Llama.cpp (like `llama.cpp/examples/server`), simply set the URL to your local port (e.g. `http://127.0.0.1:8080`) and input the target text input's CSS class or ID.

---

## Domain Routing Rules

Every engine has its own **Domain Routing** editor (**Settings ➔ Engines ➔ [Select Engine] ➔ Routing**) that decides what happens when a link inside that engine points somewhere other than the engine's own site — for example, an OAuth login redirect, a citation link, or an external documentation page.

### How a Link Is Routed

1.  **Same-Origin Priority:** Links to the engine's own domain (or its subdomains) always open inline, regardless of any rule — this guarantees normal in-app navigation is never intercepted.
2.  **Ordered Rule Matching:** For every other link, Quiper walks the **Routing Rules** list from top to bottom and applies the action of the **first rule whose regex pattern matches** the URL. Reorder rules with the chevrons next to each row to control priority.
3.  **Default Fallback:** If no rule matches, the link opens externally in your default system browser.

### Routing Actions

| Action | Behavior |
| :--- | :--- |
| **Internal** | Loads the URL inside the current Quiper tab. |
| **Popup** | Opens the URL in a native floating popup window. |
| **Prompt** | Shows a "Security & Routing" dialog asking you to choose Internal, Popup, or Safari for that link. |
| **Safari** | Opens the link externally in your default system browser. |

### Authentication Domains (OAuth Sign-In)

Many AI services use third-party OAuth providers for logins (e.g., signing in to Claude or ChatGPT using a Google or Apple account). By default, WebKit restricts cookies and scripts to the engine's main domain, so clicking "Sign in with Google" can otherwise get blocked or bounced externally.

*   **The Solution:** Add an **Internal** routing rule for the authentication domain so the login flow stays inside Quiper.
*   **Default Authenticator Expressions:**
    *   To allow Google Sign-In, add: `^https?://([^/]*\.)?accounts\.google\.com(/|$)` → **Internal**
    *   To allow Apple ID logins, add: `^https?://([^/]*\.)?appleid\.apple\.com(/|$)` → **Internal**

### Remembering Prompt Decisions

When a link triggers the **Security & Routing** prompt, you can check **"Remember my choice for this domain"** before choosing Internal, Popup, or Safari. Quiper then automatically inserts a new rule for that exact host at the top of the list so you won't be asked again. Press **Escape** or click **Cancel** to dismiss the prompt without navigating.

> **Migrating from older versions:** Settings from versions prior to the unified routing editor (which used separate "Friend Domains" and "Associated Domains" lists) are automatically converted into equivalent Routing Rules the first time Quiper loads them.

---

## Web Data Isolation & Management

To prevent data leaks and maintain complete privacy, Quiper runs every engine in a fully sandboxed `WebsiteDataStore` container. This isolates cookies, SQLite databases, IndexedDB logs, and cache assets between your profiles.

### Database Storage Paths
You can view the exact on-disk directory storing your engine's web profile by navigating to the **Web Data** sub-tab:

*   **Standard Storage (Unencrypted):** The data resides in a dedicated sandboxed folder under application support:
    `~/Library/Application Support/app.sassanh.quiper.Quiper/WebKit/WebsiteData/<Engine-UUID>`
*   **Secure Storage (Touch ID Encrypted):**
    When **Encrypt Local Storage** is toggled on (see [Touch ID & Security](security.md)), Quiper dynamically mounts an AES-256 APFS sparsebundle over the WebKit folder at launch:
    `/Volumes/quiper-secure-<Engine-UUID>`
### Show in Finder
Clicking **Show in Finder** opens the native macOS Finder directly at the location of the selected engine's database folder, allowing you to manually audit the local files or verify encryption states.

### Reset Web Data
*   Clicking **Reset Web Data...** prompts you to permanently purge all data associated with that specific engine.
*   **Purged Content:** Cookies, Local Storage, Cache, Service Workers, Session Storage, and WebSQL databases.
*   **Result:** Instantly logs you out of all sessions inside the engine and clears its cache footprint without affecting other engines.
