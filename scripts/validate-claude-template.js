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
const service = parseServices(source).find((candidate) => candidate.name === "Claude");
if (!service) {
  throw new Error("Claude default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Claude validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  const results = [];

  logStep("select Claude");
  await request("POST", "/engine/select", { name: "Claude" });
  logStep("close floating UI");
  await closeFloatingUI();

  for (const size of ["small", "large"]) {
    logStep(`check focus at ${size}`);
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} editor`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  await request("POST", "/viewport", { size: "large" });
  await delay(options.viewportDelayMs);

  logStep("run New Session");
  await runDefaultAction("New Session");
  const normal = await waitForStatus((status) => /\/new$/.test(status.pageURL || ""), "normal /new");
  await waitForFocusVisible("normal /new editor");
  results.push(`new session ${urlShape(normal.pageURL)}`);

  logStep("run New Temporary Session");
  await runDefaultAction("New Temporary Session");
  const temporary = await waitForStatus((status) => /\/new\?incognito$/.test(status.pageURL || ""), "incognito /new");
  await waitForFocusVisible("incognito /new editor");
  results.push(`temporary session ${urlShape(temporary.pageURL)}`);

  logStep("return to normal New Session");
  await runDefaultAction("New Session");
  const normalAgain = await waitForStatus((status) => /\/new$/.test(status.pageURL || ""), "normal /new after incognito");
  results.push(`normal after temporary ${urlShape(normalAgain.pageURL)}`);

  logStep("create disposable chat");
  await runProbeScript("New Session", createDisposableChatScript());
  const chat = await waitForStatus((status) => /\/chat\//.test(status.pageURL || ""), "disposable chat URL", 12000);
  results.push(`disposable chat ${urlShape(chat.pageURL)}`);

  logStep("run Share");
  await runDefaultAction("Share");
  const shareState = await runJSONProbe(shareStateScript());
  if (!shareState.shareDialog) {
    throw new Error("Claude Share did not leave the share dialog open");
  }
  results.push("share dialog visible");
  logStep("close share dialog");
  await closeFloatingUI();

  for (const size of ["large", "small"]) {
    logStep(`toggle History at ${size}`);
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const before = await runJSONProbe(sidebarStateScript());
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterOne = await runJSONProbe(sidebarStateScript());
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterTwo = await runJSONProbe(sidebarStateScript());

    if (before.toggleLabel === afterOne.toggleLabel || afterOne.toggleLabel === afterTwo.toggleLabel) {
      throw new Error(`Claude History did not toggle at ${size} viewport`);
    }
    results.push(`history toggle ${size}: ${before.toggleLabel} -> ${afterOne.toggleLabel} -> ${afterTwo.toggleLabel}`);
  }

  console.log("Claude validation passed");
  for (const result of results) {
    console.log(`- ${result}`);
  }
}

function logStep(message) {
  console.log(`Claude validation: ${message}`);
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

async function runProbeScript(action, script) {
  const response = await request("POST", "/action/run", { action, script });
  if (!response.ok) {
    throw new Error(response.error || "Probe script failed");
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

async function closeFloatingUI() {
  await runProbeScript("History", `
    document.dispatchEvent(new KeyboardEvent("keydown", {
      key: "Escape",
      code: "Escape",
      keyCode: 27,
      which: 27,
      bubbles: true
    }));
    await new Promise((resolve) => setTimeout(resolve, 350));
  `);
}

async function waitForStatus(predicate, label, timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastStatus = null;
  while (Date.now() - startedAt <= timeoutMs) {
    const response = await request("GET", "/status");
    lastStatus = response.result || null;
    if (lastStatus && predicate(lastStatus)) {
      return lastStatus;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for ${label}; last URL: ${lastStatus?.pageURL || "(unknown)"}`);
}

