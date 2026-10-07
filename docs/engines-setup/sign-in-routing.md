# Keeping Sign-In Inside the Overlay

[← All engines](../engines-setup)

Sign-in is the most common reason a login step leaves Quiper: when a link points at a domain the engine has no rule for, a **clicked** link opens in your default system browser — outside the overlay, where it can't share the engine's session. Pick the situation that matches you:

| Situation | What to use |
| :--- | :--- |
| An engine Quiper ships | Nothing — every template keeps Google sign-in inside the overlay, and the engines in these guides also ship rules for the providers they use (Apple, GitHub, or X) |
| A sign-in link you can see and click | Right-click it → **Open Link Here** |
| You want Quiper to ask first | Set the rule's action to **Prompt**, or hold **⌥** while clicking |
| You want it to always stay | An **Internal** routing rule (or tick **Remember my choice for this domain**) |

## Why it happens

- Links to the engine's own site always stay in the tab.
- For every other link, Quiper checks the engine's routing rules top to bottom; a click that matches no rule opens in the default system browser.
- Sign-in hops to the provider's auth domain (`accounts.google.com`, `appleid.apple.com`, `github.com`, `x.com`, …). Quiper's built-in templates ship **Internal** rules for whichever providers their sign-in uses, so the engines in these guides sign in without help. This page is for when a domain's rule is missing or reordered, or a custom engine never had one. Full rule semantics: [Domain Routing Rules](../engines#domain-routing-rules).

## Right-click the link (no rules needed)

Right-click the login link in the overlay and choose:

| Menu item | What it does |
| :--- | :--- |
| **Open Link Here** | Loads the link in the current tab |
| **Open Link in New Window** | Loads it in a Quiper popup that shares the engine's storage, so the session set during login survives |
| **Open Link in System Browser** | Opens it outside Quiper |
| **Open Private** | Opens it in a private tab |

These menu choices bypass routing rules entirely — no rule editing needed. They cover links you can click; they can't intercept a redirect the page performs on its own, so for a bounce in the middle of a login flow use **Prompt** or an **Internal** rule below.

## Ask first, remember the answer

1.  Open **Settings (`⌘ ⇧ ,`) → Engines → [engine] → Domain Routing** and set the login domain's **Action** to **Prompt**. Add the rule first if it isn't there — for Google, pattern `^https?://([^/]*\.)?accounts\.google\.com(/|$)`.
2.  Trigger the login again. The **Security & Routing** dialog asks how to open the link: **Open Here**, **Open in New Window**, **Open Externally**, or **Cancel**.
3.  Choose **Open Here** and tick **Remember my choice for this domain** — Quiper saves that host as an **Internal** rule at the top of the list, so the next sign-in goes straight through (see [Remembering Prompt Decisions](../engines#remembering-prompt-decisions)).

Two variants:

- **One-off ask:** hold **⌥** while clicking a link that would otherwise open in the system browser — Quiper asks instead, without changing any rules.
- **Ask about every off-site link:** append a rule with pattern `^https?://` and action **Prompt** at the bottom of the list. The engine's own site stays regardless of rules, and remembered domains keep their place above it. Heads-up: every external link — citations, docs pages — now asks too.

> [!NOTE]
> Pinned Tabs engines never navigate in place, so their choices are **Open in New Window** or **Open Externally** only (see [Pinned-Tab Engines](../engines#pinned-tab-engines)).

## Make it permanent: an Internal rule

For a domain you sign in with regularly, one **Internal** rule is the fix that needs no attention later: **Settings (`⌘ ⇧ ,`) → Engines → [engine] → Domain Routing → Add Routing Rule**, pattern `^https?://([^/]*\.)?accounts\.google\.com(/|$)` → **Internal**. Ready-to-paste patterns for the common providers: [Authentication Domains (OAuth Sign-In)](../engines#authentication-domains-oauth-sign-in).

For anything else, see [Troubleshooting & Diagnostics](../troubleshooting).
