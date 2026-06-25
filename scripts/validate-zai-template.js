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
const service = parseServices(source).find((candidate) => candidate.name === "Z.ai");
if (!service) {
  throw new Error("Z.ai default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Z.ai validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "Z.ai" });
  await delay(options.pageDelayMs);

  if (options.inspectOnly) {
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify(controls, null, 2));
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

  if (options.clickLabel) {
    const before = await runJSONProbe(stateScript());
    const click = await runJSONProbe(clickLabelScript(options.clickLabel));
    await delay(options.actionDelayMs);
    const after = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ before, click, after, controls: controls.items }, null, 2));
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

  for (const actionName of ["History", "New Session", "New Temporary Session", "Share"]) {
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

  console.log("Z.ai validation completed");
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
  throw new Error(`Timed out waiting for Share button; last state: ${JSON.stringify(lastState)}`);
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
  console.log(`Z.ai validation: ${message}`);
}

function formatState(state) {
  return [
    `composer=${state.composerVisible}`,
    `sidebar=${state.sidebarVisible}`,
    `dialog=${state.dialogVisible}`,
    `temporary=${state.temporaryActive}`,
  ].join(" ");
}

function controlStateScript() {
  return String.raw`
    const patterns = [/new/i, /chat/i, /share/i, /history/i, /temporary/i, /private/i, /menu/i, /sidebar/i, /close/i, /more/i];
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function label(el) {
      const value = [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.getAttribute("data-testid"),
        el.getAttribute("href"),
        el.getAttribute("placeholder"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim().slice(0, 120);
      return value.replace(/Open User Menu.*/i, "Open User Menu");
    }
    function clipped(value) {
      return String(value || "").split(/\s+/).filter(Boolean).slice(0, 8).join(" ");
    }
    function svgFacts(el) {
      return [...el.querySelectorAll("svg")].slice(0, 2).map((svg) => ({
        className: clipped(svg.getAttribute("class")),
        viewBox: svg.getAttribute("viewBox"),
        pathCount: svg.querySelectorAll("path").length,
        circleCount: svg.querySelectorAll("circle").length,
        lineCount: svg.querySelectorAll("line").length,
        polylineCount: svg.querySelectorAll("polyline").length,
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
          label: label(el).replace(/\/chat\/[^?\s]+/g, "/chat/:id"),
          ariaExpanded: el.getAttribute("aria-expanded"),
          ariaPressed: el.getAttribute("aria-pressed"),
          className: clipped(el.className),
          dataSlot: el.getAttribute("data-slot"),
          svg: svgFacts(el),
          disabled: el.disabled || el.getAttribute("aria-disabled"),
          rect: [
            Math.round(rect.x),
            Math.round(rect.y),
            Math.round(rect.width),
            Math.round(rect.height)
          ]
        };
        item.inChrome = rect.x < 330 || rect.y < 110 || rect.x > window.innerWidth - 180;
        return item;
      })
      .filter((item) => patterns.some((pattern) => pattern.test(item.label)) || item.tag === "textarea" || item.inChrome)
      .slice(0, 80);
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/chat\/[^?\s]+/g, "/chat/:id"),
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
    const sidebarVisible = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .some((el) => {
        const rect = el.getBoundingClientRect();
        return rect.x < 280 && rect.width > 120 && /New Chat|Chat/i.test(text(el));
      });
    const dialogVisible = [...document.querySelectorAll("[role='dialog'],[aria-modal='true']")].some(visible);
    const temporaryActive = [...document.querySelectorAll("button,[role='button'],span,div")]
      .filter(visible)
      .some((el) => /temporary|incognito|private/i.test(text(el)) && /active|selected|on/i.test(String(el.className || "") + " " + text(el)));
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/chat\/[^?\s]+/g, "/chat/:id"),
      composerVisible,
      sidebarVisible,
      dialogVisible,
      temporaryActive
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
    const shareButton = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .find((el) => /share/i.test(text(el)));
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/c\/[^?\s]+/g, "/c/:id").replace(/\/chat\/[^?\s]+/g, "/chat/:id"),
      shareVisible: Boolean(shareButton),
      label: shareButton ? text(shareButton).slice(0, 80) : ""
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
        el.getAttribute("data-testid"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const controls = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .map((el) => ({ el, rect: el.getBoundingClientRect() }))
      .filter(({ rect }) => rect.x < 340 || rect.y < 120 || rect.x > window.innerWidth - 180)
      .filter(({ el, rect }) => el.tagName.toLowerCase() !== "a" || rect.y < 180)
      .map(({ el, rect }) => ({
        el,
        label: text(el).replace(/\/chat\/[^?\s]+/g, "/chat/:id").slice(0, 100),
        rect: [
          Math.round(rect.x),
          Math.round(rect.y),
          Math.round(rect.width),
          Math.round(rect.height)
        ]
      }));
    const target = controls[${Number(index)}]?.el;
    if (!target) {
      throw new Error(JSON.stringify({ clicked: false, index: ${Number(index)}, count: controls.length }));
    }
    target.click();
    throw new Error(JSON.stringify({
      clicked: true,
      index: ${Number(index)},
      label: controls[${Number(index)}].label,
      rect: controls[${Number(index)}].rect
    }));
  `;
}

