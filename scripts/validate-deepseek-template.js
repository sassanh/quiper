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
const service = parseServices(source).find((candidate) => candidate.name === "DeepSeek");
if (!service) {
  throw new Error("DeepSeek default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`DeepSeek validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "DeepSeek" });
  await delay(options.pageDelayMs);

  if (options.inspectOnly) {
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify(controls, null, 2));
    return;
  }

  if (options.sendTest) {
    const before = await runJSONProbe(stateScript());
    const send = await runJSONProbe(sendTestMessageScript());
    await delay(options.sendDelayMs);
    const after = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ before, send, after, controls: controls.items }, null, 2));
    return;
  }

  if (options.clickTopRight) {
    const before = await runJSONProbe(stateScript());
    const click = await runJSONProbe(clickTopRightScript());
    await delay(options.actionDelayMs);
    const after = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ before, click, after, controls: controls.items }, null, 2));
    return;
  }

  if (options.clickChromeIndex !== null) {
    const before = await runJSONProbe(stateScript());
    const click = await runJSONProbe(clickChromeControlScript(options.clickChromeIndex));
    await delay(options.actionDelayMs);
    const after = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ before, click, after, controls: controls.items }, null, 2));
    return;
  }

  if (options.runAction) {
    await runDefaultAction(options.runAction);
    await delay(options.actionDelayMs);
    const state = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ action: options.runAction, state, controls: controls.items }, null, 2));
    return;
  }

  const results = [];
  for (const size of ["small", "large"]) {
    logStep(`check focus at ${size}`);
    await request("POST", "/viewport", { size });
    await delay(options.viewportDelayMs);
    const focus = await waitForFocusVisible(`${size} composer`);
    results.push(`${size} focus ${focus.visibleCount || 0}/${focus.count || 0}`);
  }

  logStep("inspect controls");
  const controls = await runJSONProbe(controlStateScript());
  results.push(`controls: ${controls.items.map((item) => item.label).join(" | ")}`);

  for (const actionName of ["History", "New Session", "Share"]) {
    if (!actions[actionName]) { continue; }
    if (actionName === "Share") {
      await runJSONProbe(sendTestMessageScript());
      await delay(options.sendDelayMs);
      await waitForShareVisible();
    }
    logStep(`run ${actionName}`);
    await runDefaultAction(actionName);
    await delay(options.actionDelayMs);
    const state = await runJSONProbe(stateScript());
    results.push(`${actionName}: ${formatState(state)}`);
  }

  console.log("DeepSeek validation completed");
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

