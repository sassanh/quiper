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
const service = parseServices(source).find((candidate) => candidate.name === "X");
if (!service) {
  throw new Error("X default service template not found");
}

const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};
const actions = Object.fromEntries(service.actions.map((action) => [action.name, liveScript(action)]));

main().catch((error) => {
  console.error(`X validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  const results = [];

  await request("POST", "/engine/select", { name: "X" });

  if (options.inspectOnly) {
    const controls = await runJSONProbe(controlStateScript());
    const privateDiagnostic = await runJSONProbe(privateDiagnosticScript());
    console.log(JSON.stringify({ controls: controls.items, privateDiagnostic }, null, 2));
    return;
  }

  if (options.privateOnly) {
    const privateDiagnostic = await runJSONProbe(privateDiagnosticScript());
    console.log(JSON.stringify(privateDiagnostic, null, 2));
    return;
  }

  if (options.clickPrivateOnly) {
    const before = await runJSONProbe(privateStateScript());
    const click = await runJSONProbe(clickPrivateButtonScript());
    await delay(options.actionDelayMs);
    const after = await runJSONProbe(privateStateScript());
    console.log(JSON.stringify({ before, click, after }, null, 2));
    return;
  }

  if (options.historyOnly) {
    const before = await runJSONProbe(historyStateScript());
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterOne = await runJSONProbe(historyStateScript());
    await runDefaultAction("History");
    await delay(options.actionDelayMs);
    const afterTwo = await runJSONProbe(historyStateScript());
    console.log(JSON.stringify({ before, afterOne, afterTwo }, null, 2));
    return;
  }

  if (options.historyInspectOnly) {
    const state = await runJSONProbe(historyDiagnosticScript());
    console.log(JSON.stringify(state, null, 2));
    return;
  }

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
  if (options.verbose) {
    console.log(JSON.stringify({ controls: controls.items }, null, 2));
  }

  logStep("run History twice");
  const historyBefore = await runJSONProbe(historyStateScript());
  await runDefaultAction("History");
  await delay(options.actionDelayMs);
  const historyAfterOne = await runJSONProbe(historyStateScript());
  await runDefaultAction("History");
  await delay(options.actionDelayMs);
  const historyAfterTwo = await runJSONProbe(historyStateScript());
  results.push(`history: ${historyBefore.historyOpen} -> ${historyAfterOne.historyOpen} -> ${historyAfterTwo.historyOpen}`);

  logStep("run New Temporary Session");
  await runDefaultAction("New Temporary Session");
  await delay(options.actionDelayMs);
  const temporary = await runJSONProbe(privateStateScript());
  results.push(`private after temporary: ${temporary.privateActive}`);

  logStep("run New Session");
  await runDefaultAction("New Session");
  await delay(options.actionDelayMs);
  const normal = await runJSONProbe(privateStateScript());
  results.push(`private after normal: ${normal.privateActive}`);

  console.log("X validation completed");
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
  console.log(`X validation: ${message}`);
}

function controlStateScript() {
  return String.raw`
    const patterns = [/new/i, /private/i, /temporary/i, /share/i, /history/i, /chat/i, /sidebar/i, /menu/i, /grok/i];
    function visible(el) {
      const style = getComputedStyle(el);
      const rect = el.getBoundingClientRect();
      return style.display !== "none" && style.visibility !== "hidden" && rect.width > 0 && rect.height > 0;
    }
    function label(el) {
      return [
        el.getAttribute("aria-label"),
        el.getAttribute("title"),
        el.getAttribute("data-testid"),
        el.getAttribute("href"),
        el.innerText,
        el.textContent
      ].filter(Boolean).join(" ").replace(/\s+/g, " ").trim().slice(0, 140);
    }
    const items = [...document.querySelectorAll("button,a,[role='button'],[role='menuitem'],textarea")]
      .filter(visible)
      .filter((el) => !(el.matches("a[href*='conversation=']") || el.closest("a[href*='conversation=']")))
      .map((el) => ({
        tag: el.tagName.toLowerCase(),
        role: el.getAttribute("role"),
        label: label(el).replace(/conversation=[^&\s]+/g, "conversation=:id"),
        ariaPressed: el.getAttribute("aria-pressed"),
        ariaSelected: el.getAttribute("aria-selected"),
        ariaChecked: el.getAttribute("aria-checked"),
        disabled: el.disabled || el.getAttribute("aria-disabled"),
        rect: [
          Math.round(el.getBoundingClientRect().x),
          Math.round(el.getBoundingClientRect().y),
          Math.round(el.getBoundingClientRect().width),
          Math.round(el.getBoundingClientRect().height)
        ]
      }))
      .filter((item) => patterns.some((pattern) => pattern.test(item.label)))
      .slice(0, 80);
    throw new Error(JSON.stringify({ url: location.href.replace(/conversation=[^&]+/g, "conversation=:id"), title: document.title, items }));
  `;
}

function privateStateScript() {
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
    const button = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .find((el) => {
        const value = text(el);
        const rect = el.getBoundingClientRect();
        return /private/i.test(value) && rect.y < 140 && rect.width >= 40 && rect.height >= 20;
      });
    const label = button ? text(button) : "";
    const statusVisible = [...document.querySelectorAll("h1,h2,h3,p,span,div")]
      .filter(visible)
      .some((el) => /This chat won.t appear in your history/i.test(text(el)));
    const privateActive = Boolean(statusVisible || (
      button && (
        button.getAttribute("aria-pressed") === "true" ||
        button.getAttribute("aria-selected") === "true" ||
        button.getAttribute("aria-checked") === "true" ||
        /active|selected/i.test(button.className || "") ||
        /disable private|turn off private|private mode/i.test(label)
      )
    ));
    throw new Error(JSON.stringify({
      privateActive,
      label,
      statusVisible,
      ariaPressed: button?.getAttribute("aria-pressed") || null,
      ariaSelected: button?.getAttribute("aria-selected") || null,
      ariaChecked: button?.getAttribute("aria-checked") || null,
      url: location.href.replace(/conversation=[^&]+/g, "conversation=:id")
    }));
  `;
}

function clickPrivateButtonScript() {
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
    const buttons = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .filter((el) => text(el) === "Private Private Private" || text(el) === "Private");
    const button = buttons.find((el) => {
      const rect = el.getBoundingClientRect();
      return rect.y < 120 && rect.width >= 50 && rect.height >= 20;
    }) || buttons[0];
    if (!button) { throw new Error(JSON.stringify({ clicked: false, reason: "private button not found" })); }
    button.scrollIntoView({ block: "center", inline: "center" });
    button.click();
    throw new Error(JSON.stringify({
      clicked: true,
      label: text(button).slice(0, 80),
      rect: [
        Math.round(button.getBoundingClientRect().x),
        Math.round(button.getBoundingClientRect().y),
        Math.round(button.getBoundingClientRect().width),
        Math.round(button.getBoundingClientRect().height)
      ]
    }));
  `;
}

function privateDiagnosticScript() {
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
    function ownText(el) {
      return [...el.childNodes]
        .filter((node) => node.nodeType === Node.TEXT_NODE)
        .map((node) => node.textContent)
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
    }
    function clippedClass(value) {
      return String(value || "")
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 12)
        .join(" ");
    }
    const candidates = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .filter((el) => /private/i.test(text(el)))
      .slice(0, 8)
      .map((el) => {
        const style = getComputedStyle(el);
        const rect = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          role: el.getAttribute("role"),
          label: text(el).slice(0, 80),
          ownText: ownText(el).slice(0, 80),
          className: clippedClass(el.className),
          parentClassName: clippedClass(el.parentElement?.className),
          ariaPressed: el.getAttribute("aria-pressed"),
          ariaSelected: el.getAttribute("aria-selected"),
          ariaChecked: el.getAttribute("aria-checked"),
          ariaCurrent: el.getAttribute("aria-current"),
          disabled: el.disabled || el.getAttribute("aria-disabled"),
          styles: {
            backgroundColor: style.backgroundColor,
            borderColor: style.borderColor,
            boxShadow: style.boxShadow === "none" ? "none" : "present",
            color: style.color,
            fontWeight: style.fontWeight,
            outlineColor: style.outlineColor
          },
          rect: [
            Math.round(rect.x),
            Math.round(rect.y),
            Math.round(rect.width),
            Math.round(rect.height)
          ]
        };
      });
    const privateStatusText = [...document.querySelectorAll("h1,h2,h3,p,span,div")]
      .filter(visible)
      .map((el) => ownText(el) || text(el))
      .filter((value) => /This chat won.t appear in your history/i.test(value))
      .map((value) => value.slice(0, 100))
      .slice(0, 3);
    throw new Error(JSON.stringify({
      url: location.href.replace(/conversation=[^&]+/g, "conversation=:id"),
      candidates,
      privateStatusText
    }));
  `;
}

function historyStateScript() {
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
    const historyButton = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .find((el) => {
        const rect = el.getBoundingClientRect();
        return /chat history|history/i.test(text(el)) && rect.y < 140 && rect.width >= 20 && rect.height >= 20;
      });
    const tablist = [...document.querySelectorAll("[role='tablist']")]
      .filter(visible)
      .find((el) => {
        const value = text(el);
        const rect = el.getBoundingClientRect();
        return /chats/i.test(value) && /bookmarks|images/i.test(value) && rect.width > 180 && rect.height > 30;
      });
    const searchInput = [...document.querySelectorAll("input,textarea,[contenteditable='true']")]
      .filter(visible)
      .find((el) => /search/i.test(text(el) || el.getAttribute("placeholder") || ""));
    const closeButton = [...document.querySelectorAll("button,[role='button']")]
      .filter(visible)
      .find((el) => {
        const rect = el.getBoundingClientRect();
        return /^(close|close history)$/i.test(text(el)) &&
          rect.x > 70 &&
          rect.y < 80 &&
          rect.width >= 20 &&
          rect.height >= 20;
      });
    const historyOpen = Boolean(tablist || searchInput || closeButton);
    const tabRect = tablist ? tablist.getBoundingClientRect() : null;
    const searchRect = searchInput ? searchInput.getBoundingClientRect() : null;
    const closeRect = closeButton ? closeButton.getBoundingClientRect() : null;
    throw new Error(JSON.stringify({
      historyOpen,
      buttonLabel: historyButton ? text(historyButton) : "",
      tablistRect: tabRect ? [
        Math.round(tabRect.x),
        Math.round(tabRect.y),
        Math.round(tabRect.width),
        Math.round(tabRect.height)
      ] : null,
      searchRect: searchRect ? [
        Math.round(searchRect.x),
        Math.round(searchRect.y),
        Math.round(searchRect.width),
        Math.round(searchRect.height)
      ] : null,
      closeRect: closeRect ? [
        Math.round(closeRect.x),
        Math.round(closeRect.y),
        Math.round(closeRect.width),
        Math.round(closeRect.height)
      ] : null,
      url: location.href.replace(/conversation=[^&]+/g, "conversation=:id")
    }));
  `;
}

function historyDiagnosticScript() {
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
    const controls = [...document.querySelectorAll("button,[role='button'],a,input,textarea")]
      .filter(visible)
      .map((el) => {
        const rect = el.getBoundingClientRect();
        return { el, rect };
      })
      .filter(({ rect }) => rect.x > window.innerWidth * 0.45 || rect.y < 170)
      .filter(({ el }) => !(el.matches("a[href*='conversation=']") || el.closest("a[href*='conversation=']")))
      .filter(({ el, rect }) => el.tagName.toLowerCase() !== "a" || rect.y < 170)
      .map(({ el, rect }) => ({
        tag: el.tagName.toLowerCase(),
        role: el.getAttribute("role"),
        label: text(el).slice(0, 100).replace(/conversation=[^&\s]+/g, "conversation=:id"),
        ariaLabel: el.getAttribute("aria-label"),
        dataTestId: el.getAttribute("data-testid"),
        type: el.getAttribute("type"),
        rect: [
          Math.round(rect.x),
          Math.round(rect.y),
          Math.round(rect.width),
          Math.round(rect.height)
        ]
      }))
      .slice(0, 80);
    throw new Error(JSON.stringify({
      url: location.href.replace(/conversation=[^&]+/g, "conversation=:id"),
      viewport: [window.innerWidth, window.innerHeight],
      controls
    }));
  `;
}

function parseArgs(values) {
  const parsed = {
    actionDelayMs: 1800,
    clickPrivateOnly: false,
    historyOnly: false,
    historyInspectOnly: false,
    inspectOnly: false,
    privateOnly: false,
    readyPollMs: 250,
    readyTimeoutMs: 12000,
    requestTimeoutMs: 12000,
    verbose: false,
    viewportDelayMs: 600,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--action-delay-ms") {
      parsed.actionDelayMs = Number(values[++index]);
    } else if (value === "--click-private-only") {
      parsed.clickPrivateOnly = true;
    } else if (value === "--history-only") {
      parsed.historyOnly = true;
    } else if (value === "--history-inspect-only") {
      parsed.historyInspectOnly = true;
    } else if (value === "--inspect-only") {
      parsed.inspectOnly = true;
    } else if (value === "--private-only") {
      parsed.privateOnly = true;
    } else if (value === "--ready-timeout-ms") {
      parsed.readyTimeoutMs = Number(values[++index]);
    } else if (value === "--request-timeout-ms") {
      parsed.requestTimeoutMs = Number(values[++index]);
    } else if (value === "--viewport-delay-ms") {
      parsed.viewportDelayMs = Number(values[++index]);
    } else if (value === "--verbose") {
      parsed.verbose = true;
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
  console.log("Usage: node scripts/validate-x-template.js");
  console.log("Runs bounded live checks for X/Grok default focus/action templates through the dev validation bridge.");
}
