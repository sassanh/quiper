#!/usr/bin/env node

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { parseHelper, parseServices } = require("./audit-default-templates");

const repoRoot = path.resolve(__dirname, "..");
const settingsPath = path.join(repoRoot, "Quiper", "Settings.swift");
const portFilePath = path.join(os.tmpdir(), "quiper-template-validation-port.json");

const source = fs.readFileSync(settingsPath, "utf8");
const helperSource = parseHelper(source);
const service = parseServices(source).find((candidate) => candidate.name === "oMLX");
if (!service) {
  throw new Error("oMLX default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`oMLX validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "oMLX" });
  await delay(options.pageDelayMs);

  if (options.inspectOnly) {
    console.log(JSON.stringify(await runJSONProbe(inspectScript()), null, 2));
    return;
  }

  const results = [];
  for (const size of ["small", "large"]) {
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} oMLX composer`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  if (actions.History) {
    const beforeHistory = await runJSONProbe(stateScript());
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterHistory = await runJSONProbe(stateScript());
    if (afterHistory.sidebarMode === beforeHistory.sidebarMode) {
      throw new Error(`History did not toggle sidebar: ${beforeHistory.sidebarMode} -> ${afterHistory.sidebarMode}`);
    }
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterSecondHistory = await runJSONProbe(stateScript());
    if (afterSecondHistory.sidebarMode !== beforeHistory.sidebarMode) {
      throw new Error(`History did not toggle sidebar back: ${beforeHistory.sidebarMode} -> ${afterHistory.sidebarMode} -> ${afterSecondHistory.sidebarMode}`);
    }
    results.push(`History: ${beforeHistory.sidebarMode} -> ${afterHistory.sidebarMode} -> ${afterSecondHistory.sidebarMode}`);
  }

  for (const actionName of ["New Session", "Share"]) {
    if (!actions[actionName]) { continue; }
    await runDefaultAction(actionName);
    await delay(options.actionDelayMs);
    const state = await runJSONProbe(stateScript());
    results.push(`${actionName}: ${formatState(state)}`);
  }

  console.log("oMLX validation completed");
  for (const result of results) {
    console.log(`- ${result}`);
  }
}

async function runDefaultAction(name) {
  const response = await request("POST", "/action/run", {
    action: name,
    script: actions[name],
  });
  if (!response.ok) {
    throw new Error(`${name} failed: ${response.error || "unknown error"}`);
  }
  return response.result;
}

async function runJSONProbe(script) {
  const response = await request("POST", "/action/run", {
    action: "History",
    script,
  });
  if (response.ok) {
    throw new Error("Probe unexpectedly completed without returning JSON");
  }
  try {
    return JSON.parse(response.error || "{}");
  } catch {
    throw new Error(response.error || "Probe did not return JSON");
  }
}

async function waitForFocusVisible(label, timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastFocus = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastFocus = await request("POST", "/dom/query", {
      probe: "focusSelector",
      argument: service.focusSelector,
      focus: true,
    });
    if ((lastFocus.result?.visibleCount || 0) > 0) {
      return lastFocus.result;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for ${label}; visible focus count: ${lastFocus?.result?.visibleCount || 0}`);
}

function inspectScript() {
  return `
    (() => {
      const visible = (el) => {
        const rect = el.getBoundingClientRect();
        const style = window.getComputedStyle(el);
        return rect.width > 0 && rect.height > 0 &&
          style.display !== "none" &&
          style.visibility !== "hidden";
      };
      const text = (el) => [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim().slice(0, 140);
      const controls = [...document.querySelectorAll("button,a,[role='button'],[role='menuitem'],input,textarea,[contenteditable='true']")]
        .filter(visible)
        .map((el) => ({
          tag: el.tagName,
          role: el.getAttribute("role"),
          type: el.getAttribute("type"),
          aria: el.getAttribute("aria-label") || "",
          titleAttr: el.getAttribute("title") || "",
          id: el.id || "",
          classes: String(el.className || "").slice(0, 180),
          text: text(el),
          href: el.href ? new URL(el.href, location.href).origin + new URL(el.href, location.href).pathname : null,
          placeholder: el.getAttribute("placeholder") || "",
          x: Math.round(el.getBoundingClientRect().x),
          y: Math.round(el.getBoundingClientRect().y),
          w: Math.round(el.getBoundingClientRect().width),
          h: Math.round(el.getBoundingClientRect().height)
        }))
        .sort((a, b) => a.y - b.y || a.x - b.x);
      throw JSON.stringify({
        origin: location.origin,
        path: location.pathname,
        title: document.title,
        controls
      });
    })();
  `;
}

