import { basicSetup, EditorView } from "codemirror";
import { completeFromList, snippetCompletion } from "@codemirror/autocomplete";
import { css, cssLanguage } from "@codemirror/lang-css";
import { javascript, javascriptLanguage } from "@codemirror/lang-javascript";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { Compartment, EditorState } from "@codemirror/state";
import { tags } from "@lezer/highlight";

const bridge = window.webkit?.messageHandlers?.quiperCodeEditor;
const languageCompartment = new Compartment();
const readOnlyCompartment = new Compartment();
const themeCompartment = new Compartment();
const languageToolsCompartment = new Compartment();

let applyingHostUpdate = false;
let currentLanguage = "javascript";
let currentReadOnly = false;
let currentTheme = window.__quiperInitialTheme === "light" ? "light" : "dark";

const quiperJavaScriptCompletions = completeFromList([
  snippetCompletion("await waitFor(() => ${condition}, ${1000});", {
    label: "waitFor",
    detail: "Quiper helper",
    type: "function",
    info: "Wait until a page condition becomes truthy or the timeout expires."
  }),
  { label: "document", type: "variable", detail: "Browser DOM" },
  { label: "window", type: "variable", detail: "Browser global" },
  { label: "console", type: "variable", detail: "Browser console" },
  { label: "location", type: "variable", detail: "Page location" },
  { label: "history", type: "variable", detail: "Page history" },
  { label: "fetch", type: "function", detail: "Browser API" },
  { label: "requestAnimationFrame", type: "function", detail: "Browser API" },
  { label: "setTimeout", type: "function", detail: "Browser API" },
  { label: "URL", type: "class", detail: "Browser API" },
  { label: "URLSearchParams", type: "class", detail: "Browser API" }
]);

const selectorCompletions = completeFromList([
  { label: "textarea", type: "type", detail: "Text input element" },
  { label: "input", type: "type", detail: "Input element" },
  { label: "[contenteditable=\"true\"]", type: "property", detail: "Editable element" },
  { label: "[role=\"textbox\"]", type: "property", detail: "ARIA textbox" },
  { label: "[aria-label]", type: "property", detail: "Element with an accessible label" },
  { label: "[placeholder]", type: "property", detail: "Element with placeholder text" },
  { label: ":focus", type: "keyword", detail: "Focused element" },
  { label: ":not()", type: "function", detail: "Negated selector" },
  { label: ":has()", type: "function", detail: "Relational selector" },
  { label: ":first-of-type", type: "keyword", detail: "First element of its type" }
]);

const javascriptSupport = [
  javascript(),
  javascriptLanguage.data.of({ autocomplete: quiperJavaScriptCompletions })
];
const cssSupport = css();
const selectorSupport = [
  css(),
  cssLanguage.data.of({ autocomplete: selectorCompletions })
];

const darkHighlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "#f92672" },
  { tag: [tags.name, tags.deleted, tags.character, tags.macroName], color: "#f8f8f2" },
  { tag: [tags.propertyName, tags.function(tags.variableName)], color: "#66d9ef" },
  { tag: [tags.variableName, tags.labelName], color: "#f8f8f2" },
  { tag: [tags.color, tags.constant(tags.name), tags.standard(tags.name)], color: "#ae81ff" },
  { tag: [tags.definition(tags.name), tags.separator], color: "#fd971f" },
  { tag: [tags.typeName, tags.className, tags.number, tags.changed, tags.annotation, tags.modifier, tags.self, tags.namespace], color: "#ae81ff" },
  { tag: [tags.operator, tags.operatorKeyword, tags.url, tags.escape, tags.regexp, tags.link], color: "#f92672" },
  { tag: [tags.meta, tags.comment], color: "#75715e", fontStyle: "italic" },
  { tag: [tags.string, tags.inserted], color: "#e6db74" },
  { tag: tags.invalid, color: "#f8f8f2", backgroundColor: "#f92672" }
]);

const lightHighlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "#9b1c7c" },
  { tag: [tags.name, tags.deleted, tags.character, tags.macroName], color: "#24292f" },
  { tag: [tags.propertyName, tags.function(tags.variableName)], color: "#0969da" },
  { tag: [tags.variableName, tags.labelName], color: "#24292f" },
  { tag: [tags.color, tags.constant(tags.name), tags.standard(tags.name)], color: "#8250df" },
  { tag: [tags.definition(tags.name), tags.separator], color: "#953800" },
  { tag: [tags.typeName, tags.className, tags.number, tags.changed, tags.annotation, tags.modifier, tags.self, tags.namespace], color: "#8250df" },
  { tag: [tags.operator, tags.operatorKeyword, tags.url, tags.escape, tags.regexp, tags.link], color: "#cf222e" },
  { tag: [tags.meta, tags.comment], color: "#6e7781", fontStyle: "italic" },
  { tag: [tags.string, tags.inserted], color: "#0a3069" },
  { tag: tags.invalid, color: "#ffffff", backgroundColor: "#cf222e" }
]);

const sharedThemeRules = {
  "&": {
    height: "100%",
    fontSize: "13px",
    backgroundColor: "transparent"
  },
  ".cm-scroller": {
    overflow: "auto",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    lineHeight: "1.55"
  },
  ".cm-content": {
    minWidth: "max-content",
    padding: "8px 0"
  },
  ".cm-line": {
    padding: "0 10px"
  },
  ".cm-gutters": {
    borderRight: "1px solid rgba(127, 127, 127, 0.22)",
    backgroundColor: "transparent"
  },
  ".cm-foldGutter": {
    width: "14px"
  },
  ".cm-tooltip": {
    borderRadius: "6px",
    overflow: "hidden"
  },
  ".cm-panels": {
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
  }
};

const darkTheme = [
  EditorView.theme({
    ...sharedThemeRules,
    "&": { ...sharedThemeRules["&"], color: "#f8f8f2" },
    ".cm-gutters": { ...sharedThemeRules[".cm-gutters"], color: "#858585" },
    ".cm-activeLine": { backgroundColor: "rgba(255, 255, 255, 0.045)" },
    ".cm-activeLineGutter": { backgroundColor: "rgba(255, 255, 255, 0.065)" },
    ".cm-selectionBackground": { backgroundColor: "Highlight !important" },
    "&.cm-focused .cm-selectionBackground": { backgroundColor: "Highlight !important" },
    "::selection": { color: "HighlightText", backgroundColor: "Highlight" },
    ".cm-cursor": { borderLeftColor: "#f8f8f2" },
    ".cm-tooltip": { color: "#f8f8f2", backgroundColor: "#252526", border: "1px solid #454545" },
    ".cm-tooltip-autocomplete > ul > li[aria-selected]": { backgroundColor: "#094771" },
    ".cm-panels": { ...sharedThemeRules[".cm-panels"], color: "#f8f8f2", backgroundColor: "#252526" }
  }, { dark: true }),
  syntaxHighlighting(darkHighlightStyle)
];

const lightTheme = [
  EditorView.theme({
    ...sharedThemeRules,
    "&": { ...sharedThemeRules["&"], color: "#24292f" },
    ".cm-gutters": { ...sharedThemeRules[".cm-gutters"], color: "#6e7781" },
    ".cm-activeLine": { backgroundColor: "rgba(9, 105, 218, 0.045)" },
    ".cm-activeLineGutter": { backgroundColor: "rgba(9, 105, 218, 0.08)" },
    ".cm-selectionBackground": { backgroundColor: "Highlight !important" },
    "&.cm-focused .cm-selectionBackground": { backgroundColor: "Highlight !important" },
    "::selection": { color: "HighlightText", backgroundColor: "Highlight" },
    ".cm-cursor": { borderLeftColor: "#24292f" },
    ".cm-tooltip": { color: "#24292f", backgroundColor: "#ffffff", border: "1px solid #d0d7de" },
    ".cm-tooltip-autocomplete > ul > li[aria-selected]": { backgroundColor: "#ddf4ff" },
    ".cm-panels": { ...sharedThemeRules[".cm-panels"], color: "#24292f", backgroundColor: "#f6f8fa" }
  }),
  syntaxHighlighting(lightHighlightStyle)
];

