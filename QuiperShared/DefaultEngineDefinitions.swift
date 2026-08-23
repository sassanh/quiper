import Foundation

// Shared default engines, action IDs, and JS action-script helpers.
// Platform-neutral: both the macOS and iOS targets consume these definitions.

enum DefaultEngineDefinitions {
    static let newSessionActionID = UUID()
    static let newTemporarySessionActionID = UUID()
    static let shareActionID = UUID()
    static let historyActionID = UUID()
    static let openSettingsActionID = UUID()

    /// Names of bundled templates that run locally on the user's machine rather
    /// than as cloud services. Used to group the Add Engine menu into cloud and
    /// local templates, matching macOS.
    static let localTemplateNames: Set<String> = ["open webui", "llama.cpp", "omlx", "openclaw"]

    static let actionScriptHelpers = """
    function waitFor(check, timeoutMs = 1000) {
      return new Promise((resolve, reject) => {
        const start = Date.now();
        const step = () => {
          try {
            if (check()) { resolve(true); return; }
          } catch (err) {
            reject(err);
            return;
          }
          if (Date.now() - start >= timeoutMs) {
            reject(new Error(`waitFor timed out after ${timeoutMs}ms`));
            return;
          }
          window.requestAnimationFrame(step);
        };
        step();
      });
    }

    function quiperNormalize(value) {
      return (value || "").replace(/\\s+/g, " ").trim();
    }

    function quiperElements(selectors) {
      const found = [];
      for (const selector of selectors) {
        try {
          found.push(...document.querySelectorAll(selector));
        } catch {}
      }
      return [...new Set(found)];
    }

    function quiperIsVisible(element) {
      if (!element) { return false; }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) {
        return false;
      }
      const rects = element.getClientRects();
      return rects.length > 0 && [...rects].some((rect) => rect.width > 0 && rect.height > 0);
    }

    function quiperIsDisabled(element) {
      return !element ||
        element.disabled === true ||
        element.getAttribute("aria-disabled") === "true" ||
        element.closest("[aria-disabled='true']");
    }

    function quiperClickable(element) {
      return element?.closest("button,a,[role='button'],[role='menuitem'],[tabindex]") || element;
    }

    function quiperUsable(element) {
      const target = quiperClickable(element);
      return target && quiperIsVisible(target) && !quiperIsDisabled(target) ? target : null;
    }

    function quiperText(element) {
      return quiperNormalize([
        element?.getAttribute("aria-label"),
        element?.getAttribute("title"),
        element?.innerText,
        element?.textContent
      ].filter(Boolean).join(" "));
    }

    function quiperFind(selectors, options = {}) {
      const visible = options.visible !== false;
      for (const element of quiperElements(selectors)) {
        const target = quiperClickable(element);
        if (!target || quiperIsDisabled(target)) { continue; }
        if (visible && !quiperIsVisible(target)) { continue; }
        return target;
      }
      return null;
    }

    function quiperFindByText(labels, options = {}) {
      const visible = options.visible !== false;
      const normalizedLabels = labels.map( quiperNormalize ).filter(Boolean);
      const candidates = quiperElements([
        "button",
        "a",
        "[role='button']",
        "[role='menuitem']",
        "[tabindex]",
        "[aria-label]",
        "[title]",
        "span",
        "div"
      ]);

      for (const mode of ["exact", "contains"]) {
        for (const element of candidates) {
          const target = quiperClickable(element);
          if (!target || quiperIsDisabled(target)) { continue; }
          if (visible && !quiperIsVisible(target)) { continue; }
          const text = quiperText(element);
          if (!text) { continue; }
          const match = normalizedLabels.some((label) =>
            mode === "exact" ? text === label : text.includes(label)
          );
          if (match) { return target; }
        }
      }
      return null;
    }

    async function quiperClickElement(element, errorMessage = "Target not found") {
      const target = quiperUsable(element);
      if (!target) { throw new Error(errorMessage); }
      target.scrollIntoView({ block: "center", inline: "center" });
      target.click();
      await new Promise((resolve) => window.requestAnimationFrame(resolve));
      return target;
    }

    async function quiperClick(selectors, labels, errorMessage) {
      const target = quiperFind(selectors) || quiperFindByText(labels || []);
      return quiperClickElement(target, errorMessage);
    }

    async function quiperOpenDisclosure(disclosureSelectors, disclosureLabels, expectedSelectors, expectedLabels) {
      if (quiperFind(expectedSelectors || []) || quiperFindByText(expectedLabels || [])) {
        return;
      }
      const disclosure = quiperFind(disclosureSelectors || []) || quiperFindByText(disclosureLabels || []);
      if (!disclosure) { return; }
      await quiperClickElement(disclosure, "Disclosure button not found");
      await waitFor(() => quiperFind(expectedSelectors || []) || quiperFindByText(expectedLabels || []), 1200);
    }
    """

