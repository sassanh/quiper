#!/usr/bin/env node

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const readline = require("readline/promises");
const { stdin: input, stdout: output } = require("process");
const { parseHelper, parseServices } = require("./audit-default-templates");

const repoRoot = path.resolve(__dirname, "..");
const settingsPath = path.join(repoRoot, "Quiper", "Settings.swift");
const portFilePath = path.join(os.tmpdir(), "quiper-template-validation-port.json");
const source = fs.readFileSync(settingsPath, "utf8");
const helperSource = parseHelper(source);

const args = process.argv.slice(2);
const options = parseArgs(args);
const services = parseServices(source).filter((service) => {
  if (options.engine.length === 0) {
    return true;
  }
  return options.engine.some((name) => service.name.toLowerCase() === name.toLowerCase());
});

async function main() {
  if (services.length === 0) {
    throw new Error("No matching default services found");
  }

  const bridge = readBridge();
  const baseURL = `http://${bridge.host || "127.0.0.1"}:${bridge.port}`;
  const report = [];

  console.log(`Template validation bridge: ${baseURL}`);
  console.log(`Engines: ${services.map((service) => service.name).join(", ")}`);

  for (const service of services) {
    const result = await validateService(baseURL, service);
    report.push(result);
    printServiceResult(result);

    if (result.needsHuman && options.wait) {
      await waitForHuman(service.name);
    }
  }

  const failures = report.filter((result) => result.status === "failed");
  const blocked = report.filter((result) => result.status === "needs-human");

  console.log("\nSummary");
  console.log(`- Passed: ${report.filter((result) => result.status === "passed").length}`);
  console.log(`- Needs human: ${blocked.length}`);
  console.log(`- Failed: ${failures.length}`);

  if (blocked.length > 0) {
    console.log("\nNeeds human:");
    for (const result of blocked) {
      console.log(`- ${result.name}: ${result.reason}`);
    }
  }

  if (failures.length > 0) {
    console.log("\nFailures:");
    for (const result of failures) {
      console.log(`- ${result.name}: ${result.reason}`);
    }
    process.exitCode = 1;
  }
}

async function validateService(baseURL, service) {
  const checks = [];
  const actionResults = [];

  try {
    await request(baseURL, "POST", "/engine/select", { name: service.name });
    await request(baseURL, "POST", "/session/start-current", { reload: options.reload });
    await waitForBridgeReady(baseURL);
    await delay(options.pageDelayMs);

    for (const viewport of ["small", "large"]) {
      await request(baseURL, "POST", "/viewport", { size: viewport });
      await waitForBridgeReady(baseURL);
      await delay(options.viewportDelayMs);
      const focus = await waitForFocusSelector(baseURL, service.focusSelector);
      checks.push({ viewport, focus });
    }

    const focusFailure = checks.find((check) => !check.focus.result?.visibleCount);
    if (focusFailure) {
      const page = await request(baseURL, "POST", "/dom/query", { probe: "pageFacts" });
      return {
        name: service.name,
        status: "needs-human",
        needsHuman: true,
        reason: `focus selector not visible at ${focusFailure.viewport}; page title: ${page.result?.title || "(unknown)"}`,
        checks,
        actionResults,
      };
    }

    for (const action of service.actions) {
      const actionResult = await request(baseURL, "POST", "/action/run", {
        action: action.name,
        script: liveScript(action),
      });
      actionResults.push({ action: action.name, ok: true, result: actionResult.result });
      await delay(options.actionDelayMs);
      await validateActionPostcondition(baseURL, service, action.name);
      const extra = await runActionTransitionChecks(baseURL, service, action.name);
      actionResults.push(...extra);
    }

    return {
      name: service.name,
      status: "passed",
      reason: "selectors and actions completed",
      checks,
      actionResults,
    };
  } catch (error) {
    const status = error.status === 422 || error.status === 404 || error.status === 409 ? "needs-human" : "failed";
    return {
      name: service.name,
      status,
      needsHuman: status === "needs-human",
      reason: error.message,
      checks,
      actionResults,
    };
  }
}

async function waitForBridgeReady(baseURL) {
  const startedAt = Date.now();
  let lastStatus = null;
  while (Date.now() - startedAt <= options.readyTimeoutMs) {
    lastStatus = await request(baseURL, "GET", "/status");
    if (lastStatus.result?.ready && !lastStatus.result?.isLoading) {
      return lastStatus;
    }
    await delay(options.readyPollMs);
  }
  return lastStatus;
}

async function waitForFocusSelector(baseURL, selector) {
  const startedAt = Date.now();
  let lastFocus = null;
  while (Date.now() - startedAt <= options.focusTimeoutMs) {
    lastFocus = await request(baseURL, "POST", "/dom/query", {
      probe: "focusSelector",
      argument: selector,
      focus: true,
    });
    if (lastFocus.result?.visibleCount) {
      return lastFocus;
    }
    await delay(options.focusPollMs);
  }
  return lastFocus;
}

async function runActionTransitionChecks(baseURL, service, completedActionName) {
  if (service.name !== "Gemini" || completedActionName !== "New Temporary Session") {
    return [];
  }

  const newSession = service.actions.find((action) => action.name === "New Session");
  if (!newSession) {
    return [];
  }

  const actionResult = await request(baseURL, "POST", "/action/run", {
    action: newSession.name,
    script: liveScript(newSession),
  });
  await delay(options.actionDelayMs);
  await validateActionPostcondition(baseURL, service, "New Session");
  return [{ action: "New Session after Temporary", ok: true, result: actionResult.result }];
}