async function waitForShareVisible(timeoutMs = options.shareTimeoutMs) {
  const startedAt = Date.now();
  let lastState = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastState = await runJSONProbe(shareStateScript());
    if (lastState.shareVisible) {
      return lastState;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for Share control; last state: ${JSON.stringify(lastState)}`);
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

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function logStep(message) {
  console.log(`DeepSeek validation: ${message}`);
}

function formatState(state) {
  return [
    `composer=${state.composerVisible}`,
    `sidebar=${state.sidebarVisible}`,
    `dialog=${state.dialogVisible}`,
    `share=${state.shareVisible}`,
  ].join(" ");
}

function controlStateScript() {
  return String.raw`
    const patterns = [/new/i, /chat/i, /share/i, /history/i, /menu/i, /sidebar/i, /close/i, /copy/i, /delete/i, /more/i];
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function clipped(value) {
      return String(value || "").split(/\s+/).filter(Boolean).slice(0, 8).join(" ");
    }
    function label(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.getAttribute("data-testid"),
        el.getAttribute("href"),
        el.getAttribute("placeholder"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim().slice(0, 120);
    }
    function sanitizeLabel(value) {
      return String(value || "")
        .replace(/\/a\/chat\/s\/[^?\s]+(?:\s+[^]*)?/g, "/a/chat/s/:id")
        .replace(/(Today|Yesterday)\s+[^]*/i, "$1");
    }
    function svgFacts(el) {
      return [...el.querySelectorAll("svg")].slice(0, 2).map((svg) => ({
        className: clipped(svg.getAttribute("class")),
        viewBox: svg.getAttribute("viewBox"),
        pathCount: svg.querySelectorAll("path").length,
        circleCount: svg.querySelectorAll("circle").length,
        lineCount: svg.querySelectorAll("line").length,
        pathD: [...svg.querySelectorAll("path")]
          .map((path) => path.getAttribute("d"))
          .filter(Boolean)
          .slice(0, 2)
          .map((value) => value.slice(0, 80))
      }));
    }
    const items = [...document.querySelectorAll("button,a,[role='button'],[role='menuitem'],input,textarea,[contenteditable='true']")]
      .filter(visible)
      .map((el) => {
        const rect = el.getBoundingClientRect();
        const item = {
          tag: el.tagName.toLowerCase(),
          role: el.getAttribute("role"),
          label: sanitizeLabel(label(el)),
          ariaExpanded: el.getAttribute("aria-expanded"),
          ariaPressed: el.getAttribute("aria-pressed"),
          className: clipped(el.className),
          dataTestId: el.getAttribute("data-testid"),
          disabled: el.disabled || el.getAttribute("aria-disabled"),
          svg: svgFacts(el),
          rect: [
            Math.round(rect.x),
            Math.round(rect.y),
            Math.round(rect.width),
            Math.round(rect.height)
          ]
        };
        item.inChrome = rect.x < 330 ||
          rect.y < 120 ||
          rect.x > window.innerWidth - 220 ||
          (rect.y > window.innerHeight * 0.45 && rect.y < window.innerHeight - 80 && rect.x > window.innerWidth * 0.45);
        return item;
      })
      .filter((item) => patterns.some((pattern) => pattern.test(item.label)) || item.tag === "textarea" || item.inChrome)
      .slice(0, 100);
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/a\/chat\/s\/[^?\s]+/g, "/a/chat/s/:id"),
      title: document.title,
      viewport: [window.innerWidth, window.innerHeight],
      items
    }));
  `;
}

function stateScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.getAttribute("placeholder"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const composerVisible = [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox']")].some(visible);
    const hasHistoryLinks = [...document.querySelectorAll("a[href*='/a/chat/s/']")]
      .filter(visible)
      .some((el) => el.getBoundingClientRect().x < 80);
    const hasExpandedTopControls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
      .filter(visible)
      .some((el) => {
        const rect = el.getBoundingClientRect();
        return rect.y < 90 && rect.x > 180 && rect.x < 280 && rect.width >= 14 && rect.height >= 14;
      });
    const sidebarVisible = hasHistoryLinks || hasExpandedTopControls;
    const dialogVisible = [...document.querySelectorAll("[role='dialog'],[aria-modal='true']")].some(visible);
    const shareVisible = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .some((el) => /share|create public link/i.test(text(el))) ||
      [...document.querySelectorAll("button,[role='button'],div[role='button']")]
        .filter(visible)
        .map((el) => ({ el, rect: el.getBoundingClientRect() }))
        .some(({ rect }) => rect.y < 80 && rect.x > window.innerWidth - 90 && rect.width >= 20 && rect.height >= 20);
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/a\/chat\/s\/[^?\s]+/g, "/a/chat/s/:id"),
      composerVisible,
      sidebarVisible,
      dialogVisible,
      shareVisible
    }));
  `;
}

function shareStateScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const labelledShare = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .find((el) => /share/i.test(text(el)));
    const topRightShare = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
      .filter(visible)
      .map((el) => ({ el, rect: el.getBoundingClientRect() }))
      .find(({ rect }) => rect.y < 80 && rect.x > window.innerWidth - 90 && rect.width >= 20 && rect.height >= 20);
    const shareButton = labelledShare || topRightShare?.el;
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/a\/chat\/s\/[^?\s]+/g, "/a/chat/s/:id"),
      shareVisible: Boolean(shareButton),
      label: shareButton ? text(shareButton).slice(0, 80) : ""
    }));
  `;
}

function sendTestMessageScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const input = [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox']")].find(visible);
    if (!input) {
      throw new Error(JSON.stringify({ sent: false, reason: "composer not found" }));
    }
    input.focus();
    if ("value" in input) {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set ||
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
      if (setter) {
        setter.call(input, "test");
      } else {
        input.value = "test";
      }
      input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "test" }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      input.textContent = "test";
      input.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "test" }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
    const sendButtons = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .filter((el) => {
        const rect = el.getBoundingClientRect();
        const value = text(el);
        return /send/i.test(value) || (rect.y > window.innerHeight * 0.45 && rect.x > window.innerWidth * 0.55 && rect.width >= 20 && rect.height >= 20 && !el.disabled);
      })
      .sort((a, b) => {
        const aPrimary = /primary|filled|circle/i.test(String(a.className || "")) ? 1 : 0;
        const bPrimary = /primary|filled|circle/i.test(String(b.className || "")) ? 1 : 0;
        if (aPrimary !== bPrimary) { return bPrimary - aPrimary; }
        return b.getBoundingClientRect().x - a.getBoundingClientRect().x;
      });
    const sendButton = sendButtons[0];
    if (sendButton) {
      sendButton.click();
    } else {
      const eventInit = {
        key: "Enter",
        code: "Enter",
        keyCode: 13,
        which: 13,
        bubbles: true,
        cancelable: true
      };
      input.dispatchEvent(new KeyboardEvent("keydown", eventInit));
      input.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    }
    const rect = sendButton?.getBoundingClientRect() || input.getBoundingClientRect();
    throw new Error(JSON.stringify({
      sent: true,
      method: sendButton ? "button" : "enter",
      rect: [
        Math.round(rect.x),
        Math.round(rect.y),
        Math.round(rect.width),
        Math.round(rect.height)
      ]
    }));
  `;
}

