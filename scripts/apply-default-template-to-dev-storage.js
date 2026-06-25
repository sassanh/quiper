#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");
const { parseHelper, parseServices } = require("./audit-default-templates");

const repoRoot = path.resolve(__dirname, "..");
const settingsSourcePath = path.join(repoRoot, "Quiper", "Settings.swift");

const options = parseArgs(process.argv.slice(2));
const appSupportPath = path.join(os.homedir(), "Library", "Application Support", "app.sassanh.quiper.QuiperDev");
const settingsPath = path.join(appSupportPath, "settings.json");
const source = fs.readFileSync(settingsSourcePath, "utf8");
const helperSource = parseHelper(source);
const defaultServices = parseServices(source);
const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));

const service = findByName(settings.services || [], options.service, "service");
const template = findByName(defaultServices, service.name, "default service template");
const actions = options.actions.length > 0
  ? options.actions
  : (template.actions || []).map((action) => action.name);

let appliedFocusSelector = false;
if (options.focusSelector) {
  service.focus_selector = template.focusSelector;
  appliedFocusSelector = true;
}

const applied = [];
for (const actionName of actions) {
  const action = findByName(settings.customActions || [], actionName, "custom action");
  const templateAction = findByName(template.actions || [], action.name, `default action for ${template.name}`);
  const script = liveScript(templateAction);
  const dir = path.join(appSupportPath, "ActionScripts", service.id);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${action.id}.js`), script, "utf8");
  applied.push(action.name);
}

const removed = [];
for (const actionName of options.removeActions) {
  const action = findByName(settings.customActions || [], actionName, "custom action");
  const dir = path.join(appSupportPath, "ActionScripts", service.id);
  const scriptPath = path.join(dir, `${action.id}.js`);
  if (fs.existsSync(scriptPath)) {
    fs.unlinkSync(scriptPath);
  }
  if (service.actionScripts && Object.prototype.hasOwnProperty.call(service.actionScripts, action.id)) {
    delete service.actionScripts[action.id];
  }
  removed.push(action.name);
}

if (appliedFocusSelector || removed.length > 0) {
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2), "utf8");
}

console.log(`Applied ${applied.length} default script(s) to QuiperDev storage for ${service.name}:`);
for (const actionName of applied) {
  console.log(`- ${actionName}`);
}
if (appliedFocusSelector) {
  console.log(`Applied default focus selector to QuiperDev storage for ${service.name}.`);
}
if (removed.length > 0) {
  console.log(`Removed ${removed.length} script(s) from QuiperDev storage for ${service.name}:`);
  for (const actionName of removed) {
    console.log(`- ${actionName}`);
  }
}

function liveScript(action) {
  return action.sourceLines
    .map((line) => (/^\s*\\\(Settings\.defaultActionScriptHelpers\)\s*$/.test(line) ? helperSource : line))
    .join("\n")
    .trim();
}

function findByName(items, name, label) {
  const normalized = normalizeName(name);
  const item = items.find((candidate) => normalizeName(candidate.name) === normalized);
  if (!item) {
    throw new Error(`${label} not found: ${name}`);
  }
  return item;
}

function normalizeName(value) {
  return String(value || "").trim().toLowerCase();
}

function parseArgs(values) {
  const parsed = { service: null, actions: [], removeActions: [], focusSelector: false };
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--service") {
      parsed.service = values[++index];
    } else if (value === "--action") {
      parsed.actions.push(values[++index]);
    } else if (value === "--focus-selector") {
      parsed.focusSelector = true;
    } else if (value === "--remove-action") {
      parsed.removeActions.push(values[++index]);
    } else if (value === "--help") {
      printHelp();
      process.exit(0);
    } else {
      throw new Error(`Unknown argument ${value}`);
    }
  }
  if (!parsed.service) {
    throw new Error("--service is required");
  }
  return parsed;
}

function printHelp() {
  console.log(`Usage: node scripts/apply-default-template-to-dev-storage.js --service Gemini --action "New Session"`);
  console.log("Applies repo default action scripts to QuiperDev ActionScripts storage without restarting the app.");
  console.log(`       node scripts/apply-default-template-to-dev-storage.js --service Google --focus-selector`);
  console.log(`       node scripts/apply-default-template-to-dev-storage.js --service Z.ai --remove-action "New Temporary Session"`);
}
