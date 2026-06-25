#!/usr/bin/env node

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const portFilePath = path.join(os.tmpdir(), "quiper-template-validation-port.json");
const options = parseArgs(process.argv.slice(2));

main().catch((error) => {
  console.error(`Template validation status query failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  const bridge = readBridge();
  const response = await request(bridge.host || "127.0.0.1", bridge.port, "GET", "/status");
  if (!response.ok) {
    throw new Error(response.error || "status endpoint returned an error");
  }

  const status = redactStatus(response.result || {});
  if (options.json) {
    console.log(JSON.stringify(status, null, 2));
    return;
  }

  console.log("Template validation status");
  console.log(`- Ready: ${status.ready}`);
  console.log(`- Bundle: ${status.bundleIdentifier}`);
  console.log(`- Dev build: ${status.isDev}`);
  console.log(`- Running tests: ${status.isRunningTests}`);
  console.log(`- Service: ${status.currentService || "(none)"}`);
  console.log(`- Service ID: ${status.currentServiceID || "(none)"}`);
  console.log(`- Encrypted: ${status.currentServiceEncrypted}`);
  console.log(`- Persistent WebKit store: ${status.websiteDataStorePersistent}`);
  console.log(`- Page URL: ${status.pageURL || "(none)"}`);
  console.log(`- Loading: ${status.isLoading}`);
  if (status.window) {
    console.log(`- Window: ${status.window.width}x${status.window.height}, visible=${status.window.visible}`);
  }
}

function request(hostname, port, method, pathname) {
  return new Promise((resolve, reject) => {
    const req = http.request({ hostname, port, method, path: pathname }, (res) => {
      let body = "";
      res.on("data", (chunk) => {
        body += chunk;
      });
      res.on("end", () => {
        try {
          resolve(JSON.parse(body));
        } catch (error) {
          reject(error);
        }
      });
    });

    req.on("error", reject);
    req.setTimeout(options.timeoutMs, () => {
      req.destroy(new Error(`Request timed out after ${options.timeoutMs}ms`));
    });
    req.end();
  });
}

function readBridge() {
  const raw = fs.readFileSync(portFilePath, "utf8");
  const bridge = JSON.parse(raw);
  if (!bridge.port) {
    throw new Error(`Missing port in ${portFilePath}`);
  }
  return bridge;
}

function redactStatus(status) {
  return {
    ...status,
    currentServiceURL: redactURL(status.currentServiceURL),
    pageURL: redactURL(status.pageURL),
    pageTitle: status.pageTitle ? "(redacted)" : status.pageTitle,
  };
}

function redactURL(value) {
  if (!value || typeof value !== "string") {
    return value;
  }

  try {
    const url = new URL(value);
    if (url.protocol === "http:" && (url.hostname === "localhost" || url.hostname === "127.0.0.1")) {
      return `${url.origin}${url.pathname}`;
    }
    return `${url.origin}/...`;
  } catch {
    return "(redacted)";
  }
}

function parseArgs(args) {
  const parsed = {
    json: false,
    timeoutMs: 5000,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--json") {
      parsed.json = true;
    } else if (arg === "--timeout-ms") {
      parsed.timeoutMs = Number(args[index + 1]);
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!Number.isFinite(parsed.timeoutMs) || parsed.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive number");
  }

  return parsed;
}