    static let definitions: [Service] = [
        Service(
            name: "Gemini",
            url: "https://gemini.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "rich-textarea .textarea, .textarea, div[contenteditable='true'], textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const newChatSelectors = [
                  "a[aria-label='New chat'].gem-nav-list-item",
                  ".gds-sidenav-list a[aria-label='New chat']",
                  "mat-nav-list a[aria-label='New chat']",
                  "a[aria-label='New chat']:not(.side-nav-sparkle-button)",
                  "button[aria-label='New chat']"
                ];
                const activeTemporarySelectors = [
                  ".temp-chat-on button[aria-label='Temporary chat']",
                  ".temp-chat-on [aria-label='Temporary chat']",
                  "button[aria-label='Turn off temporary chat']",
                  "[aria-label='Turn off temporary chat']",
                  "button[aria-label='Temporary chat'].temp-chat-on",
                  "button[aria-label='Temporary chat'][aria-pressed='true']",
                  "[aria-label='Temporary chat'][aria-checked='true']"
                ];

                function geminiTemporaryActive() {
                  return quiperFind(activeTemporarySelectors) || quiperFindByText(["Temporary Chat"]);
                }

                function geminiTemporaryToggle() {
                  return quiperFind([
                    ".temp-chat-on button[aria-label='Temporary chat']",
                    ".temp-chat-on [aria-label='Temporary chat']",
                    "button[aria-label='Turn off temporary chat']",
                    "[aria-label='Turn off temporary chat']",
                    "button[aria-label='Temporary chat']",
                    "[aria-label='Temporary chat']"
                  ]);
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  newChatSelectors,
                  ["New chat", "New Chat"]
                );

                if (geminiTemporaryActive()) {
                  const temporaryToggle = geminiTemporaryToggle();
                  if (temporaryToggle) {
                    await quiperClickElement(temporaryToggle, "Temporary chat button not found");
                    await waitFor(() => !geminiTemporaryActive(), 1200);
                  }
                }

                await quiperClick(
                  newChatSelectors,
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const temporarySelectors = [
                  "button[aria-label='Temporary chat']",
                  "[aria-label='Temporary chat']"
                ];
                const activeTemporarySelectors = [
                  ".temp-chat-on button[aria-label='Temporary chat']",
                  ".temp-chat-on [aria-label='Temporary chat']",
                  "button[aria-label='Turn off temporary chat']",
                  "[aria-label='Turn off temporary chat']",
                  "button[aria-label='Temporary chat'].temp-chat-on",
                  "button[aria-label='Temporary chat'][aria-pressed='true']",
                  "[aria-label='Temporary chat'][aria-checked='true']"
                ];
                const newChatSelectors = [
                  "a[aria-label='New chat'].gem-nav-list-item",
                  ".gds-sidenav-list a[aria-label='New chat']",
                  "mat-nav-list a[aria-label='New chat']",
                  "a[aria-label='New chat']:not(.side-nav-sparkle-button)",
                  "button[aria-label='New chat']"
                ];
                function geminiTemporaryActive() {
                  return quiperFind(activeTemporarySelectors) || quiperFindByText(["Temporary Chat"]);
                }

                if (!quiperFind(temporarySelectors) && (quiperFind(["button[aria-label='Sign in']"]) || quiperFindByText(["Sign in"]))) {
                  throw new Error("Sign in to Gemini before creating a temporary chat");
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  newChatSelectors,
                  ["New chat", "New Chat"]
                );

                await quiperClick(
                  newChatSelectors,
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                await waitFor(() => quiperFind(temporarySelectors) || quiperFindByText(["Temporary chat", "Temporary"]), 2500);

                const temporaryButton = quiperFind(temporarySelectors) || quiperFindByText(["Temporary chat", "Temporary"]);
                if (!temporaryButton) { throw new Error("Temporary chat button not found"); }
                if (!geminiTemporaryActive()) {
                  await quiperClickElement(temporaryButton, "Temporary chat button not found");
                  await waitFor(() => geminiTemporaryActive(), 1500);
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const shareDirect = quiperFind([
                  "button[aria-label='Share conversation']",
                  "[role='menuitem'][aria-label='Share conversation']",
                  "button[data-test-id='share-button']"
                ]) || quiperFindByText(["Share conversation"]);
                if (shareDirect) {
                  await quiperClickElement(shareDirect, "Share button not found");
                } else {
                  await quiperClick(
                    [
                      "button[aria-label='Open menu for conversation actions.']",
                      "button[aria-label='Open menu for conversation actions']"
                    ],
                    ["Open menu for conversation actions"],
                    "Conversation actions menu button not found"
                  );
                  await waitFor(() =>
                    quiperFind([
                      "button[aria-label='Share conversation']",
                      "[role='menuitem'][aria-label='Share conversation']",
                      "button[data-test-id='share-button']"
                    ]) || quiperFindByText(["Share conversation"])
                  );
                  await quiperClick(
                    [
                      "button[aria-label='Share conversation']",
                      "[role='menuitem'][aria-label='Share conversation']",
                      "button[data-test-id='share-button']"
                    ],
                    ["Share conversation"],
                    "Share button not found"
                  );
                }
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const closeSidebar = quiperFind(["button[aria-label='Close sidebar']", "button[aria-label='Close navigation menu']"]);
                if (closeSidebar) {
                  await quiperClickElement(closeSidebar, "Close sidebar button not found");
                  return;
                }
                await quiperClick(
                  ["button[aria-label='Open sidebar']", "button[aria-label='Main menu']", "button[aria-label='Open navigation menu']"],
                  ["Open sidebar", "Main menu", "Open navigation menu", "Menu"],
                  "Sidebar button not found"
                );
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function geminiSettingsVisible() {
                  return quiperElements([".mat-mdc-menu-panel"]).some((element) =>
                    quiperIsVisible(element)
                  );
                }

                const settingsButton = quiperFind(["button[aria-label='Settings']"]);
                await quiperClickElement(settingsButton, "Settings button not found");
                if (geminiSettingsVisible()) {
                  await waitFor(() => !geminiSettingsVisible(), 3000);
                } else {
                  await waitFor(geminiSettingsVisible, 3000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            html, body, chat-app-orchestrator, mat-sidenav-container, mat-sidenav-content,
            .blur-bg, .autosuggest-scrim, response-container>* {
              background-color: transparent !important;
            }
            input-container, input-container::before {
              background: transparent !important;
            }
            """
        ),
        Service(
            name: "Claude",
            url: "https://claude.ai?referrer=https://github.io/sassanh/quiper",
            focus_selector: "[data-testid='chat-input'] div[contenteditable='true'], div[contenteditable='true'], textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function claudeClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                const newChatSelectors = [
                  "a[aria-label='New chat']",
                  "button[aria-label='New chat']",
                  "a[href='/new']"
                ];
                const exitIncognito = quiperFind(["button[aria-label='Exit incognito']"]);
                if (exitIncognito) {
                  await claudeClick(exitIncognito, "Exit incognito button not found");
                }

                const newChat = quiperFind(newChatSelectors) || quiperFindByText(["New chat"]);
                if (newChat) {
                  await claudeClick(newChat, "New chat button not found");
                } else {
                  const target = new URL("/new", window.location.origin);
                  window.location.assign(target.href);
                }
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function claudeClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                const newChatSelectors = [
                  "a[aria-label='New chat']",
                  "button[aria-label='New chat']",
                  "a[href='/new']"
                ];
                const incognitoActive = () => location.search.includes("incognito") ||
                  Boolean(quiperFind(["button[aria-label='Exit incognito']"]));

                const newChat = quiperFind(newChatSelectors) || quiperFindByText(["New chat"]);
                if (newChat) {
                  await claudeClick(newChat, "New chat button not found");
                }

                if (!incognitoActive()) {
                  const incognitoButton = quiperFind(["button[aria-label='Use incognito']"]) ||
                    quiperFindByText(["Use incognito", "Incognito"]);
                  if (incognitoButton) {
                    await claudeClick(incognitoButton, "Use incognito button not found");
                  } else {
                    const target = new URL("/new", window.location.origin);
                    target.searchParams.set("incognito", "");
                    window.location.assign(target.href.replace("incognito=", "incognito"));
                  }
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function claudeShareDialogVisible() {
                  return quiperElements(["[role='dialog']"]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    return /share chat|create public link|create share link/i.test(quiperText(element));
                  });
                }

                const shareButton = quiperFind([
                  "button[data-testid='wiggle-controls-actions-share']",
                  "[data-testid='wiggle-controls-actions-share']",
                  "button[aria-label='Share']"
                ]) || Array.from(document.querySelectorAll("button")).find((button) => {
                  if (!quiperIsVisible(button) || quiperIsDisabled(button)) { return false; }
                  if (button.closest("[role='dialog'], [role='menu'], [data-testid*='action-bar']")) { return false; }
                  const rect = button.getBoundingClientRect();
                  return rect.top <= Math.max(120, window.innerHeight * 0.2) &&
                    rect.left >= window.innerWidth * 0.45 &&
                    quiperNormalize(button.innerText || button.textContent || button.getAttribute("aria-label")) === "Share";
                });

                await quiperClickElement(shareButton, "Share button not found");
                await waitFor(() => claudeShareDialogVisible(), 1500);
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  [
                    "button[data-testid='pin-sidebar-toggle']",
                    "button[aria-label='Open sidebar']",
                    "button[aria-label='Close sidebar']",
                    "[data-testid='sidebar-toggle']"
                  ],
                  ["Open sidebar", "Close sidebar", "Sidebar", "Menu"],
                  "Sidebar button not found"
                );
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function claudeSettingsVisible() {
                  return location.hash.includes("settings") || location.pathname.startsWith("/settings");
                }

                if (claudeSettingsVisible()) {
                  if (location.hash.includes("settings")) {
                    window.location.hash = "";
                  } else {
                    window.location.assign(new URL("/new", window.location.origin).href);
                  }
                } else {
                  const userMenu = quiperFind(["[data-testid='user-menu-button']"]);
                  await quiperClickElement(userMenu, "User menu button not found");
                  await waitFor(() => quiperFind(["[data-testid='user-menu-settings']"]), 2000);
                  const settingsItem = quiperFind(["[data-testid='user-menu-settings']"]);
                  await quiperClickElement(settingsItem, "Settings menu item not found");
                  await waitFor(claudeSettingsVisible, 4000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            body, .bg-bg-500, .bg-bg-400, .bg-bg-300 {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Grok",
            url: "https://grok.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[aria-label='Ask Grok anything'], textarea, div[contenteditable='true']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const privateActiveSelectors = [
                  "[aria-label='Switch to Default Chat']",
                  "button[aria-label='Switch to Default Chat']"
                ];
                const privateInactiveSelectors = [
                  "[aria-label='Switch to Private Chat']",
                  "button[aria-label='Switch to Private Chat']",
                  "button[aria-label='Private']"
                ];
                const newChat = quiperFind([
                  "[data-testid='new-chat']",
                  "a[href='/']:not([aria-label='Home page'])",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New Chat", "New chat"]);
                const privateActive = quiperFind(privateActiveSelectors);
                if (privateActive) {
                  await quiperClickElement(privateActive, "Private chat toggle not found");
                  await waitFor(() => quiperFind(privateInactiveSelectors), 1500);
                }
                if (newChat) {
                  await quiperClickElement(newChat, "New Chat button not found");
                } else {
                  window.location.assign("/");
                }
                await waitFor(() => !quiperFind(privateActiveSelectors), 1500);
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const privateActiveSelectors = [
                  "[aria-label='Switch to Default Chat']",
                  "button[aria-label='Switch to Default Chat']"
                ];
                const privateInactiveSelectors = [
                  "[aria-label='Switch to Private Chat']",
                  "button[aria-label='Switch to Private Chat']",
                  "button[aria-label='Private']"
                ];
                const newChat = quiperFind([
                  "[data-testid='new-chat']",
                  "a[href='/']:not([aria-label='Home page'])",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New Chat", "New chat"]);
                if (newChat) {
                  await quiperClickElement(newChat, "New Chat button not found");
                } else {
                  window.history.pushState(null, "", "/");
                }

                await waitFor(() => quiperFind(privateActiveSelectors) || quiperFind(privateInactiveSelectors), 2000);
                if (!quiperFind(privateActiveSelectors)) {
                  await quiperClick(
                    privateInactiveSelectors,
                    ["Private", "Private Chat", "Switch to Private Chat"],
                    "Private chat button not found"
                  );
                  await waitFor(() => quiperFind(privateActiveSelectors), 1500);
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Create share link']", "button[aria-label='Share']", "[aria-label='Share']"],
                  ["Create share link", "Share"],
                  "Share button not found"
                );
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                if (window.innerWidth >= 700) {
                  const historySelectors = ["button[aria-label='History']", "[aria-label='History']"];
                  const historyVisible = () => quiperFind(historySelectors) || quiperFindByText(["History"]);
                  const sidebarToggle = quiperFindByText(["Toggle Sidebar"]) ||
                    quiperFind(["button[aria-label='Toggle sidebar']", "[aria-label='Toggle sidebar']"]);
                  if (!sidebarToggle) { throw new Error("Sidebar toggle button not found"); }

                  if (historyVisible()) {
                    await quiperClickElement(sidebarToggle, "Sidebar toggle button not found");
                    return;
                  }

                  await quiperClickElement(sidebarToggle, "Sidebar toggle button not found");
                  await waitFor(() => historyVisible(), 1500);

                  const historyHeader = quiperFind(historySelectors) || quiperFindByText(["History"]);
                  const expanded = historyHeader?.getAttribute("aria-expanded") === "true" ||
                    historyHeader?.getAttribute("data-state") === "open" ||
                    historyHeader?.closest("[data-state='open'], [aria-expanded='true']");
                  if (historyHeader && !expanded) {
                    await quiperClickElement(historyHeader, "History button not found");
                  }
                  return;
                }

                await quiperOpenDisclosure(
                  ["button[aria-label='Toggle sidebar']", "[aria-label='Toggle sidebar']"],
                  ["Toggle sidebar", "Menu"],
                  ["div[role='button'][aria-label='History']", "[aria-label='History']"],
                  ["History"]
                );
                await quiperClick(
                  ["div[role='button'][aria-label='History']", "[aria-label='History']"],
                  ["History"],
                  "History button not found"
                );
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function grokPointerClick(element) {
                  if (!element) { throw new Error("Grok click target not found"); }
                  const rect = element.getBoundingClientRect();
                  const options = {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: rect.left + rect.width / 2,
                    clientY: rect.top + rect.height / 2,
                    button: 0
                  };
                  for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "click"]) {
                    element.dispatchEvent(new MouseEvent(type, options));
                  }
                  await new Promise((resolve) => window.requestAnimationFrame(resolve));
                }

                function grokSettingsVisible() {
                  return quiperElements(["[role='dialog']"]).some((element) =>
                    quiperIsVisible(element) && /General|Appearance/.test(quiperText(element))
                  );
                }

                function grokSettingsDialog() {
                  return quiperElements(["[role='dialog']"]).find((element) =>
                    quiperIsVisible(element) && /General|Appearance/.test(quiperText(element))
                  );
                }

                if (grokSettingsVisible()) {
                  const dialog = grokSettingsDialog();
                  const closeButton = dialog && Array.from(dialog.querySelectorAll("button"))
                    .find((button) => button.getAttribute("title") === "Close");
                  await grokPointerClick(closeButton);
                  await waitFor(() => !grokSettingsVisible(), 3000);
                } else {
                  const profileButton = quiperClickable(quiperFind(["img[src*='profile-picture']"]));
                  await grokPointerClick(profileButton);
                  await waitFor(() => quiperFind(["[role='menu']"]), 2000);
                  const menu = quiperFind(["[role='menu']"]);
                  const settingsItem = menu && Array.from(menu.querySelectorAll("div"))
                    .find((element) => quiperNormalize(element.innerText) === "Settings");
                  if (!settingsItem) { throw new Error("Settings menu item not found"); }
                  await grokPointerClick(settingsItem);
                  await waitFor(grokSettingsVisible, 4000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?x\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            body {
              background-color: transparent !important;
            }
            .chat-input-backdrop {
              background-color: transparent;
              background-image: none;
            }
            """
        ),
        Service(
            name: "ChatGPT",
            url: "https://chatgpt.com?referrer=https://github.io/sassanh/quiper",
            // Prefer the stable prompt id; keep ProseMirror/role fallbacks for older markup.
            focus_selector: "#prompt-textarea, .ProseMirror[role='textbox'], textarea[name='prompt'], div[contenteditable='true'][role='textbox']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function chatGPTButtonByText(label) {
                  return Array.from(document.querySelectorAll("button")).find((button) =>
                    quiperIsVisible(button) &&
                    !quiperIsDisabled(button) &&
                    quiperNormalize(button.innerText || button.textContent) === label
                  );
                }

                await quiperOpenDisclosure(
                  ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                  ["Open sidebar", "Menu"],
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']"],
                  ["New chat", "New Chat"]
                );
                await quiperClick(
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']", "button[aria-label='New chat']"],
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                const clearChat = chatGPTButtonByText("Clear chat");
                if (clearChat) {
                  await quiperClickElement(clearChat, "Clear chat button not found");
                  await waitFor(() => !chatGPTButtonByText("Clear chat"), 2000);
                }
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function chatGPTButtonByText(label) {
                  return Array.from(document.querySelectorAll("button")).find((button) =>
                    quiperIsVisible(button) &&
                    !quiperIsDisabled(button) &&
                    quiperNormalize(button.innerText || button.textContent) === label
                  );
                }

                const temporarySelectors = [
                  "[aria-label='Turn on temporary chat']",
                  "[data-testid='temporary-chat-button']"
                ];
                const activeTemporarySelectors = [
                  "[aria-label='Turn off temporary chat']",
                  "[data-testid='temporary-chat-button'][aria-pressed='true']"
                ];
                if (!quiperFind(temporarySelectors) && (quiperFind(["[data-testid='login-button']"]) || quiperFindByText(["Log in"]))) {
                  throw new Error("Sign in to ChatGPT before creating a temporary chat");
                }

                if (quiperFind(activeTemporarySelectors)) {
                  const clearChat = chatGPTButtonByText("Clear chat");
                  if (clearChat) {
                    await quiperClickElement(clearChat, "Clear chat button not found");
                    await waitFor(() => !chatGPTButtonByText("Clear chat"), 2000);
                  }
                  return;
                }

                await quiperOpenDisclosure(
                  ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                  ["Open sidebar", "Menu"],
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']"],
                  ["New chat", "New Chat"]
                );
                await quiperClick(
                  ["[data-testid='create-new-chat-button']", "a[href='/']", "a[aria-label='New chat']", "button[aria-label='New chat']"],
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );

                await waitFor(() =>
                  quiperFind(temporarySelectors) ||
                  quiperFindByText(["Temporary chat"])
                );
                await quiperClick(
                  temporarySelectors,
                  ["Temporary chat", "Turn on temporary chat"],
                  "Temporary chat button not found"
                );
                await waitFor(() => quiperFind(activeTemporarySelectors), 1500);
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function chatGPTShareButton() {
                  const candidates = quiperElements([
                    "button[data-testid='share-chat-button']",
                    "button[aria-label='Share'][data-testid='share-chat-button']",
                    "header button[aria-label='Share']",
                    "button[aria-label='Share'][aria-haspopup]",
                    "button[aria-label='Share']"
                  ]).map( quiperClickable ).filter((button) => {
                    if (!button || !quiperIsVisible(button) || quiperIsDisabled(button)) { return false; }
                    if (button.closest("[role='dialog'], [role='menu'], [data-radix-popper-content-wrapper]")) { return false; }
                    const rect = button.getBoundingClientRect();
                    return rect.top <= Math.max(160, window.innerHeight * 0.25) &&
                      rect.left >= window.innerWidth * 0.35;
                  });

                  return candidates
                    .sort((left, right) => {
                      const a = left.getBoundingClientRect();
                      const b = right.getBoundingClientRect();
                      return (a.top - b.top) || (b.right - a.right);
                    })[0] || null;
                }

                function chatGPTShareWidgetVisible() {
                  return quiperElements([
                    "[role='dialog']",
                    "[role='menu']",
                    "[data-radix-popper-content-wrapper]",
                    "[data-testid='share-modal']",
                    "[data-testid='share-dialog']"
                  ]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    const text = quiperText(element);
                    return /share|copy link|create link/i.test(text);
                  });
                }

                await quiperClickElement(chatGPTShareButton(), "Share button not found");
                await waitFor(() => chatGPTShareWidgetVisible(), 1500);
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function chatGPTInViewport(element) {
                  if (!element || !quiperIsVisible(element)) { return false; }
                  const rect = element.getBoundingClientRect();
                  return rect.width > 0 &&
                    rect.height > 0 &&
                    rect.bottom > 0 &&
                    rect.top < window.innerHeight &&
                    rect.right > 0 &&
                    rect.left < window.innerWidth;
                }

                function chatGPTSearchInput() {
                  return quiperElements([
                    "input[placeholder*='Search chats']",
                    "input[aria-label*='Search chats']",
                    "input[type='search']",
                    "input[placeholder*='Search']"
                  ]).find((input) => {
                    if (!chatGPTInViewport(input)) { return false; }
                    const label = [
                      input.getAttribute("placeholder"),
                      input.getAttribute("aria-label"),
                      input.getAttribute("type")
                    ].filter(Boolean).join(" ");
                    return /search chats|search chat history|search/i.test(label);
                  }) || null;
                }

                function chatGPTSearchPanel() {
                  const input = chatGPTSearchInput();
                  if (!input) { return null; }
                  return input.closest("[role='dialog'], [data-radix-popper-content-wrapper]") ||
                    input.closest("form") ||
                    input.parentElement;
                }

                function chatGPTSearchLoginWallOpen() {
                  // Logged-out search opens a "Search your chat history" panel instead of an input.
                  // ChatGPT sometimes mounts this dialog off-screen in constrained windows, so do not
                  // require in-viewport geometry — data-state/open + copy is the reliable signal.
                  return quiperElements([
                    "[role='dialog']",
                    "[data-radix-popper-content-wrapper]",
                    "[class*='popover']",
                    "[class*='modal']"
                  ]).some((panel) => {
                    const state = panel.getAttribute("data-state");
                    if (state && state !== "open") { return false; }
                    if (!quiperIsVisible(panel) && state !== "open") { return false; }
                    return /search your chat history|log in to save conversations/i.test(quiperText(panel));
                  });
                }

                function chatGPTIsLoggedOut() {
                  return !!(
                    quiperFind(["[data-testid='login-button']", "[data-testid='unsupported-nav-login']"]) ||
                    quiperFindByText(["Log in"])
                  );
                }

                async function chatGPTSleep(ms) {
                  await new Promise((resolve) => setTimeout(resolve, ms));
                }

                async function chatGPTDismissOverlay() {
                  document.dispatchEvent(new KeyboardEvent("keydown", {
                    key: "Escape",
                    code: "Escape",
                    keyCode: 27,
                    which: 27,
                    bubbles: true
                  }));
                  await chatGPTSleep(350);
                }

                async function chatGPTOpenSearch() {
                  await quiperOpenDisclosure(
                    ["button[data-testid='open-sidebar-button']", "button[aria-label='Open sidebar']"],
                    ["Open sidebar", "Menu"],
                    ["button[aria-label='Search chats']", "[data-testid='sidebar-search-button']"],
                    ["Search chats"]
                  );
                  await quiperClick(
                    ["button[aria-label='Search chats']", "[data-testid='sidebar-search-button']"],
                    ["Search chats"],
                    "Search chats button not found"
                  );
                  await chatGPTSleep(450);
                }

                const searchInput = chatGPTSearchInput();
                if (searchInput) {
                  const inputRect = searchInput.getBoundingClientRect();
                  const searchPanel = chatGPTSearchPanel();
                  const panelButtons = searchPanel ? Array.from(searchPanel.querySelectorAll("button")) : [];
                  const closeButton = panelButtons.find((button) => {
                    const text = quiperText(button);
                    return chatGPTInViewport(button) && !quiperIsDisabled(button) &&
                      /^(close|cancel)$/i.test(text);
                  }) || Array.from(document.querySelectorAll("button")).find((button) => {
                    if (!chatGPTInViewport(button) || quiperIsDisabled(button)) { return false; }
                    const rect = button.getBoundingClientRect();
                    const verticallyAligned = rect.top < inputRect.bottom + 24 && rect.bottom > inputRect.top - 24;
                    const rightOfInput = rect.left > inputRect.right - 120;
                    return verticallyAligned && rightOfInput;
                  });
                  if (closeButton) {
                    await quiperClickElement(closeButton, "Close search button not found");
                  } else {
                    await chatGPTDismissOverlay();
                  }
                  await chatGPTSleep(200);
                  return;
                }

                // Logged-out ChatGPT search is a login wall panel (no search input). Toggle that panel.
                if (chatGPTIsLoggedOut()) {
                  if (chatGPTSearchLoginWallOpen()) {
                    await chatGPTDismissOverlay();
                    return;
                  }
                  await chatGPTOpenSearch();
                  return;
                }

                await chatGPTOpenSearch();
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function chatGPTSettingsVisible() {
                  if (location.hash.startsWith("#settings")) { return true; }
                  return quiperElements([
                    "[data-testid='settings-modal']",
                    "[data-testid='settings']",
                    "[role='dialog']",
                    "[data-radix-popper-content-wrapper]"
                  ]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    return /settings/i.test(quiperText(element));
                  });
                }

                if (chatGPTSettingsVisible()) {
                  const closeButton = quiperFind(["[aria-label='Close']"], { visible: true });
                  if (closeButton) {
                    const target = quiperUsable(closeButton);
                    if (!target) { throw new Error("Close settings button not found"); }
                    target.click();
                  } else {
                    window.location.assign(new URL(window.location.pathname, window.location.origin).href);
                  }
                } else {
                  window.location.assign(new URL("#settings", window.location.origin).href);
                  await waitFor(chatGPTSettingsVisible, 4000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            html, body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "X",
            url: "https://x.com/i/grok?referrer=https://github.io/sassanh/quiper",
            focus_selector: "div[contenteditable='true'], textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function xClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                function xPrivateActive() {
                  return /This chat won.t appear in your history/i.test(document.body.innerText || "") ||
                    Boolean(quiperFind([
                      "button[aria-label='Disable private']",
                      "button[aria-label='Turn off private']",
                      "button[aria-pressed='true'][aria-label*='Private']",
                      "[aria-selected='true'][aria-label*='Private']"
                    ]));
                }

                const privateButton = quiperFind(["button[aria-label='Private']", "[aria-label='Private']"]) ||
                  quiperFindByText(["Private"]);
                if (xPrivateActive() && privateButton) {
                  await xClick(privateButton, "Private button not found");
                }

                const grokHome = quiperFind(["a[href='/i/grok']", "a[aria-label='Grok']"]) ||
                  quiperFindByText(["Grok"]);
                if (grokHome) {
                  await xClick(grokHome, "Grok navigation button not found");
                } else {
                  window.history.pushState(null, "", "/i/grok");
                  window.dispatchEvent(new PopStateEvent("popstate"));
                }
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function xClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                function xPrivateActive() {
                  return /This chat won.t appear in your history/i.test(document.body.innerText || "") ||
                    Boolean(quiperFind([
                      "button[aria-label='Disable private']",
                      "button[aria-label='Turn off private']",
                      "button[aria-pressed='true'][aria-label*='Private']",
                      "[aria-selected='true'][aria-label*='Private']"
                    ]));
                }

                const grokHome = quiperFind(["a[href='/i/grok']", "a[aria-label='Grok']"]) ||
                  quiperFindByText(["Grok"]);
                if (grokHome) {
                  await xClick(grokHome, "Grok navigation button not found");
                } else {
                  window.history.pushState(null, "", "/i/grok");
                  window.dispatchEvent(new PopStateEvent("popstate"));
                }

                if (!xPrivateActive()) {
                  const privateButton = quiperFind(["button[aria-label='Private']", "[aria-label='Private']"]) ||
                    quiperFindByText(["Private"]);
                  await xClick(privateButton, "Private button not found");
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Share']", "[aria-label='Share']"],
                  ["Share"],
                  "Share button not found"
                );
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function xVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function xText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function xTopHistoryButton() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return /chat history|history/i.test(xText(element)) &&
                        rect.y < 140 &&
                        rect.width >= 20 &&
                        rect.height >= 20;
                    });
                }

                function xHistoryPanelOpen() {
                  const tablist = [...document.querySelectorAll("[role='tablist']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      const value = xText(element);
                      return /chats/i.test(value) &&
                        /bookmarks|images/i.test(value) &&
                        rect.width > 180 &&
                        rect.height > 30;
                    });
                  const searchInput = [...document.querySelectorAll("input,textarea,[contenteditable='true']")]
                    .filter(xVisible)
                    .find((element) => /search/i.test(xText(element) || element.getAttribute("placeholder") || ""));
                  return Boolean(tablist || searchInput || xHistoryCloseButton());
                }

                function xHistoryCloseButton() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(xVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return /^(close|close history)$/i.test(xText(element)) &&
                        rect.x > 70 &&
                        rect.y < 80 &&
                        rect.width >= 20 &&
                        rect.height >= 20;
                    });
                }

                async function xPressEscape() {
                  const eventInit = {
                    key: "Escape",
                    code: "Escape",
                    keyCode: 27,
                    which: 27,
                    bubbles: true,
                    cancelable: true
                  };
                  (document.activeElement || document.body).dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  document.dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  window.dispatchEvent(new KeyboardEvent("keydown", eventInit));
                  await new Promise((resolve) => setTimeout(resolve, 250));
                }

                const historyButton = xTopHistoryButton();
                if (!historyButton) {
                  throw new Error("Chat history button not found");
                }

                if (xHistoryPanelOpen()) {
                  const closeButton = xHistoryCloseButton();
                  await quiperClickElement(closeButton || historyButton, "History close button not found");
                  try {
                    await waitFor(() => !xHistoryPanelOpen(), 1600);
                  } catch {
                    await xPressEscape();
                    await waitFor(() => !xHistoryPanelOpen(), 1600);
                  }
                } else {
                  await quiperClickElement(historyButton, "Chat history button not found");
                  await waitFor(() => xHistoryPanelOpen(), 1600);
                }
                """,
                 DefaultEngineDefinitions.openSettingsActionID: """
                 \(DefaultEngineDefinitions.actionScriptHelpers)
                 async function xWaitFor(check, timeoutMs = 3000) {
                   const start = Date.now();
                   return new Promise((resolve, reject) => {
                     const step = () => {
                       try {
                         if (check()) { resolve(true); return; }
                       } catch (err) {
                         reject(err);
                         return;
                       }
                       if (Date.now() - start >= timeoutMs) {
                         reject(new Error(`xWaitFor timed out after ${timeoutMs}ms`));
                         return;
                       }
                       setTimeout(step, 50);
                     };
                     setTimeout(step, 0);
                   });
                 }

                 async function xClick(element, errorMessage) {
                   const target = quiperUsable(element);
                   if (!target) { throw new Error(errorMessage); }
                   target.scrollIntoView({ block: "center", inline: "center" });
                   target.click();
                   await new Promise((resolve) => setTimeout(resolve, 350));
                   return target;
                 }

                 function xSettingsVisible() {
                   return location.pathname.startsWith("/settings");
                 }

                 function xSettingsOrigin() {
                   return sessionStorage.getItem("quiper.x.settings.origin") || "/i/grok";
                 }

                 if (xSettingsVisible()) {
                   sessionStorage.removeItem("quiper.x.settings.origin");
                   const originPath = new URL(xSettingsOrigin(), location.href).pathname;
                   const originLink = quiperFind([
                     `a[href='${originPath}']`,
                     "a[aria-label='Grok']",
                     "a[href='/i/grok']"
                   ]);
                   await xClick(originLink, "Settings return link not found");
                   await xWaitFor(() => !xSettingsVisible(), 3000);
                 } else {
                   sessionStorage.setItem("quiper.x.settings.origin", location.href);
                   const direct = quiperFind([
                     "a[href='/settings']",
                     "[data-testid='settings']",
                     "[aria-label='Settings and privacy']"
                   ]);
                   if (direct) {
                     await xClick(direct, "Settings link not found");
                   } else {
                     const moreButton = quiperFind([
                       "button[aria-label='More menu items']",
                       "[data-testid='AppTabBar_More_Menu']",
                       "[data-testid='SideNav_More']"
                     ]) || quiperFindByText(["More menu items", "More"]);
                     await xClick(moreButton, "More menu button not found");
                     await xWaitFor(
                       () => quiperFind(["a[data-testid='settings']", "[data-testid='settings']"]) || quiperFindByText(["Settings and privacy"]),
                       2000
                     );
                     const settingsItem = quiperFind(["a[data-testid='settings']", "[data-testid='settings']"]) ||
                       quiperFindByText(["Settings and privacy"]);
                     await xClick(settingsItem, "Settings menu item not found");
                   }
                   await xWaitFor(xSettingsVisible, 3500);
                 }
                 """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            body, div[data-testid="primaryColumn"] {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Open WebUI",
            url: "http://localhost:8080",
            focus_selector: "#chat-input[contenteditable='true'], textarea, div[contenteditable='true']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  ["a[href='/']", "button[aria-label='New Chat']", "[aria-label='New Chat']"],
                  ["New Chat", "New chat"],
                  "New chat button not found"
                );
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function openWebUIVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function openWebUIText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function openWebUITemporaryActive() {
                  return new URL(location.href).searchParams.get("temporary-chat") === "true";
                }

                function openWebUITemporaryButton() {
                  const labelled = quiperFind([
                    "#temporary-chat-button",
                    "button[aria-label='Temporary Chat']",
                    "[aria-label='Temporary Chat']"
                  ]) || quiperFindByText(["Temporary Chat", "Temporary"]);
                  if (labelled) { return labelled; }

                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(openWebUIVisible)
                    .map((element) => ({ element, rect: element.getBoundingClientRect(), text: openWebUIText(element) }))
                    .filter(({ rect, text }) =>
                      rect.y < 64 &&
                      rect.x > window.innerWidth - 180 &&
                      rect.width >= 28 &&
                      rect.width <= 44 &&
                      rect.height >= 28 &&
                      rect.height <= 44 &&
                      !/Controls|Voice|Model|Add|Share|Menu/i.test(text)
                    )
                    .sort((a, b) => a.rect.x - b.rect.x)[0]?.element;
                }

                const newChat = quiperFind(["a[href='/']", "button[aria-label='New Chat']", "[aria-label='New Chat']"]) ||
                  quiperFindByText(["New Chat", "New chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                await new Promise((resolve) => setTimeout(resolve, 350));

                if (!openWebUITemporaryActive()) {
                  await quiperClickElement(openWebUITemporaryButton(), "Temporary button not found");
                  await waitFor(() => openWebUITemporaryActive(), 1800);
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const copyButtons = quiperElements(["[aria-label='Copy']", "button[aria-label='Copy']"]).filter( quiperIsVisible );
                const target = quiperClickable(copyButtons.at(-1));
                await quiperClickElement(target, "Copy/share button not found");
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function openWebUIVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function openWebUIText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                const labelledToggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(openWebUIVisible)
                  .find((element) => /^(Open|Close|Toggle) Sidebar$/i.test(openWebUIText(element)));

                const chromeToggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(openWebUIVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) =>
                    rect.y < 64 &&
                    rect.x < 280 &&
                    rect.width >= 28 &&
                    rect.width <= 44 &&
                    rect.height >= 28 &&
                    rect.height <= 44
                  )
                  .sort((a, b) => b.rect.x - a.rect.x)[0]?.element;

                await quiperClickElement(labelledToggle || chromeToggle, "Sidebar/history button not found");
                await new Promise((resolve) => setTimeout(resolve, 250));
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function openWebUISettingsVisible() {
                  return quiperElements([
                    "[role='dialog']"
                  ]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    return /settings/i.test(quiperText(element));
                  });
                }

                if (openWebUISettingsVisible()) {
                  const closeButton = quiperFind([
                    "[aria-label='Close settings modal']",
                    "[aria-label='Close']"
                  ]);
                  if (closeButton) {
                    await quiperClickElement(closeButton, "Close settings button not found");
                  }
                } else {
                  const userMenu = quiperFind([
                    "img[aria-label='Open User Profile Menu']",
                    "[aria-label='Open User Profile Menu']"
                  ]);
                  await quiperClickElement(userMenu, "User menu button not found");
                  await waitFor(
                    () => quiperFindByText(["Settings"]),
                    2000
                  );
                  const settingsItem = quiperFindByText(["Settings"]);
                  await quiperClickElement(settingsItem, "Settings menu item not found");
                  await waitFor(openWebUISettingsVisible, 3000);
                }
                """,
            ],
            customCSS: """
            body, div.app>div, div.bg-white:has(form #chat-input-container) {
              background-color: transparent !important;
            }
            """,
        ),
        Service(
            name: "Z.ai",
            url: "https://chat.z.ai?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea, div[contenteditable='true'], [role='textbox']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function zaiVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function zaiText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function zaiButtonByText(pattern) {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .find((element) => pattern.test(zaiText(element)));
                }

                function zaiSidebarExpanded() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 280 && rect.width > 120 && /New Chat|Chat/i.test(zaiText(element));
                    });
                }

                async function zaiClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.scrollIntoView({ block: "center", inline: "center" });
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 350));
                  return target;
                }

                async function zaiEnsureSidebarOpen() {
                  if (zaiSidebarExpanded()) { return; }
                  const toggle = [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .find((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 80 && rect.y < 60 && rect.width >= 20 && rect.height >= 20;
                    });
                  await zaiClick(toggle, "Sidebar toggle button not found");
                  await waitFor(() => zaiSidebarExpanded(), 1800);
                }

                await zaiEnsureSidebarOpen();
                const chatButton = zaiButtonByText(/^Chat\\s*Chat$|^Chat$/i);
                if (chatButton) {
                  await zaiClick(chatButton, "Chat button not found");
                }
                const newChat = zaiButtonByText(/New Chat/i);
                await zaiClick(newChat, "New Chat button not found");
                await waitFor(() => quiperFind(["textarea", "[role='textbox']", "div[contenteditable='true']"]), 1800);
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  ["button[aria-label='Share']", "[aria-label='Share']", "[data-testid*='share']"],
                  ["Share"],
                  "Share button not found"
                );
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function zaiVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function zaiText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                function zaiSidebarExpanded() {
                  return [...document.querySelectorAll("button,[role='button']")]
                    .filter(zaiVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.x < 280 && rect.width > 120 && /New Chat|Chat/i.test(zaiText(element));
                    });
                }

                const wasExpanded = zaiSidebarExpanded();
                const toggle = [...document.querySelectorAll("button,[role='button']")]
                  .filter(zaiVisible)
                  .find((element) => {
                    const rect = element.getBoundingClientRect();
                    return rect.y < 60 &&
                      rect.width >= 20 &&
                      rect.height >= 20 &&
                      (wasExpanded ? rect.x > 180 && rect.x < 280 : rect.x < 80);
                  });
                await quiperClickElement(toggle, "Sidebar toggle button not found");
                await waitFor(() => zaiSidebarExpanded() !== wasExpanded, 1800);
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const ZAI_ORIGIN_KEY = "quiper.zai.settingsOrigin";

                function zaiSettingsVisible() {
                  return location.pathname.startsWith("/settings");
                }

                function zaiSaveOrigin(url) {
                  try { sessionStorage.setItem(ZAI_ORIGIN_KEY, url); } catch {}
                }

                function zaiGetOrigin() {
                  try { return sessionStorage.getItem(ZAI_ORIGIN_KEY); } catch { return null; }
                }

                function zaiClearOrigin() {
                  try { sessionStorage.removeItem(ZAI_ORIGIN_KEY); } catch {}
                }

                async function zaiSoftNavigate(url) {
                  try {
                    const target = new URL(url, window.location.origin);
                    if (target.origin !== window.location.origin) { return; }
                    history.pushState(null, "", target.href);
                    window.dispatchEvent(new PopStateEvent("popstate"));
                  } catch {}
                }

                if (zaiSettingsVisible()) {
                  const origin = zaiGetOrigin();
                  if (origin) {
                    await zaiSoftNavigate(origin);
                  }
                  zaiClearOrigin();
                } else {
                  zaiSaveOrigin(location.href);
                  const userMenu = quiperFind(["button[aria-label='Open User Menu']"]);
                  await quiperClickElement(userMenu, "User menu button not found");
                  await waitFor(
                    () => quiperFind(["[role='menuitem']"]) || quiperFindByText(["Settings"]),
                    1500
                  );
                  const settingsItem = quiperFind(["[role='menuitem']"]) || quiperFindByText(["Settings"]);
                  await quiperClickElement(settingsItem, "Settings menu item not found");
                  await waitFor(zaiSettingsVisible, 4000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            body, #app, .app>div, text-3d-flip-char>.backface-hidden  {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Kimi",
            url: "https://www.kimi.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "[contenteditable='true'][role='textbox'], textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  [
                    "a.new-chat-btn",
                    "a[aria-label='New Chat']",
                    "[aria-label='New Chat']"
                  ],
                  ["New chat", "New Chat"],
                  "New chat button not found"
                );
                await waitFor(() => quiperFind([
                  "[contenteditable='true'][role='textbox']",
                  "textarea"
                ]), 1500);
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  [
                    "button[aria-label='Share']",
                    "[role='button'][aria-label='Share']",
                    "button[title='Share']",
                    "[data-testid*='share']"
                  ],
                  ["Share"],
                  "Share button not found"
                );
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function kimiInViewport(element) {
                  if (!quiperIsVisible(element)) { return false; }
                  const rect = element.getBoundingClientRect();
                  return rect.right > 0 &&
                    rect.left < window.innerWidth &&
                    rect.bottom > 0 &&
                    rect.top < window.innerHeight;
                }

                function kimiSidebarExpanded() {
                  const sidebar = document.querySelector(".next-sidebar");
                  if (!sidebar) { return false; }
                  const rect = sidebar.getBoundingClientRect();
                  return kimiInViewport(sidebar) && rect.right > Math.min(100, rect.width / 2);
                }

                const wasExpanded = kimiSidebarExpanded();
                const collapse = quiperFind([
                  "button.expand-btn[aria-label='Hide Sidebar']",
                  "button[aria-label='Hide Sidebar']"
                ]);
                const expand = quiperFind([
                  ".sidebar-main-trigger__button[aria-label='Expand Sidebar']",
                  "[aria-label='Expand Sidebar']"
                ]);
                const target = wasExpanded ? collapse : expand;
                if (!target || !kimiInViewport(target)) {
                  throw new Error("Sidebar/history button not found");
                }
                target.click();
                await waitFor(() => kimiSidebarExpanded() !== wasExpanded, 1500);
                """,
                 DefaultEngineDefinitions.openSettingsActionID: """
                 \(DefaultEngineDefinitions.actionScriptHelpers)
                 const KIMI_ORIGIN_KEY = "quiper.kimi.settingsOrigin";

                 function kimiSettingsVisible() {
                   return location.pathname.startsWith("/settings");
                 }

                 function kimiSaveOrigin(url) {
                   try { sessionStorage.setItem(KIMI_ORIGIN_KEY, url); } catch {}
                 }

                 function kimiGetOrigin() {
                   try { return sessionStorage.getItem(KIMI_ORIGIN_KEY); } catch { return null; }
                 }

                 function kimiClearOrigin() {
                   try { sessionStorage.removeItem(KIMI_ORIGIN_KEY); } catch {}
                 }

                 async function kimiSoftNavigate(url) {
                   try {
                     const target = new URL(url, window.location.origin);
                     if (target.origin !== window.location.origin) { return; }
                     history.pushState(null, "", target.href);
                     window.dispatchEvent(new PopStateEvent("popstate"));
                   } catch {}
                 }

                 async function kimiWaitFor(check, timeoutMs = 3000) {
                   const start = Date.now();
                   return new Promise((resolve, reject) => {
                     const step = () => {
                       try {
                         if (check()) { resolve(true); return; }
                       } catch (err) {
                         reject(err);
                         return;
                       }
                       if (Date.now() - start >= timeoutMs) {
                         reject(new Error(`kimiWaitFor timed out after ${timeoutMs}ms`));
                         return;
                       }
                       setTimeout(step, 50);
                     };
                     setTimeout(step, 0);
                   });
                 }

                 if (kimiSettingsVisible()) {
                   const origin = kimiGetOrigin();
                   if (origin) {
                     await kimiSoftNavigate(origin);
                     await kimiWaitFor(() => !kimiSettingsVisible(), 3000);
                   }
                   kimiClearOrigin();
                 } else {
                   kimiSaveOrigin(location.href);
                   const target = new URL("/settings", window.location.origin);
                   await kimiSoftNavigate(target.href);
                   await kimiWaitFor(kimiSettingsVisible, 3000);
                 }
                 """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?github\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            html, body, #app, .main,
            .publisher-stage,
            #chat-box {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Qwen",
            url: "https://chat.qwen.ai?referrer=https://github.io/sassanh/quiper",
            focus_selector: ".message-input-textarea, textarea[placeholder='How can I help you today?'], textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function qwenTemporaryActive() {
                  const temporary = quiperFind([
                    "[role='button'][aria-label='Temporary Chat']",
                    ".temporary-chat-entry[aria-label='Temporary Chat']"
                  ]);
                  return temporary?.getAttribute("aria-pressed") === "true";
                }

                const temporary = quiperFind([
                  "[role='button'][aria-label='Temporary Chat']",
                  ".temporary-chat-entry[aria-label='Temporary Chat']"
                ]);
                if (qwenTemporaryActive()) {
                  await quiperClickElement(temporary, "Temporary Chat button not found");
                  await waitFor(() => !qwenTemporaryActive(), 1500);
                }

                const newChat = quiperFind([
                  "[role='button'][aria-label='New Chat']",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New chat", "New Chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                await waitFor(() => quiperFind([
                  ".message-input-textarea",
                  "textarea[placeholder='How can I help you today?']",
                  "textarea"
                ]), 1500);
                """,
                DefaultEngineDefinitions.newTemporarySessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function qwenTemporaryButton() {
                  return quiperFind([
                    "[role='button'][aria-label='Temporary Chat']",
                    ".temporary-chat-entry[aria-label='Temporary Chat']"
                  ]);
                }

                function qwenTemporaryActive() {
                  return qwenTemporaryButton()?.getAttribute("aria-pressed") === "true";
                }

                const newChat = quiperFind([
                  "[role='button'][aria-label='New Chat']",
                  "button[aria-label='New Chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New chat", "New Chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                await waitFor(() => qwenTemporaryButton(), 1500);

                if (!qwenTemporaryActive()) {
                  await quiperClickElement(qwenTemporaryButton(), "Temporary Chat button not found");
                  await waitFor(() => qwenTemporaryActive(), 1500);
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  [
                    "button[aria-label='Share']",
                    "[aria-label='Share']",
                    "[data-testid*='share']"
                  ],
                  ["Share"],
                  "Share button not found"
                );
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                await quiperClick(
                  [
                    "button[aria-label='Toggle sidebar']",
                    "button[aria-label='Expand sidebar']",
                    "button[aria-label='Collapse sidebar']"
                  ],
                  ["Toggle sidebar", "Expand sidebar", "Collapse sidebar"],
                  "Sidebar/history button not found"
                );
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function qwenSettingsVisible() {
                  return location.pathname.startsWith("/settings");
                }

                if (qwenSettingsVisible()) {
                  const backButton = quiperFind([
                    "button[aria-label='Back']",
                    "[aria-label='Back']"
                  ]);
                  await quiperClickElement(backButton, "Settings back button not found");
                  await waitFor(() => !qwenSettingsVisible(), 3000);
                } else {
                  const userMenu = quiperFind(["button.user-menu-btn"]);
                  await quiperClickElement(userMenu, "User menu button not found");
                  await waitFor(
                    () => quiperFindByText(["Settings"]) || quiperFind(["[role='menuitem']"]),
                    1500
                  );
                  const settingsItem = quiperFind(["[role='menuitem']"]) || quiperFindByText(["Settings"]);
                  await quiperClickElement(settingsItem, "Settings menu item not found");
                  await waitFor(qwenSettingsVisible, 4000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?github\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            html, body, #root,
            .desktop-layout,
            .desktop-layout-content,
            .home-page-layout-main {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "DeepSeek",
            url: "https://chat.deepseek.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea, div[contenteditable='true'], [role='textbox']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function deepseekComposerVisible() {
                  return [...document.querySelectorAll("textarea,[role='textbox'],div[contenteditable='true']")]
                    .some(deepseekVisible);
                }

                function deepseekAtHome() {
                  return new URL(location.href).pathname === "/";
                }

                function deepseekTopControls() {
                  return [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                    .filter(deepseekVisible)
                    .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                    .filter(({ rect }) => rect.y < 90 && rect.width >= 14 && rect.height >= 14)
                    .sort((a, b) => a.rect.x - b.rect.x);
                }

                async function deepseekClick(element, errorMessage) {
                  const target = quiperUsable(element);
                  if (!target) { throw new Error(errorMessage); }
                  target.click();
                  await new Promise((resolve) => setTimeout(resolve, 450));
                  return target;
                }

                const controls = deepseekTopControls();
                const newChat = controls.find(({ rect }, index) =>
                  index === 1 && rect.x < 180
                )?.element || quiperFind([
                  "a[href='/']",
                  "button[aria-label='New chat']",
                  "button[aria-label='New Chat']",
                  "[aria-label='New chat']",
                  "[aria-label='New Chat']"
                ]) || quiperFindByText(["New chat", "New Chat"]);

                if (newChat) {
                  await deepseekClick(newChat, "New chat button not found");
                  try {
                    await waitFor(() => deepseekComposerVisible() && deepseekAtHome(), 1600);
                  } catch {}
                }

                if (!deepseekComposerVisible() || !deepseekAtHome()) {
                  location.assign("/");
                }
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                const labelledShare = quiperFind([
                  "button[aria-label='Share']",
                  "[aria-label='Share']",
                  "[data-testid*='share']"
                ]) || quiperFindByText(["Share", "Share chat", "Share conversation"]);

                const topRightShare = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                  .filter(deepseekVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) =>
                    rect.y < 80 &&
                    rect.x > window.innerWidth - 90 &&
                    rect.width >= 20 &&
                    rect.height >= 20
                  )
                  .sort((a, b) => b.rect.x - a.rect.x)[0]?.element;

                await quiperClickElement(labelledShare || topRightShare, "Share button not found");
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function deepseekVisible(element) {
                  if (!element) { return false; }
                  const style = window.getComputedStyle(element);
                  const rect = element.getBoundingClientRect();
                  return style.display !== "none" &&
                    style.visibility !== "hidden" &&
                    rect.width > 0 &&
                    rect.height > 0;
                }

                function deepseekHistoryOpen() {
                  const hasHistoryLinks = [...document.querySelectorAll("a[href*='/a/chat/s/']")]
                    .filter(deepseekVisible)
                    .some((element) => element.getBoundingClientRect().x < 80);
                  const hasExpandedTopControls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                    .filter(deepseekVisible)
                    .some((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.y < 90 && rect.x > 180 && rect.x < 280 && rect.width >= 14 && rect.height >= 14;
                    });
                  return hasHistoryLinks || hasExpandedTopControls;
                }

                const wasOpen = deepseekHistoryOpen();
                const controls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
                  .filter(deepseekVisible)
                  .map((element) => ({ element, rect: element.getBoundingClientRect() }))
                  .filter(({ rect }) => rect.y < 90 && rect.width >= 14 && rect.height >= 14)
                  .sort((a, b) => a.rect.x - b.rect.x);
                const toggle = controls.find(({ rect }) =>
                  wasOpen ? rect.x > 220 && rect.x < 280 : rect.x < 90
                )?.element || quiperFind([
                  "button[aria-label='Open sidebar']",
                  "button[aria-label='Toggle sidebar']",
                  "[aria-label='Open sidebar']",
                  "[aria-label='Toggle sidebar']"
                ]);

                await quiperClickElement(toggle, "Sidebar/history button not found");
                await new Promise((resolve) => setTimeout(resolve, 350));
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                async function deepseekWaitFor(check, timeoutMs = 3000) {
                  const start = Date.now();
                  return new Promise((resolve, reject) => {
                    const step = () => {
                      if (check()) { resolve(true); return; }
                      if (Date.now() - start >= timeoutMs) {
                        reject(new Error(`deepseekWaitFor timed out after ${timeoutMs}ms`));
                        return;
                      }
                      setTimeout(step, 50);
                    };
                    setTimeout(step, 0);
                  });
                }

                function deepseekSettingsVisible() {
                  return !!quiperElements([".ds-modal"]).find((element) =>
                    /settings|设置/i.test(quiperText(element))
                  );
                }

                function deepseekUserMenu() {
                  return quiperElements(["div[tabindex='0']"]).find((element) => {
                    const text = quiperText(element);
                    return text.includes("@") && !!element.querySelector(".ds-icon svg");
                  });
                }

                function deepseekSettingsOption() {
                  return quiperElements(["div.ds-dropdown-menu-option"]).find((element) =>
                    /settings|设置/i.test(quiperText(element))
                  );
                }

                if (deepseekSettingsVisible()) {
                  const closeButton = quiperElements([".ds-modal-content__header-wrapper .ds-button--iconLabelPrimary"]).find(Boolean);
                  if (closeButton) {
                    closeButton.click();
                  }
                  await deepseekWaitFor(() => !deepseekSettingsVisible(), 3000);
                } else {
                  const userMenu = deepseekUserMenu();
                  if (!userMenu) { throw new Error("User menu button not found"); }
                  userMenu.click();
                  await deepseekWaitFor(deepseekSettingsOption, 1500);
                  const settingsItem = deepseekSettingsOption();
                  if (!settingsItem) { throw new Error("Settings menu item not found"); }
                  settingsItem.click();
                  await deepseekWaitFor(deepseekSettingsVisible, 3000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: "^https?://([^/]*\\.)?accounts\\.google\\.com(/|$)", action: .internalStay),
                RoutingRule(pattern: "^https?://([^/]*\\.)?appleid\\.apple\\.com(/|$)", action: .internalStay)
            ],
            customCSS: """
            html, body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "llama.cpp",
            url: "http://localhost:8080",
            focus_selector: "[data-slot='input-area'] textarea.text-md, textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const newChat = quiperFind(
                  ["button[aria-label='New chat']", "button[aria-label='New Chat']", "a[href*='new_chat=true']"]
                ) || quiperFindByText(["New chat", "New Chat"]);
                await quiperClickElement(newChat, "New chat button not found");
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const sidebarButton = [...document.querySelectorAll("button")]
                  .find((button) => quiperIsVisible(button) && /sidebar/i.test(quiperText(button)));
                if (!sidebarButton) { throw new Error("Sidebar/history button not found"); }
                sidebarButton.click();
                await new Promise((resolve) => window.requestAnimationFrame(resolve));
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function llamacppSettingsVisible() {
                  return location.hash.startsWith("#/settings/");
                }

                if (llamacppSettingsVisible()) {
                  window.location.hash = "";
                } else {
                  const entry = quiperFind([
                    "button[aria-label='Settings']",
                    "button[aria-label='Open settings']",
                    "[aria-label='Settings']"
                  ]) || quiperFindByText(["Settings"]);
                  await quiperClickElement(entry, "Settings button not found");
                  await waitFor(llamacppSettingsVisible, 3000);
                }
                """,
            ],
            customCSS: """
            body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "oMLX",
            url: "http://localhost:8480/admin/chat",
            focus_selector: ".input-container textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const newChat = quiperFindByText(["New Chat", "New chat"]) ||
                  quiperFind(["button[aria-label='New Chat']", "button[aria-label='New chat']"]);
                if (newChat) {
                  await quiperClickElement(newChat, "New chat button not found");
                } else {
                  window.location.assign("/admin/chat");
                }
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function omlxViewportVisible(element) {
                  if (!element) { return false; }
                  const rect = element.getBoundingClientRect();
                  const style = window.getComputedStyle(element);
                  return rect.width > 0 &&
                    rect.height > 0 &&
                    rect.right > 0 &&
                    rect.left < window.innerWidth &&
                    rect.bottom > 0 &&
                    rect.top < window.innerHeight &&
                    style.display !== "none" &&
                    style.visibility !== "hidden";
                }

                function omlxText(element) {
                  return [
                    element?.getAttribute("aria-label"),
                    element?.getAttribute("title"),
                    element?.innerText,
                    element?.textContent
                  ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
                }

                const visibleButtons = [...document.querySelectorAll("button,[role='button']")]
                  .filter(omlxViewportVisible);
                const explicitSidebarToggle = visibleButtons.find((element) =>
                  /chat\\.(open|close)_sidebar/i.test(omlxText(element))
                );
                const expandedNewChat = visibleButtons.find((element) => {
                  const rect = element.getBoundingClientRect();
                  return /New Chat/i.test(omlxText(element)) &&
                    rect.left >= 0 &&
                    rect.width > 100;
                });

                const sidebarToggle = explicitSidebarToggle || (expandedNewChat
                  ? visibleButtons
                    .filter((element) => {
                      const rect = element.getBoundingClientRect();
                      return rect.top < 80 &&
                        rect.left > 80 &&
                        rect.left < 280 &&
                        rect.width >= 18 &&
                        rect.height >= 18;
                    })
                    .sort((a, b) => b.getBoundingClientRect().left - a.getBoundingClientRect().left)[0]
                  : visibleButtons
                    .filter((element) => {
                      const rect = element.getBoundingClientRect();
                      const text = omlxText(element);
                      return rect.top < 80 &&
                        rect.left >= 0 &&
                        rect.left < 100 &&
                        rect.width >= 24 &&
                        rect.height >= 24 &&
                        !/oMLX|GitHub|settings|MODEL|PROFILE/i.test(text);
                    })
                    .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left)[0]);
                await quiperClickElement(sidebarToggle, "Sidebar/history button not found");
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function omlxSettingsVisible() {
                  return quiperFind([".right-sidebar-width"], { visible: true }) !== null ||
                    quiperElements([
                      "[role='dialog']",
                      "[class*='settings']",
                      "[data-testid*='settings']"
                    ]).some((element) => {
                      if (!quiperIsVisible(element)) { return false; }
                      return /settings/i.test(quiperText(element));
                    });
                }

                if (omlxSettingsVisible()) {
                  const closeButton = quiperFind(["button[title='Close settings']"], { visible: true });
                  if (closeButton) {
                    const target = quiperUsable(closeButton);
                    if (!target) { throw new Error("Close settings button not found"); }
                    target.click();
                  }
                } else {
                  const entry = quiperFind([
                    "button[aria-label='Settings']",
                    "button[aria-label='Open settings']",
                    "button[title='Show settings']",
                    "[aria-label='Settings']",
                    "a[href*='settings']"
                  ]) || quiperFindByText(["Settings"]);
                  await quiperClickElement(entry, "Settings button not found");
                  await waitFor(omlxSettingsVisible, 3000);
                }
                """,
            ],
            customCSS: """
            html {
              --bg-primary: transparent !important;
            }

            .right-sidebar-width, .sidebar-width {
              background-color: var(--bg-secondary);
            }
            """
        ),
        Service(
            name: "OpenClaw",
            url: "http://127.0.0.1:18789",
            focus_selector: ".agent-chat__composer-combobox > textarea, textarea",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const newSession = quiperFind([
                  "button[aria-label='New session']",
                  "[aria-label='New session']",
                  ".sidebar-new-session"
                ]) || quiperFindByText(["New session", "New chat"]);
                await quiperClickElement(newSession, "New session button not found");
                """,
                DefaultEngineDefinitions.historyActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function openclawRailVisible() {
                  return [...document.querySelectorAll(".sidebar-recent-session__link, [class*='recent-session']")]
                    .some((el) => {
                      if (!quiperIsVisible(el)) { return false; }
                      return el.getBoundingClientRect().x >= 0;
                    });
                }

                if (openclawRailVisible()) {
                  const collapse = quiperFind([
                    "button[aria-label='Collapse sidebar']",
                    "[aria-label='Collapse sidebar']"
                  ]);
                  if (!collapse) {
                    return;
                  }
                  await quiperClickElement(collapse, "Sidebar/collapse button not found");
                  return;
                }

                const expand = quiperFind([
                  "button[aria-label='Expand sidebar']",
                  "[aria-label='Expand sidebar']"
                ]);
                if (!expand) {
                  return;
                }
                await quiperClickElement(expand, "Sidebar/expand button not found");
                try {
                  await waitFor(openclawRailVisible, 2000);
                } catch {}
                """,
                DefaultEngineDefinitions.shareActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                const copy = quiperFind([
                  "button[aria-label='Copy as markdown']",
                  "[aria-label='Copy as markdown']",
                  ".chat-copy-btn"
                ], { visible: false });
                if (!copy) {
                  throw new Error("Copy/share button not found");
                }
                copy.click();
                await new Promise((resolve) => window.requestAnimationFrame(resolve));
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function openclawSettingsVisible() {
                  return location.pathname.startsWith("/settings");
                }

                if (openclawSettingsVisible()) {
                  const back = quiperFind([
                    "a[href*='/chat']",
                    "a[href='/chat']"
                  ]) || quiperFindByText(["Back", "Chat"]);
                  if (back) {
                    await quiperClickElement(back, "Settings back link not found");
                  } else {
                    window.location.assign("/chat");
                  }
                } else {
                  const entry = quiperFind([
                    "a[aria-label='Settings']",
                    "a[href*='/settings']",
                    "button[aria-label='Settings']",
                    "[aria-label='Settings']"
                  ]) || quiperFindByText(["Settings"]);
                  await quiperClickElement(entry, "Settings button not found");
                  await waitFor(openclawSettingsVisible, 3000);
                }
                """,
            ],
            customCSS: """
            body {
              background-color: transparent !important;
            }
            """
        ),
        Service(
            name: "Google",
            url: "https://www.google.com?referrer=https://github.io/sassanh/quiper",
            focus_selector: "textarea[name='q'], input[name='q'], textarea[aria-label='Search'], input[aria-label='Search'], textarea[title='Search'], input[title='Search'], input[type='search']",
            actionScripts: [
                DefaultEngineDefinitions.newSessionActionID: """
                const homeLink = [...document.querySelectorAll("a")].find((link) => {
                  try {
                    const rect = link.getBoundingClientRect();
                    const href = new URL(link.href, location.href);
                    return href.origin === location.origin &&
                      href.pathname === "/webhp" &&
                      rect.width > 0 &&
                      rect.height > 0;
                  } catch {
                    return false;
                  }
                });
                if (homeLink) {
                  homeLink.click();
                } else {
                  window.location.assign("https://www.google.com?referrer=https://github.io/sassanh/quiper");
                }
                """,
                DefaultEngineDefinitions.openSettingsActionID: """
                \(DefaultEngineDefinitions.actionScriptHelpers)
                function googleSettingsVisible() {
                  if (location.pathname === "/preferences" || location.pathname.startsWith("/preferences")) { return true; }
                  return quiperElements([
                    "[role='menu']",
                    "[class*='menu']",
                    "[data-testid*='settings']"
                  ]).some((element) => {
                    if (!quiperIsVisible(element)) { return false; }
                    return /search settings|advanced search|settings/i.test(quiperText(element));
                  });
                }

                const settingsGear = quiperFind([
                  "button[aria-label='Settings']",
                  "a[aria-label='Settings']",
                  "[aria-label='Settings']"
                ]) || quiperFindByText(["Settings"]);
                await quiperClickElement(settingsGear, "Settings button not found");
                if (!googleSettingsVisible()) {
                  await waitFor(googleSettingsVisible, 2000);
                }
                """,
            ],
            routingRules: [
                RoutingRule(pattern: ".*", action: .internalStay)
            ],
            customCSS: """
            body, div[style*="max-width:100%;"] {
              background-color: transparent !important;
            }
            """
        )
    ]
}
