---
title: Why I Built Spotlight for AI
description: Why Quiper brings persistent AI sessions into a native, keyboard-first macOS overlay instead of another browser tab.
date: "2026-07-23"
image: /blog/quiper-overlay.webp
blog: true
sidebar: false
aside: false
editLink: false
lastUpdated: false
prev: false
next: false
---

# Why I Built Spotlight for AI

<p class="post-meta"><time datetime="2026-07-23">July 23, 2026</time> · Sassan Haradji</p>

AI is becoming less of a place I occasionally visit and more of a regular part of daily work. I reach for it while coding, researching, writing, and handling the smaller questions between those tasks. As those interactions become more frequent, the mechanics of reaching it start to matter.

The usual ways of getting there create friction. A question starts with finding the right browser window, locating the right tab, and then remembering which conversation belongs to the task in front of me. A separate desktop client changes the container, but it still becomes another application to summon, position, and manage.

None of these steps is difficult on its own. Repeated throughout the day, however, they turn quick questions into context switches and pull attention away from the work that prompted them.

Quiper is my attempt to make that interaction feel more like Spotlight than a destination. Press one global shortcut—`⌥ Space` by default—and it appears over the application I am already using. Ask the question, copy what I need, and dismiss it with the same shortcut or `⌘Q`. The latter closes the overlay while Quiper continues running in the menu bar, ready for the next shortcut. It restores focus to the previous application without rearranging the workspace.

![Quiper floating over an active macOS workspace](/blog/quiper-overlay.webp)

*Quiper opens above the current workspace, then gets out of the way without changing that workspace.*

## Sessions should follow the work

A single AI conversation is rarely enough. A coding thread accumulates repository context. Research collects sources and dead ends. Writing benefits from a separate editorial conversation. Personal questions should not be mixed into any of them.

Quiper gives each configured engine up to ten independent session slots. I can leave those conversations attached to their tasks and switch directly with the keyboard instead of searching through a provider's history each time. The open tabs and their pages can be restored when Quiper starts again, so closing the overlay does not mean abandoning the thread.

The same model applies across engines. Quiper includes templates for services such as ChatGPT, Claude, Gemini, and Grok, but an engine is fundamentally a name, a URL, and a small amount of integration configuration. That makes room for other web-based providers as well as local interfaces such as Open WebUI and `llama.cpp`. Cloud and local tools can live in the same switcher without pretending they are the same model or forcing them through a common API.

This matters because different tasks call for different tools. It also avoids turning the overlay itself into another AI platform. Quiper manages access and sessions; the provider still provides the service.

## Why it is a native Mac app

Quiper is written in Swift and built with AppKit, SwiftUI, and the system WebKit framework. That choice is practical. A global overlay needs to cooperate with macOS window levels, Spaces, focus restoration, menu-bar behavior, global hotkeys, notifications, Keychain, and Touch ID. Those are operating-system concerns, not decorations around a web page.

An Electron application would bring another browser runtime to solve a problem already centered on web services. A browser extension would remain bounded by the browser and could not provide the same system-wide window and focus behavior over Xcode, a terminal, a writing app, or anything else on the Mac. Using native controls around `WKWebView` gives Quiper a focused shell while leaving each service's actual interface intact.

Native does not automatically mean fast, so the interaction model is deliberately keyboard-first. The global shortcut opens and closes the overlay. Number shortcuts jump to sessions or engines. Arrow-key bindings move between them. There are shortcuts for history, find, reload, zoom, and user-defined actions. The point is not to collect shortcuts; it is to make the path from “I need to ask this” to the right existing conversation short and predictable.

## Trust has to be inspectable

Quiper handles authenticated web sessions, so trust cannot depend on a privacy slogan. The application is open source and telemetry-free. Chat pages connect directly from their WebKit views to the providers or local engines configured by the user; Quiper does not proxy conversations through a Quiper service.

Stable release disk images are built by GitHub Actions from the public repository and published with GitHub artifact attestations. The provenance of a downloaded `Quiper.dmg` can be checked with the GitHub CLI rather than taken on faith:

```bash
gh attestation verify Quiper.dmg --repo sassanh/quiper
```

For local data that needs additional protection, Quiper can optionally place a selected engine's cookies, cache, local storage, and session data in encrypted APFS storage protected by Touch ID and the macOS Keychain. It is an opt-in local safeguard, not the center of the product.

That boundary is important. Quiper wraps web services; it does not replace them. When a prompt is sent to a cloud provider, that provider receives and stores the conversation according to its own policies. Quiper's encrypted local storage does not extend to a provider's servers, and Quiper cannot make a cloud conversation end-to-end encrypted.

## A smaller interruption

Context matters to people, too. Just as an AI needs the right context to give a useful answer, we need to stay connected to the work that prompted the question. Hunting for the right app or tab breaks that connection, even if only for a moment.

Quiper does not try to change how AI services work. It changes how much of my own context I have to leave to reach them. The overlay, persistent task-specific sessions, provider switching, and native keyboard control all serve that narrower goal: make AI available when it is useful, then make it disappear.

[Download the latest Quiper release](https://github.com/sassanh/quiper/releases/latest), [view the source on GitHub](https://github.com/sassanh/quiper), or [read the documentation](/getting-started).

<style scoped>
.post-meta {
  margin: 0.75rem 0 2rem;
  color: var(--vp-c-text-2);
  font-size: 0.9rem;
  line-height: 1.5;
}
</style>
