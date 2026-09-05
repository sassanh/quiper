# Engine Setup Guides — TODO

Every engine Quiper ships as a one-click template should eventually get a setup guide under this folder, following the same shape as [gemini.md](gemini.md): a "starting point" table, numbered steps from zero to a working engine, optional refinements, and a troubleshooting table.

**Done so far:** Gemini ✅, Grok ✅

## Cloud engines

- [ ] **ChatGPT** — `https://chatgpt.com` — OpenAI account creation and sign-in; keep the auth flow inside the overlay via routing rules (mirror Gemini's accounts.google.com treatment).
- [ ] **Claude** — `https://claude.ai` — Anthropic account creation and sign-in.
- [x] **Grok** — `https://grok.com` — sign-in with an X account; call out the overlap with both the X guide and Gemini's hotkey-conflict note if relevant.
- [ ] **X** — `https://x.com/i/grok` — uses the Grok assistant integrated into X; requires an X account, not a separate Grok signup.
- [ ] **DeepSeek** — `https://chat.deepseek.com` — account creation (email/phone).
- [ ] **Kimi** — `https://www.kimi.com` — Moonshot AI account creation and sign-in.
- [ ] **Qwen** — `https://chat.qwen.ai` — account creation and sign-in.
- [ ] **Z.ai** — `https://chat.z.ai` — Z.ai account creation and sign-in.
- [ ] **Google** — `https://www.google.com` — works without an account for plain search; cover what signing in adds (personalized results, AI features).

## Local / self-hosted engines

These guides need a "run the server first" prerequisite section before the standard install/open/verify flow.

- [ ] **Open WebUI** — `http://localhost:8080` — point Quiper at your own server; note the default-port overlap with llama.cpp (`localhost:8080`) and how to handle running both.
- [ ] **llama.cpp** — `http://localhost:8080` — building/launching `llama-server` with a model before opening the engine.
- [ ] **oMLX** — `http://localhost:8480/admin/chat` — Apple Silicon local inference; getting the server running and loading models.
- [ ] **OpenClaw** — `http://127.0.0.1:18789` — controlling local agents from the overlay; also document its bundled actions (new session, session-history rail, share as markdown, open settings).

## Per-guide checklist

Use exact bundled-template URLs above (including the `?referrer=` parameter) when telling readers to re-add an engine manually. Each finished guide must also be wired up:

1. Add an entry to **Available guides** in [`../engines-setup.md`](../engines-setup.md).
2. Add a sidebar item under "Setting Up Engines" in `docs/.vitepress/config.mts`.