function clickTopRightScript() {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const candidates = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
      .filter(visible)
      .map((el) => ({ el, rect: el.getBoundingClientRect(), label: text(el) }))
      .filter(({ rect }) => rect.y < 80 && rect.x > window.innerWidth - 90 && rect.width >= 20 && rect.height >= 20)
      .sort((a, b) => b.rect.x - a.rect.x);
    const target = candidates[0]?.el;
    if (!target) {
      throw new Error(JSON.stringify({ clicked: false, reason: "top-right control not found" }));
    }
    target.click();
    const rect = target.getBoundingClientRect();
    throw new Error(JSON.stringify({
      clicked: true,
      label: text(target).slice(0, 80),
      rect: [
        Math.round(rect.x),
        Math.round(rect.y),
        Math.round(rect.width),
        Math.round(rect.height)
      ]
    }));
  `;
}

function clickChromeControlScript(index) {
  return String.raw`
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const controls = [...document.querySelectorAll("button,[role='button'],div[role='button']")]
      .filter(visible)
      .map((el) => ({ el, rect: el.getBoundingClientRect(), label: text(el) }))
      .filter(({ rect }) => rect.y < 90 && rect.width >= 14 && rect.height >= 14)
      .sort((a, b) => a.rect.x - b.rect.x);
    const target = controls[${Number(index)}]?.el;
    if (!target) {
      throw new Error(JSON.stringify({ clicked: false, index: ${Number(index)}, count: controls.length }));
    }
    target.click();
    const rect = target.getBoundingClientRect();
    throw new Error(JSON.stringify({
      clicked: true,
      index: ${Number(index)},
      label: text(target).slice(0, 80),
      rect: [
        Math.round(rect.x),
        Math.round(rect.y),
        Math.round(rect.width),
        Math.round(rect.height)
      ]
    }));
  `;
}

function parseArgs(values) {
  const parsed = {
    actionDelayMs: 1200,
    clickChromeIndex: null,
    clickTopRight: false,
    inspectOnly: false,
    pageDelayMs: 800,
    readyPollMs: 250,
    readyTimeoutMs: 12000,
    requestTimeoutMs: 12000,
    runAction: null,
    sendDelayMs: 10000,
    sendTest: false,
    shareTimeoutMs: 30000,
    viewportDelayMs: 600,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--action-delay-ms") {
      parsed.actionDelayMs = Number(values[++index]);
    } else if (value === "--click-chrome-index") {
      parsed.clickChromeIndex = Number(values[++index]);
    } else if (value === "--click-top-right") {
      parsed.clickTopRight = true;
    } else if (value === "--inspect-only") {
      parsed.inspectOnly = true;
    } else if (value === "--page-delay-ms") {
      parsed.pageDelayMs = Number(values[++index]);
    } else if (value === "--ready-timeout-ms") {
      parsed.readyTimeoutMs = Number(values[++index]);
    } else if (value === "--request-timeout-ms") {
      parsed.requestTimeoutMs = Number(values[++index]);
    } else if (value === "--run-action") {
      parsed.runAction = values[++index];
    } else if (value === "--send-delay-ms") {
      parsed.sendDelayMs = Number(values[++index]);
    } else if (value === "--send-test") {
      parsed.sendTest = true;
    } else if (value === "--share-timeout-ms") {
      parsed.shareTimeoutMs = Number(values[++index]);
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
  console.log("Usage: node scripts/validate-deepseek-template.js [--inspect-only]");
  console.log("Runs bounded live checks for DeepSeek default focus/action templates through the dev validation bridge.");
}