async function validateActionPostcondition(baseURL, service, actionName) {
  if (service.name !== "Gemini") {
    return;
  }

  const state = await geminiState(baseURL);

  if (actionName === "New Temporary Session") {
    if (!state.temporaryActive) {
      throw new Error("Gemini postcondition failed: temporary mode is not active after New Temporary Session");
    }
  } else if (actionName === "New Session") {
    if (state.temporaryActive) {
      throw new Error("Gemini postcondition failed: temporary mode is still active after New Session");
    }
  } else if (actionName === "Share") {
    if (!state.dialogVisible && state.shareConversationVisible) {
      throw new Error("Gemini postcondition failed: share conversation was not selected");
    }
  }
}

async function geminiState(baseURL) {
  const response = await request(baseURL, "POST", "/dom/query", { probe: "geminiState" });
  return response.result || {};
}

function liveScript(action) {
  return action.sourceLines
    .map((line) => (/^\s*\\\(Settings\.defaultActionScriptHelpers\)\s*$/.test(line) ? helperSource : line))
    .join("\n");
}

async function request(baseURL, method, pathname, body = undefined) {
  const url = new URL(pathname, baseURL);
  const requestBody = body ? JSON.stringify(body) : "";

  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: url.hostname,
      port: Number(url.port),
      path: `${url.pathname}${url.search}`,
      method,
      headers: requestBody
        ? {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(requestBody),
          }
        : undefined,
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        let payload = {};
        try {
          payload = text ? JSON.parse(text) : {};
        } catch {
          payload = {};
        }
        if ((response.statusCode || 500) >= 400 || payload.ok === false) {
          const error = new Error(payload.error || `${method} ${pathname} failed with ${response.statusCode}`);
          error.status = response.statusCode;
          error.payload = payload;
          reject(error);
          return;
        }
        resolve(payload);
      });
    });
    req.on("error", reject);
    if (requestBody) {
      req.write(requestBody);
    }
    req.end();
  });
}

function readBridge() {
  if (options.host && options.port) {
    return { host: options.host, port: options.port };
  }
  if (process.env.QUIPER_TEMPLATE_VALIDATION_PORT) {
    return {
      host: process.env.QUIPER_TEMPLATE_VALIDATION_HOST || "127.0.0.1",
      port: Number(process.env.QUIPER_TEMPLATE_VALIDATION_PORT),
    };
  }
  if (!fs.existsSync(portFilePath)) {
    throw new Error(`Bridge port file not found at ${portFilePath}. Launch QuiperDev with --template-validation-server first.`);
  }
  return JSON.parse(fs.readFileSync(portFilePath, "utf8"));
}

function printServiceResult(result) {
  const icon = result.status === "passed" ? "ok" : result.status;
  console.log(`\n${result.name}: ${icon}`);
  console.log(`- ${result.reason}`);
  for (const check of result.checks || []) {
    const focus = check.focus.result || {};
    console.log(`- ${check.viewport}: ${focus.visibleCount || 0}/${focus.count || 0} visible for focus selector`);
  }
  for (const action of result.actionResults || []) {
    console.log(`- action ${action.action}: ok`);
  }
}

async function waitForHuman(serviceName) {
  const rl = readline.createInterface({ input, output });
  await rl.question(`Resolve ${serviceName} manually in Quiper, then press Enter to continue...`);
  rl.close();
}

function parseArgs(values) {
  const parsed = {
    actionDelayMs: 400,
    engine: [],
    focusPollMs: 300,
    focusTimeoutMs: 5000,
    host: null,
    pageDelayMs: 2500,
    port: null,
    readyPollMs: 300,
    readyTimeoutMs: 8000,
    reload: false,
    viewportDelayMs: 300,
    wait: false,
  };

  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--engine") {
      parsed.engine.push(values[++index]);
    } else if (value === "--host") {
      parsed.host = values[++index];
    } else if (value === "--port") {
      parsed.port = Number(values[++index]);
    } else if (value === "--reload") {
      parsed.reload = true;
    } else if (value === "--wait") {
      parsed.wait = true;
    } else if (value === "--page-delay-ms") {
      parsed.pageDelayMs = Number(values[++index]);
    } else if (value === "--viewport-delay-ms") {
      parsed.viewportDelayMs = Number(values[++index]);
    } else if (value === "--action-delay-ms") {
      parsed.actionDelayMs = Number(values[++index]);
    } else if (value === "--focus-timeout-ms") {
      parsed.focusTimeoutMs = Number(values[++index]);
    } else if (value === "--focus-poll-ms") {
      parsed.focusPollMs = Number(values[++index]);
    } else if (value === "--ready-timeout-ms") {
      parsed.readyTimeoutMs = Number(values[++index]);
    } else if (value === "--ready-poll-ms") {
      parsed.readyPollMs = Number(values[++index]);
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
  console.log(`Usage: node scripts/validate-default-templates.js [options]

Options:
  --engine NAME          Validate one engine; repeat for multiple engines
  --reload               Reload the active session URL before validation
  --wait                 Pause for manual login/unblocking when needed
  --host HOST --port N   Use an explicit bridge address
  --page-delay-ms N      Delay after selecting an engine (default: 2500)
  --viewport-delay-ms N  Delay after resizing the Quiper window (default: 300)
  --action-delay-ms N    Delay after each action (default: 400)
`);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
