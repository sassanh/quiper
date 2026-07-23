---
layout: home

hero:
  name: Quiper
  text: |
    Spotlight for AI.
    Any engine. One shortcut.
  tagline: |
    A native macOS overlay for persistent
    conversations across cloud and local AI engines.
  actions:
    - theme: brand
      text: Download Quiper
      link: https://github.com/sassanh/quiper/releases/latest/download/Quiper.dmg
    - theme: alt
      text: Getting Started
      link: /getting-started

features:
  - icon: ⚡
    title: One Shortcut, Anywhere
    details: Open Quiper over the application you are using, ask what you need, and dismiss it without rearranging your workspace.
  - icon: 🗂️
    title: Persistent Sessions
    details: Keep up to ten independent sessions per engine for coding, research, writing, and everything between them.
  - icon: ↔️
    title: Cloud and Local Engines
    details: Switch between services such as ChatGPT, Claude, Gemini, and Grok or connect local interfaces like Open WebUI and llama.cpp.
  - icon: ⌨️
    title: Native and Keyboard-First
    details: Navigate engines, sessions, history, search, and custom actions through native macOS controls and configurable shortcuts.
  - icon: 🔒
    title: Optional Local Protection
    details: Protect selected engines' local WebKit data with Touch ID, Keychain, and encrypted APFS storage when you need it.
  - icon: ✓
    title: Open and Verifiable
    details: Quiper is open source and telemetry-free, with stable release provenance verifiable through GitHub artifact attestations.
---

<style>
@media (min-width: 640px) {
  .VPHero .text {
    max-width: 720px;
    font-size: 48px;
    line-height: 1.12;
  }
}

@media (min-width: 960px) {
  .VPHero.has-image .container {
    gap: 32px;
  }

  .VPHero.has-image .main,
  .VPHero.has-image .text {
    max-width: 560px;
  }

  .VPHero.has-image .image {
    min-width: 0;
  }
}

@media (min-width: 1280px) {
  .VPHero.has-image .container {
    gap: 48px;
    max-width: 1280px;
  }

  .VPHero.has-image .main,
  .VPHero.has-image .text {
    max-width: 640px;
  }
}
</style>