function stateScript() {
  return `
    (() => {
      const selector = ${JSON.stringify(service.focusSelector)};
      const matches = [...document.querySelectorAll(selector)];
      const visible = matches.filter((element) => {
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
      });
      const buttonVisible = (element) => {
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none" &&
          style.visibility !== "hidden" &&
          rect.width > 0 &&
          rect.height > 0 &&
          rect.right > 0 &&
          rect.left < window.innerWidth &&
          rect.bottom > 0 &&
          rect.top < window.innerHeight;
      };
      const buttonText = (element) => [
        element.getAttribute("aria-label"),
        element.getAttribute("title"),
        element.innerText,
        element.textContent
      ].filter(Boolean).join(" ").replace(/\\s+/g, " ").trim();
      const buttons = [...document.querySelectorAll("button,[role='button']")].filter(buttonVisible);
      const expandedNewChat = buttons.some((element) => {
        const rect = element.getBoundingClientRect();
        return /New Chat/i.test(buttonText(element)) && rect.width > 100;
      });
      const compactNewChat = buttons.some((element) => {
        const rect = element.getBoundingClientRect();
        return /New Chat/i.test(buttonText(element)) && rect.width <= 100;
      });
      const sidebarMode = expandedNewChat ? "open" : (compactNewChat ? "closed" : "unknown");
      throw JSON.stringify({
        origin: location.origin,
        path: location.pathname,
        title: document.title,
        focusCount: matches.length,
        visibleFocusCount: visible.length,
        activeTag: document.activeElement?.tagName || null,
        activePlaceholder: document.activeElement?.getAttribute("placeholder") || "",
        sidebarMode
      });
    })();
  `;
}

function request(method, pathname, body = undefined) {
  return new Promise((resolve, reject) => {
    const requestBody = body ? JSON.stringify(body) : "";
    const req = http.request({
      ...base,
      method,
      path: pathname,
      headers: body ? {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(requestBody),
      } : undefined,
    }, (res) => {
      let responseBody = "";
      res.on("data", (chunk) => {
        responseBody += chunk;
      });
      res.on("end", () => {
        try {
          resolve(JSON.parse(responseBody));
        } catch (error) {
          reject(error);
        }
      });
    });

    req.on("error", reject);
    req.setTimeout(options.requestTimeoutMs, () => {
      req.destroy(new Error(`Request timed out after ${options.requestTimeoutMs}ms: ${method} ${pathname}`));
    });
    req.end(requestBody);
  });
}

function liveScript(action) {
  return action.sourceLines
    .map((line) => (/^\s*\\\(Settings\.defaultActionScriptHelpers\)\s*$/.test(line) ? helperSource : line))
    .join("\n");
}

function readBridge() {
  const raw = fs.readFileSync(portFilePath, "utf8");
  const bridge = JSON.parse(raw);
  if (!bridge.port) {
    throw new Error(`Missing port in ${portFilePath}`);
  }
  return bridge;
}

function formatState(state) {
  return `${state.origin}${state.path} focus=${state.visibleFocusCount}/${state.focusCount} active=${state.activeTag || "none"} sidebar=${state.sidebarMode}`;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseArgs(args) {
  const parsed = {
    inspectOnly: false,
    pageDelayMs: 1200,
    viewportDelayMs: 600,
    actionDelayMs: 900,
    readyTimeoutMs: 10000,
    readyPollMs: 300,
    requestTimeoutMs: 10000,
  };

  for (const arg of args) {
    if (arg === "--inspect") {
      parsed.inspectOnly = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}
