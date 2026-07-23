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
const service = parseServices(source).find((candidate) => candidate.name === "Kimi");

if (!service) {
  throw new Error("Kimi default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Kimi validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "Kimi" });
  await request("POST", "/session/start-current", { reload: options.reload });
  await waitForReady();
  await delay(options.pageDelayMs);

  if (options.inspectOnly) {
    console.log(JSON.stringify(await kimiState(), null, 2));
    return;
  }

  const results = [];
  await runDefaultAction("New Session");
  const newSessionState = await waitForState((state) => state.composerVisible);
  if (newSessionState.opaqueLayers.length > 0) {
    throw new Error(`Kimi still has opaque full-window layers: ${JSON.stringify(newSessionState.opaqueLayers)}`);
  }
  results.push(`New Session: composer=${newSessionState.composerVisible}`);
  results.push("Transparency: no opaque full-window layers");

  for (const size of ["small", "large"]) {
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} Kimi composer`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  const beforeHistory = await kimiState();
  await runDefaultAction("History");
  const afterHistory = await waitForState((state) => state.sidebarExpanded !== beforeHistory.sidebarExpanded);
  results.push(`History toggled: expanded=${beforeHistory.sidebarExpanded} -> ${afterHistory.sidebarExpanded}`);

  await runDefaultAction("History");
  const restoredHistory = await waitForState((state) => state.sidebarExpanded === beforeHistory.sidebarExpanded);
  results.push(`History restored: expanded=${restoredHistory.sidebarExpanded}`);

  if (restoredHistory.shareVisible) {
    await runDefaultAction("Share");
    results.push("Share: opened from the current conversation");
  } else {
    results.push("Share: skipped on an empty new chat");
  }

  console.log("Kimi validation completed");
  for (const result of results) {
    console.log(`- ${result}`);
  }
}

async function runDefaultAction(name) {
  const script = actions[name];
  if (!script) {
    throw new Error(`Default action not found: ${name}`);
  }
  const response = await request("POST", "/action/run", {
    action: name,
    script,
  });
  if (!response.ok) {
    throw new Error(`${name} failed: ${response.error || "unknown error"}`);
  }
  return response.result;
}

async function kimiState() {
  return runJSONProbe(`
    (() => {
      const visible = (element) => {
        if (!element) { return false; }
        const style = window.getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none" &&
          style.visibility !== "hidden" &&
          rect.width > 0 &&
          rect.height > 0;
      };
      const elements = (selector) => [...document.querySelectorAll(selector)].filter(visible);
      const sidebar = document.querySelector(".next-sidebar");
      const trigger = document.querySelector(".sidebar-main-trigger__button");
      const background = (element) => element ? window.getComputedStyle(element).backgroundColor : null;
      const opaqueLayers = [...document.querySelectorAll("body *")]
        .filter((element) => {
          if (!visible(element)) { return false; }
          const rect = element.getBoundingClientRect();
          const color = background(element);
          return rect.width >= window.innerWidth * 0.8 &&
            rect.height >= window.innerHeight * 0.2 &&
            color &&
            color !== "transparent" &&
            color !== "rgba(0, 0, 0, 0)";
        })
        .slice(0, 12)
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            tagName: element.tagName.toLowerCase(),
            id: String(element.id || "").slice(0, 80),
            className: String(element.className || "").slice(0, 160),
            background: background(element),
            rect: {
              x: Math.round(rect.x),
              y: Math.round(rect.y),
              width: Math.round(rect.width),
              height: Math.round(rect.height)
            }
          };
        });
      const summary = (element) => {
        if (!element) { return null; }
        const rect = element.getBoundingClientRect();
        return {
          className: String(element.className || "").slice(0, 160),
          ariaLabel: element.getAttribute("aria-label"),
          visible: visible(element),
          rect: {
            x: Math.round(rect.x),
            y: Math.round(rect.y),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          }
        };
      };
      throw JSON.stringify({
        origin: location.origin,
        path: location.pathname,
        composerVisible: elements(${JSON.stringify(service.focusSelector)}).length > 0,
        newChatVisible: elements("a.new-chat-btn, a[aria-label='New Chat']").length > 0,
        sidebarExpanded: Boolean(sidebar && visible(sidebar) &&
          sidebar.getBoundingClientRect().right > Math.min(100, sidebar.getBoundingClientRect().width / 2)),
        expandVisible: elements(".sidebar-main-trigger__button[aria-label='Expand Sidebar'], [aria-label='Expand Sidebar']").length > 0,
        shareVisible: elements("button[aria-label='Share'], [role='button'][aria-label='Share'], button[title='Share'], [data-testid*='share']").length > 0,
        backgrounds: {
          html: background(document.documentElement),
          body: background(document.body),
          app: background(document.querySelector("#app"))
        },
        opaqueLayers,
        sidebar: summary(sidebar),
        trigger: summary(trigger)
      });
    })();
  `);
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

async function waitForReady(timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastStatus = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastStatus = await request("GET", "/status");
    if (lastStatus.result?.ready &&
        lastStatus.result?.currentService === "Kimi" &&
        lastStatus.result?.isLoading === false) {
      return lastStatus.result;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Kimi; last status: ${JSON.stringify(redactStatus(lastStatus))}`);
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

async function waitForState(predicate, timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastState = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastState = await kimiState();
    if (predicate(lastState)) {
      return lastState;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Kimi state: ${JSON.stringify(lastState)}`);
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
    }, (response) => {
      let responseBody = "";
      response.on("data", (chunk) => {
        responseBody += chunk;
      });
      response.on("end", () => {
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

function redactStatus(response) {
  if (!response || typeof response !== "object") {
    return response;
  }
  return {
    ...response,
    result: response.result ? {
      ...response.result,
      currentServiceURL: redactURL(response.result.currentServiceURL),
      pageURL: redactURL(response.result.pageURL),
      pageTitle: response.result.pageTitle ? "(redacted)" : response.result.pageTitle,
    } : response.result,
  };
}

function redactURL(value) {
  if (!value || typeof value !== "string") {
    return value;
  }
  try {
    const url = new URL(value);
    return `${url.origin}${url.pathname}`;
  } catch {
    return "(redacted)";
  }
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

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseArgs(args) {
  const parsed = {
    inspectOnly: false,
    pageDelayMs: 5000,
    readyPollMs: 300,
    readyTimeoutMs: 12000,
    reload: false,
    requestTimeoutMs: 10000,
    viewportDelayMs: 500,
  };

  for (const arg of args) {
    if (arg === "--inspect-only") {
      parsed.inspectOnly = true;
    } else if (arg === "--reload") {
      parsed.reload = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return parsed;
}