function supportForLanguage(language) {
  switch (language) {
    case "css":
      return cssSupport;
    case "cssSelector":
      return selectorSupport;
    default:
      return javascriptSupport;
  }
}

function readOnlyExtensions(readOnly) {
  return [
    EditorState.readOnly.of(readOnly),
    EditorView.editable.of(!readOnly),
    EditorView.editorAttributes.of({ class: readOnly ? "quiper-read-only" : "" }),
    EditorView.contentAttributes.of({ "aria-readonly": readOnly ? "true" : "false" })
  ];
}

let scrollStateFrame = null;

function scheduleScrollStateReport() {
  if (scrollStateFrame !== null) {
    return;
  }
  scrollStateFrame = requestAnimationFrame(() => {
    scrollStateFrame = null;
    reportScrollState();
  });
}

function reportScrollState() {
  const scroller = editor.scrollDOM;
  const tolerance = 1;
  bridge?.postMessage({
    type: "scrollState",
    canScrollUp: scroller.scrollTop > tolerance,
    canScrollDown: scroller.scrollTop + scroller.clientHeight < scroller.scrollHeight - tolerance,
    canScrollLeft: scroller.scrollLeft > tolerance,
    canScrollRight: scroller.scrollLeft + scroller.clientWidth < scroller.scrollWidth - tolerance
  });
}

const editor = new EditorView({
  parent: document.getElementById("editor"),
  state: EditorState.create({
    doc: "",
    extensions: [
      basicSetup,
      EditorState.tabSize.of(2),
      languageCompartment.of(javascriptSupport),
      readOnlyCompartment.of(readOnlyExtensions(false)),
      themeCompartment.of(currentTheme === "light" ? lightTheme : darkTheme),
      languageToolsCompartment.of([]),
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !applyingHostUpdate) {
          bridge?.postMessage({
            type: "change",
            text: update.state.doc.toString()
          });
        }
        if (update.docChanged || update.viewportChanged || update.geometryChanged) {
          scheduleScrollStateReport();
        }
      })
    ]
  })
});

editor.scrollDOM.addEventListener("scroll", scheduleScrollStateReport, { passive: true });
new ResizeObserver(scheduleScrollStateReport).observe(editor.scrollDOM);
scheduleScrollStateReport();

function setDocument(payload) {
  const effects = [];
  const nextLanguage = payload.language || "javascript";
  const nextReadOnly = Boolean(payload.readOnly);
  const nextTheme = payload.theme === "light" ? "light" : "dark";
  const readOnlyChanged = nextReadOnly !== currentReadOnly;
  const themeChanged = nextTheme !== currentTheme;

  if (nextLanguage !== currentLanguage) {
    currentLanguage = nextLanguage;
    effects.push(languageCompartment.reconfigure(supportForLanguage(nextLanguage)));
  }
  if (readOnlyChanged) {
    effects.push(readOnlyCompartment.reconfigure(readOnlyExtensions(nextReadOnly)));
  }
  if (themeChanged) {
    effects.push(themeCompartment.reconfigure(nextTheme === "light" ? lightTheme : darkTheme));
  }
  currentReadOnly = nextReadOnly;
  currentTheme = nextTheme;

  const nextText = typeof payload.text === "string" ? payload.text : "";
  const changes = nextText === editor.state.doc.toString()
    ? undefined
    : { from: 0, to: editor.state.doc.length, insert: nextText };

  if (changes || effects.length > 0) {
    applyingHostUpdate = true;
    editor.dispatch({ changes, effects });
    applyingHostUpdate = false;
  }
  scheduleScrollStateReport();
}

window.quiperEditor = {
  setDocument,
  focus: () => editor.focus()
};

bridge?.postMessage({ type: "ready" });
