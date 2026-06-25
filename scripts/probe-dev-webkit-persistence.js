#!/usr/bin/env node

const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");

const portFilePath = path.join(os.tmpdir(), "quiper-template-validation-port.json");
const key = "__quiper_validation_storage_probe__";
const options = parseArgs(process.argv.slice(2));
const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};

main().catch((error) => {
  console.error(`WebKit persistence probe failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  const status = await request("GET", "/status");
  if (!status.ok) {
    throw new Error(status.error || "status endpoint returned an error");
  }

  if (!status.result?.isDev || status.result?.bundleIdentifier !== "app.sassanh.quiper.QuiperDev") {
    throw new Error("Refusing to run outside QuiperDev");
  }

  const result = await runProbe();
  console.log(JSON.stringify({
    mode: options.mode,
    service: status.result.currentService || null,
    serviceID: status.result.currentServiceID || null,
    persistentStore: status.result.websiteDataStorePersistent,
    pageURL: redactURL(status.result.pageURL),
    result,
  }, null, 2));
}

async function runProbe() {
  const response = await request("POST", "/action/run", {
    action: "History",
    script: probeScript(options.mode),
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

function probeScript(mode) {
  return `
    (() => {
      const key = ${JSON.stringify(key)};
      const mode = ${JSON.stringify(mode)};
      const cookieName = key.replace(/[^a-zA-Z0-9_]/g, "_");
      const getCookie = () => document.cookie
        .split(";")
        .map((item) => item.trim())
        .find((item) => item.startsWith(cookieName + "=")) || null;
      const value = Date.now().toString(36) + "-" + Math.random().toString(36).slice(2);

      if (mode === "set") {
        localStorage.setItem(key, value);
        document.cookie = cookieName + "=" + encodeURIComponent(value) + "; path=/; max-age=86400; SameSite=Lax";
      } else if (mode === "clear") {
        localStorage.removeItem(key);
        document.cookie = cookieName + "=; path=/; max-age=0; SameSite=Lax";
      }

      throw JSON.stringify({
        href: location.origin + location.pathname,
        localStorageValue: localStorage.getItem(key),
        cookieValue: getCookie(),
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
    req.setTimeout(options.timeoutMs, () => {
      req.destroy(new Error(`Request timed out after ${options.timeoutMs}ms: ${method} ${pathname}`));
    });
    req.end(requestBody);
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
    mode: "read",
    timeoutMs: 5000,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--mode") {
      parsed.mode = args[index + 1];
      index += 1;
    } else if (arg === "--timeout-ms") {
      parsed.timeoutMs = Number(args[index + 1]);
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!["set", "read", "clear"].includes(parsed.mode)) {
    throw new Error("--mode must be set, read, or clear");
  }
  if (!Number.isFinite(parsed.timeoutMs) || parsed.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive number");
  }

  return parsed;
}