async function waitForFocusVisible(label, timeoutMs = options.readyTimeoutMs) {
  const startedAt = Date.now();
  let lastFocus = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastFocus = await request("POST", "/dom/query", {
      probe: "focusSelector",
      argument: service.focusSelector,
      focus: false,
    });
    if ((lastFocus.result?.visibleCount || 0) > 0) {
      await delay(options.editorSettleDelayMs);
      return lastFocus.result;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for ${label}; visible focus count: ${lastFocus?.result?.visibleCount || 0}`);
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
  if (!fs.existsSync(portFilePath)) {
    throw new Error(`Bridge port file not found at ${portFilePath}. Launch QuiperDev with --template-validation-server first.`);
  }
  return JSON.parse(fs.readFileSync(portFilePath, "utf8"));
}

function urlShape(value) {
  return String(value || "").replace(/\/chat\/[^/?#]+/, "/chat/:id");
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createDisposableChatScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }

    async function waitForInput() {
      const selector = [
        "[data-testid='chat-input'][contenteditable='true']",
        "[data-testid='chat-input'] div[contenteditable='true']",
        "div[contenteditable='true'][role='textbox']"
      ].join(", ");
      const startedAt = Date.now();
      while (Date.now() - startedAt <= 6000) {
        const input = document.querySelector(selector);
        if (input && visible(input)) { return input; }
        await new Promise((resolve) => setTimeout(resolve, 150));
      }
      return null;
    }

    const input = await waitForInput();
    if (!input) { throw new Error("Claude input not found"); }

    input.focus();
    const range = document.createRange();
    range.selectNodeContents(input);
    range.collapse(false);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.execCommand("insertText", false, "test");
    input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "test" }));
    async function waitForSend() {
      const startedAt = Date.now();
      while (Date.now() - startedAt <= 4000) {
        const send = [...document.querySelectorAll("button,[role='button']")].find((element) => {
          const label = [
            element.getAttribute("aria-label"),
            element.getAttribute("title"),
            element.getAttribute("data-testid"),
            element.innerText,
            element.textContent
          ].filter(Boolean).join(" ");
          return visible(element) &&
            !element.disabled &&
            element.getAttribute("aria-disabled") !== "true" &&
            /send/i.test(label);
        });
        if (send) { return send; }
        await new Promise((resolve) => setTimeout(resolve, 150));
      }
      return null;
    }

    const send = await waitForSend();
    if (!send) { throw new Error("Claude send button not enabled"); }
    send.scrollIntoView({ block: "center", inline: "center" });
    for (const eventName of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
      const event = eventName.startsWith("pointer")
        ? new PointerEvent(eventName, { bubbles: true, cancelable: true, pointerType: "mouse", isPrimary: true })
        : new MouseEvent(eventName, { bubbles: true, cancelable: true, view: window });
      send.dispatchEvent(event);
    }
    send.click();
    const startedAt = Date.now();
    while (Date.now() - startedAt <= 10000) {
      if (/\/chat\//.test(location.pathname)) { return; }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    throw new Error("Claude did not navigate to a chat after Send");
  `;
}

function shareStateScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }

    const shareDialog = [...document.querySelectorAll("[role='dialog']")].some((element) => {
      const text = (element.innerText || element.textContent || "").replace(/\s+/g, " ").trim();
      return visible(element) && /share chat|create public link|create share link/i.test(text);
    });
    throw new Error(JSON.stringify({ shareDialog, url: location.href }));
  `;
}

function sidebarStateScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }

    const button = [...document.querySelectorAll(
      "button[data-testid='pin-sidebar-toggle'], button[aria-label*='sidebar' i]"
    )].find(visible);
    const nav = [...document.querySelectorAll("nav[aria-label='Sidebar']")].find(visible);
    const navRect = nav ? nav.getBoundingClientRect() : null;
    throw new Error(JSON.stringify({
      toggleLabel: button?.getAttribute("aria-label") || null,
      navWidth: navRect ? Math.round(navRect.width) : 0,
      url: location.href
    }));
  `;
}

function parseArgs(values) {
  const parsed = {
    actionDelayMs: 400,
    editorSettleDelayMs: 1200,
    readyPollMs: 250,
    readyTimeoutMs: 16000,
    requestTimeoutMs: 12000,
    viewportDelayMs: 600,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--action-delay-ms") {
      parsed.actionDelayMs = Number(values[++index]);
    } else if (value === "--editor-settle-delay-ms") {
      parsed.editorSettleDelayMs = Number(values[++index]);
    } else if (value === "--ready-timeout-ms") {
      parsed.readyTimeoutMs = Number(values[++index]);
    } else if (value === "--request-timeout-ms") {
      parsed.requestTimeoutMs = Number(values[++index]);
    } else if (value === "--viewport-delay-ms") {
      parsed.viewportDelayMs = Number(values[++index]);
    } else if (value === "--help") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument ${value}`);
    }
  }

  return parsed;
}

function printHelp() {
  console.log("Usage: node scripts/validate-claude-template.js");
  console.log("Runs bounded live checks for Claude default focus/action templates through the dev validation bridge.");
}
