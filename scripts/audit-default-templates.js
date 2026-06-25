#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const settingsPath = path.join(repoRoot, "Quiper", "Settings.swift");
const source = fs.readFileSync(settingsPath, "utf8");

const actionNames = {
  newSessionActionID: "New Session",
  newTemporarySessionActionID: "New Temporary Session",
  shareActionID: "Share",
  historyActionID: "History",
};

function parseServices(text) {
  const lines = text.split(/\r?\n/);
  const services = [];
  let current = null;
  let activeScript = null;

  for (const line of lines) {
    const serviceStart = line.match(/^\s*Service\(\s*$/);
    if (serviceStart && !activeScript) {
      current = { name: null, url: null, focusSelector: null, actions: [] };
      services.push(current);
      continue;
    }

    if (!current) { continue; }

    if (activeScript) {
      if (/^\s*""",?\s*$/.test(line)) {
        current.actions.push(activeScript);
        activeScript = null;
      } else {
        activeScript.sourceLines.push(line);
      }
      continue;
    }

    const name = line.match(/^\s*name:\s*"([^"]+)"/);
    if (name) {
      current.name = name[1];
      continue;
    }

    const url = line.match(/^\s*url:\s*"([^"]+)"/);
    if (url) {
      current.url = url[1];
      continue;
    }

    const focusSelector = line.match(/^\s*focus_selector:\s*"([^"]*)"/);
    if (focusSelector) {
      current.focusSelector = focusSelector[1];
      continue;
    }

    const action = line.match(/Settings\.(\w+ActionID):\s*"""/);
    if (action) {
      activeScript = {
        id: action[1],
        name: actionNames[action[1]] || action[1],
        sourceLines: [],
      };
    }
  }

  return services.filter((service) => service.name);
}

function parseHelper(text) {
  const match = text.match(/defaultActionScriptHelpers\s*=\s*"""\n([\s\S]*?)\n\s*"""/);
  return match ? match[1] : "";
}

function scriptForSyntax(script) {
  return script.sourceLines
    .filter((line) => !/^\s*\\\(.*\)\s*;?\s*$/.test(line))
    .join("\n");
}

function validateScript(service, script) {
  const js = scriptForSyntax(script);
  try {
    new Function(`return (async () => {\n${js}\n});`);
    return null;
  } catch (error) {
    return `${service.name} / ${script.name}: ${error.message}`;
  }
}

function validateJavaScript(label, source) {
  try {
    new Function(`return (async () => {\n${source}\n});`);
    return null;
  } catch (error) {
    return `${label}: ${error.message}`;
  }
}

async function checkEndpoint(service) {
  if (!service.url || /^https?:\/\/(localhost|127\.0\.0\.1)(:|\/|$)/.test(service.url)) {
    return "skipped local";
  }

  try {
    const response = await fetch(service.url, {
      method: "HEAD",
      redirect: "follow",
      headers: {
        "User-Agent": "Quiper default-template audit",
      },
    });
    return `${response.status} ${response.statusText}`.trim();
  } catch (error) {
    return `error: ${error.message}`;
  }
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const services = parseServices(source);
  const helper = parseHelper(source);
  const errors = [
    validateJavaScript("defaultActionScriptHelpers", helper),
    ...services.flatMap((service) =>
    service.actions.map((script) => validateScript(service, script)).filter(Boolean)
    ),
  ].filter(Boolean);

  console.log(`Default service templates: ${services.length}`);
  for (const service of services) {
    const actionList = service.actions.map((action) => action.name).join(", ") || "none";
    console.log(`- ${service.name}`);
    console.log(`  URL: ${service.url || "(missing)"}`);
    console.log(`  Focus: ${service.focusSelector || "(missing)"}`);
    console.log(`  Actions: ${actionList}`);
  }

  if (errors.length > 0) {
    console.error("\nJavaScript syntax errors:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exitCode = 1;
  } else {
    console.log("\nJavaScript syntax: ok");
  }

  if (args.has("--network")) {
    console.log("\nEndpoint checks:");
    for (const service of services) {
      console.log(`- ${service.name}: ${await checkEndpoint(service)}`);
    }
  }
}

module.exports = {
  actionNames,
  checkEndpoint,
  parseHelper,
  parseServices,
  scriptForSyntax,
  validateJavaScript,
  validateScript,
};

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
