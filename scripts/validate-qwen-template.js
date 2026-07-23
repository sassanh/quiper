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
const service = parseServices(source).find((candidate) => candidate.name === "Qwen");

if (!service) {
  throw new Error("Qwen default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Qwen validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "Qwen" });
  await request("POST", "/session/start-current", { reload: options.reload });
  await waitForReady();
  await delay(options.pageDelayMs);

  if (options.inspectOnly) {
    console.log(JSON.stringify(await qwenState(), null, 2));
    return;
  }

  const results = [];
  await runDefaultAction("New Session");
  const normalState = await waitForState((state) => state.composerVisible && !state.temporaryActive);
  results.push(`New Session: ${formatState(normalState)}`);

  for (const size of ["small", "large"]) {
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} Qwen composer`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  const beforeHistory = await qwenState();
  await runDefaultAction("History");
  await delay(options.actionDelayMs);
  const afterHistory = await qwenState();
  if (!sidebarChanged(beforeHistory, afterHistory)) {
    throw new Error(`History did not change sidebar state: ${JSON.stringify({ beforeHistory, afterHistory })}`);
  }
  results.push(`History toggled: ${formatSidebar(beforeHistory)} -> ${formatSidebar(afterHistory)}`);

  await runDefaultAction("History");
  await delay(options.actionDelayMs);
  const restoredHistory = await qwenState();
  if (!sidebarChanged(afterHistory, restoredHistory)) {
    throw new Error(`History did not restore sidebar state: ${JSON.stringify({ afterHistory, restoredHistory })}`);
  }
  results.push(`History restored: ${formatSidebar(restoredHistory)}`);

  await runDefaultAction("New Temporary Session");
  const temporaryState = await waitForState((state) => state.composerVisible && state.temporaryActive);
  results.push(`New Temporary Session: ${formatState(temporaryState)}`);

  await runDefaultAction("New Session");
  const restoredNormalState = await waitForState((state) => state.composerVisible && !state.temporaryActive);
  results.push(`New Session after temporary: ${formatState(restoredNormalState)}`);

  if (restoredNormalState.shareVisible) {
    await runDefaultAction("Share");
    results.push("Share: opened from the current conversation");
  } else {
    results.push("Share: skipped on an empty new chat");
  }

  console.log("Qwen validation completed");
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

async function qwenState() {
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
      const temporary = elements("[role='button'][aria-label='Temporary Chat'], .temporary-chat-entry[aria-label='Temporary Chat']")[0];
      const sidebar = elements("button[aria-label='Toggle sidebar'], button[aria-label='Expand sidebar'], button[aria-label='Collapse sidebar']")[0];
      const share = elements("button[aria-label='Share'], [role='button'][aria-label='Share'], [data-testid*='share']");
      throw JSON.stringify({
        origin: location.origin,
        path: location.pathname,
        composerVisible: elements(${JSON.stringify(service.focusSelector)}).length > 0,
        temporaryActive: temporary?.getAttribute("aria-pressed") === "true",
        temporaryVisible: Boolean(temporary),
        newChatVisible: elements("[role='button'][aria-label='New Chat'], button[aria-label='New Chat']").length > 0,
        historySearchVisible: elements("input.chat-search-input").length > 0,
        sidebarLabel: sidebar?.getAttribute("aria-label") || null,
        sidebarClass: sidebar?.className || null,
        shareVisible: share.length > 0
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
        lastStatus.result?.currentService === "Qwen" &&
        lastStatus.result?.isLoading === false) {
      return lastStatus.result;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Qwen; last status: ${JSON.stringify(redactStatus(lastStatus))}`);
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
    lastState = await qwenState();
    if (predicate(lastState)) {
      return lastState;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Qwen state: ${JSON.stringify(lastState)}`);
}

function sidebarChanged(before, after) {
  return before.newChatVisible !== after.newChatVisible ||
    before.historySearchVisible !== after.historySearchVisible ||
    before.sidebarLabel !== after.sidebarLabel ||
    before.sidebarClass !== after.sidebarClass;
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

function formatState(state) {
  return `composer=${state.composerVisible} temporary=${state.temporaryActive}`;
}

function formatSidebar(state) {
  return `${state.sidebarLabel || "unlabelled"} newChat=${state.newChatVisible} search=${state.historySearchVisible}`;
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
    actionDelayMs: 500,
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