function clickLabelScript(rawLabel) {
  const label = JSON.stringify(rawLabel);
  return String.raw`
    const wanted = ${label};
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function text(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.getAttribute("data-testid"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
    }
    const target = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .find((el) => {
        const value = text(el);
        return value === wanted || value === wanted + " " + wanted || value.includes(wanted);
      });
    if (!target) {
      throw new Error(JSON.stringify({ clicked: false, label: wanted }));
    }
    const rect = target.getBoundingClientRect();
    target.click();
    throw new Error(JSON.stringify({
      clicked: true,
      label: text(target).replace(/\/chat\/[^?\s]+/g, "/chat/:id").slice(0, 100),
      rect: [
        Math.round(rect.x),
        Math.round(rect.y),
        Math.round(rect.width),
        Math.round(rect.height)
      ]
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
    const textarea = [...document.querySelectorAll("textarea,[contenteditable='true'],[role='textbox']")].find(visible);
    if (!textarea) {
      throw new Error(JSON.stringify({ sent: false, reason: "composer not found" }));
    }
    textarea.focus();
    if ("value" in textarea) {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value")?.set ||
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
      if (setter) {
        setter.call(textarea, "test");
      } else {
        textarea.value = "test";
      }
      textarea.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "test" }));
      textarea.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      textarea.textContent = "test";
      textarea.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: "test" }));
      textarea.dispatchEvent(new Event("change", { bubbles: true }));
    }
    await new Promise((resolve) => setTimeout(resolve, 200));
    const sendButton = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .find((el) => {
        const rect = el.getBoundingClientRect();
        const value = [
          el.getAttribute("aria-label"),
          el.getAttribute("title"),
          el.innerText,
          el.textContent
        ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim();
        return /send/i.test(value) || (rect.y > window.innerHeight * 0.45 && rect.x > window.innerWidth * 0.65 && rect.width >= 20 && rect.height >= 20);
      });
    if (!sendButton) {
      throw new Error(JSON.stringify({ sent: false, reason: "send button not found" }));
    }
    sendButton.click();
    const rect = sendButton.getBoundingClientRect();
    throw new Error(JSON.stringify({
      sent: true,
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
    clickLabel: null,
    inspectOnly: false,
    pageDelayMs: 800,
    readyPollMs: 250,
    readyTimeoutMs: 12000,
    requestTimeoutMs: 12000,
    sendDelayMs: 8000,
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
    } else if (value === "--click-label") {
      parsed.clickLabel = values[++index];
    } else if (value === "--inspect-only") {
      parsed.inspectOnly = true;
    } else if (value === "--page-delay-ms") {
      parsed.pageDelayMs = Number(values[++index]);
    } else if (value === "--send-delay-ms") {
      parsed.sendDelayMs = Number(values[++index]);
    } else if (value === "--send-test") {
      parsed.sendTest = true;
    } else if (value === "--share-timeout-ms") {
      parsed.shareTimeoutMs = Number(values[++index]);
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
  console.log("Usage: node scripts/validate-zai-template.js [--inspect-only]");
  console.log("Runs bounded live checks for Z.ai default focus/action templates through the dev validation bridge.");
}
