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
const service = parseServices(source).find((candidate) => candidate.name === "Open WebUI");
if (!service) {
  throw new Error("Open WebUI default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`Open WebUI validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  await request("POST", "/engine/select", { name: "Open WebUI" });
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

  if (options.pressEscape) {
    const before = await runJSONProbe(stateScript());
    await runJSONProbe(pressEscapeScript());
    await delay(options.actionDelayMs);
    const after = await runJSONProbe(stateScript());
    const controls = await runJSONProbe(controlStateScript());
    console.log(JSON.stringify({ before, after, controls: controls.items }, null, 2));
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

  for (const actionName of ["History", "New Session", "New Temporary Session", "Share"]) {
    if (!actions[actionName]) { continue; }
    if (actionName === "Share") {
      await runJSONProbe(sendTestMessageScript());
      await delay(options.sendDelayMs);
      await waitForShareReady();
    }
    logStep(`run ${actionName}`);
    await runDefaultAction(actionName);
    await delay(options.actionDelayMs);
    const state = await runJSONProbe(stateScript());
    results.push(`${actionName}: ${formatState(state)}`);
  }

  console.log("Open WebUI validation completed");
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

async function waitForShareReady(timeoutMs = options.shareTimeoutMs) {
  const startedAt = Date.now();
  let lastState = null;
  while (Date.now() - startedAt <= timeoutMs) {
    lastState = await runJSONProbe(stateScript());
    if (lastState.canShare) {
      return lastState;
    }
    await delay(options.readyPollMs);
  }
  throw new Error(`Timed out waiting for share controls; last state: ${JSON.stringify(lastState)}`);
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
  console.log(`Open WebUI validation: ${message}`);
}

function formatState(state) {
  return [
    `composer=${state.composerVisible}`,
    `sidebar=${state.sidebarVisible}`,
    `dialog=${state.dialogVisible}`,
    `temporary=${state.temporaryActive}`,
    `share=${state.shareVisible}`,
  ].join(" ");
}

function controlStateScript() {
  return String.raw`
    const patterns = [/new/i, /chat/i, /share/i, /temporary/i, /copy/i, /sidebar/i, /menu/i, /more/i, /close/i, /download/i, /archive/i];
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
        .replace(/\/c\/[^?\s]+/g, "/c/:id")
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
      url: location.href.replace(/\/c\/[^?\s]+/g, "/c/:id"),
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
    const composerVisible = [...document.querySelectorAll("#chat-input[contenteditable='true'],textarea,div[contenteditable='true'],[role='textbox']")].some(visible);
    const sidebarVisible = [...document.querySelectorAll("aside,nav,[id*='sidebar'],[class*='sidebar']")]
      .filter(visible)
      .some((el) => {
        const rect = el.getBoundingClientRect();
        return rect.x < 120 && rect.width > 120 && rect.height > window.innerHeight * 0.45;
      }) || [...document.querySelectorAll("a[href^='/c/']")]
      .filter(visible)
      .some((el) => el.getBoundingClientRect().x < 320);
    const dialogVisible = [...document.querySelectorAll("[role='dialog'],[aria-modal='true']")].some(visible);
    const temporaryActive = new URL(location.href).searchParams.get("temporary-chat") === "true" ||
      [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .some((el) => /temporary/i.test(text(el)) && (el.getAttribute("aria-pressed") === "true" || /active|selected|primary/i.test(String(el.className))));
    const shareVisible = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .some((el) => /share|copy link|public link/i.test(text(el)));
    const canShare = shareVisible || [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .some((el) => {
        const rect = el.getBoundingClientRect();
        return rect.y < 120 && rect.x > window.innerWidth - 170 && rect.width >= 20 && rect.height >= 20;
      });
    throw new Error(JSON.stringify({
      url: location.href.replace(/\/c\/[^?\s]+/g, "/c/:id"),
      composerVisible,
      sidebarVisible,
      dialogVisible,
      temporaryActive,
      shareVisible,
      canShare
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
    const input = [...document.querySelectorAll("#chat-input[contenteditable='true'],textarea,div[contenteditable='true'],[role='textbox']")].find(visible);
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
    await new Promise((resolve) => setTimeout(resolve, 350));
    const sendButton = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .filter((el) => {
        const rect = el.getBoundingClientRect();
        return /send/i.test(text(el)) ||
          (rect.y > window.innerHeight * 0.45 && rect.x > window.innerWidth * 0.55 && rect.width >= 20 && rect.height >= 20 && !el.disabled);
      })
      .sort((a, b) => b.getBoundingClientRect().x - a.getBoundingClientRect().x)[0];
    if (sendButton) {
      sendButton.click();
    } else {
      const eventInit = { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true };
      input.dispatchEvent(new KeyboardEvent("keydown", eventInit));
      input.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    }
    const rect = sendButton?.getBoundingClientRect() || input.getBoundingClientRect();
    throw new Error(JSON.stringify({
      sent: true,
      method: sendButton ? "button" : "enter",
      rect: [Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)]
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
    const controls = [...document.querySelectorAll("button,[role='button'],a")]
      .filter(visible)
      .map((el) => ({ el, rect: el.getBoundingClientRect(), label: text(el).slice(0, 80) }))
      .filter(({ rect }) => rect.y < 140 || rect.x < 330 || rect.x > window.innerWidth - 220)
      .sort((a, b) => (a.rect.y - b.rect.y) || (a.rect.x - b.rect.x));
    const item = controls[${Number(index)}];
    if (!item) {
      throw new Error(JSON.stringify({ clicked: false, reason: "index out of range", count: controls.length }));
    }
    item.el.click();
    throw new Error(JSON.stringify({
      clicked: true,
      index: ${Number(index)},
      label: item.label,
      rect: [Math.round(item.rect.x), Math.round(item.rect.y), Math.round(item.rect.width), Math.round(item.rect.height)]
    }));
  `;
}

function clickLabelScript(pattern) {
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
    const pattern = new RegExp(${JSON.stringify(pattern)}, "i");
    const element = [...document.querySelectorAll("button,a,[role='button'],[role='menuitem'],input")]
      .filter(visible)
      .find((el) => pattern.test(text(el)));
    if (!element) {
      throw new Error(JSON.stringify({ clicked: false, reason: "label not found", pattern: ${JSON.stringify(pattern)} }));
    }
    const rect = element.getBoundingClientRect();
    element.click();
    throw new Error(JSON.stringify({
      clicked: true,
      label: text(element).slice(0, 80),
      rect: [Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)]
    }));
  `;
}

function pressEscapeScript() {
  return String.raw`
    const eventInit = { key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true, cancelable: true };
    document.activeElement?.dispatchEvent(new KeyboardEvent("keydown", eventInit));
    document.dispatchEvent(new KeyboardEvent("keydown", eventInit));
    window.dispatchEvent(new KeyboardEvent("keydown", eventInit));
    document.activeElement?.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    document.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    window.dispatchEvent(new KeyboardEvent("keyup", eventInit));
    throw new Error(JSON.stringify({ pressed: "Escape" }));
  `;
}

function parseArgs(values) {
  const parsed = {
    actionDelayMs: 900,
    clickChromeIndex: null,
    clickLabel: null,
    inspectOnly: false,
    pageDelayMs: 1600,
    pressEscape: false,
    readyPollMs: 300,
    readyTimeoutMs: 9000,
    requestTimeoutMs: 10000,
    runAction: null,
    sendDelayMs: 3500,
    sendTest: false,
    shareTimeoutMs: 10000,
    viewportDelayMs: 400,
  };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--inspect-only") {
      parsed.inspectOnly = true;
    } else if (value === "--press-escape") {
      parsed.pressEscape = true;
    } else if (value === "--send-test") {
      parsed.sendTest = true;
    } else if (value === "--click-chrome-index") {
      parsed.clickChromeIndex = Number(values[++index]);
    } else if (value === "--click-label") {
      parsed.clickLabel = values[++index];
    } else if (value === "--run-action") {
      parsed.runAction = values[++index];
    } else if (value === "--page-delay-ms") {
      parsed.pageDelayMs = Number(values[++index]);
    } else if (value === "--action-delay-ms") {
      parsed.actionDelayMs = Number(values[++index]);
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
  console.log(`Usage: node scripts/validate-openwebui-template.js [--inspect-only] [--run-action "Share"]`);
}
