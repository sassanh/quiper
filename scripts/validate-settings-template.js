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

const requested = new Set(process.argv.slice(2).map((name) => name.toLowerCase()));
const services = parseServices(source).filter(
  (service) => requested.size === 0 || requested.has(service.name.toLowerCase())
);
if (services.length === 0) {
  throw new Error("No default service templates match the requested engine names");
}

const bridge = readBridge();
const base = {
  hostname: bridge.host || "127.0.0.1",
  port: bridge.port,
};

main().catch((error) => {
  console.error(`Settings validation failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  let failures = 0;
  for (const service of services) {
    const settingsScript = service.actions.find((action) => action.name === "Settings");
    if (!settingsScript) {
      console.log(`- ${service.name}: SKIPPED (no Settings template)`);
      continue;
    }

    try {
      const selected = await request("POST", "/engine/select", { name: service.name });
      if (!selected.ok) {
        throw new Error(selected.error || "engine select failed");
      }
      await request("POST", "/session/start-current", {});
      await delay(1500);

      const response = await request("POST", "/action/run", {
        action: "Settings",
        script: liveScript(settingsScript),
      });
      if (!response.ok) {
        throw new Error(response.error || "unknown error");
      }
      console.log(`- ${service.name}: PASS (settings opened)`);
    } catch (error) {
      failures += 1;
      console.log(`- ${service.name}: FAIL (${error.message})`);
    }
  }

  if (failures > 0) {
    console.error(`\nSettings validation failed for ${failures} engine(s)`);
    process.exit(1);
  }
  console.log("\nSettings validation passed for all requested engines");
}

function liveScript(action) {
  return action.sourceLines
    .map((line) => (/^\s*\\\(Settings\.defaultActionScriptHelpers\)\s*$/.test(line) ? helperSource : line))
    .join("\n");
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
    req.setTimeout(12000, () => {
      req.destroy(new Error(`Request timed out: ${method} ${pathname}`));
    });
    req.end(requestBody);
  });
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
