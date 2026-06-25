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
const service = parseServices(source).find((candidate) => candidate.name === "Google");
if (!service) {
  throw new Error("Google default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Google validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "Google" });
  await delay(options.pageDelayMs);
  await waitForReady();

  if (options.inspectOnly) {
    console.log(JSON.stringify(await runJSONProbe(stateScript()), null, 2));
    return;
  }

  const results = [];
  for (const size of ["small", "large"]) {
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} Google search box`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  await navigateToSearchResults();
  await delay(options.navigationDelayMs);
  const beforeAction = await runJSONProbe(stateScript());

  await runDefaultAction("New Session");
  await delay(options.navigationDelayMs);
  await waitForReady();
  const persistentStatus = await request("GET", "/status");
  const afterAction = await waitForGoogleHome();
  if (persistentStatus.result?.websiteDataStorePersistent !== true) {
    throw new Error(`New Session did not switch back to persistent storage: ${JSON.stringify(persistentStatus.result)}`);
  }

  results.push(`before New Session: ${formatState(beforeAction)}`);
  results.push(`after New Session: ${formatState(afterAction)}`);

  console.log("Google validation completed");
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

async function waitForReady(timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastStatus = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastStatus = await request("GET", "/status");
    if (lastStatus.ok && (!lastStatus.result?.isLoading || googlePageIsUsable(lastStatus.result))) {
      return lastStatus.result;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Google page load; last status: ${JSON.stringify(redactStatus(lastStatus))}`);
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

async function waitForGoogleHome(timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastState = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastState = await runJSONProbe(stateScript());
    if (lastState.origin === "https://www.google.com" && ["/", "/webhp"].includes(lastState.path)) {
      return lastState;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Google home; last state: ${JSON.stringify(lastState)}`);
}

async function navigateToSearchResults() {
  const response = await request("POST", "/action/run", {
    action: "New Session",
    script: `
      window.location.assign("https://www.google.com/search?q=quiper+validation+test");
    `,
  });
  if (!response.ok) {
    throw new Error(response.error || "Could not navigate to Google search results");
  }
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
      throw JSON.stringify({
        origin: location.origin,
        path: location.pathname,
        hasSearchQuery: new URLSearchParams(location.search).has("q"),
        focusCount: matches.length,
        visibleFocusCount: visible.length,
        activeTag: document.activeElement?.tagName || null,
        activeName: document.activeElement?.getAttribute("name") || null
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

function googlePageIsUsable(status) {
  return status?.currentService === "Google" &&
    typeof status.pageURL === "string" &&
    status.pageURL.startsWith("https://www.google.com/");
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

function formatState(state) {
  return `${state.origin}${state.path} q=${state.hasSearchQuery} focus=${state.visibleFocusCount}/${state.focusCount} active=${state.activeTag || "none"}:${state.activeName || ""}`;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseArgs(args) {
  const parsed = {
    inspectOnly: false,
    pageDelayMs: 1800,
    viewportDelayMs: 700,
    navigationDelayMs: 1800,
    readyTimeoutMs: 12000,
    readyPollMs: 400,
    requestTimeoutMs: 10000,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--inspect") {
      parsed.inspectOnly = true;
    } else if (arg === "--page-delay-ms") {
      parsed.pageDelayMs = Number(args[index + 1]);
      index += 1;
    } else if (arg === "--navigation-delay-ms") {
      parsed.navigationDelayMs = Number(args[index + 1]);
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}
