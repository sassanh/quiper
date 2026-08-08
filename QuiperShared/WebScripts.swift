import Foundation
import WebKit

/// Single source of truth for the JavaScript injected into engine web views.
/// Keeps the macOS and iOS engines from drifting apart.
enum WebScripts {
    // MARK: - String escaping

    static func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    static func escapeForJavaScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    // MARK: - Value-setter interceptor (document start)

    /// Injects a `<style>` element with the engine's custom CSS at document end,
    /// mirroring the macOS `WebViewManager` CSS injection.
    static func makeCustomCSSInjectionScript(css: String) -> String {
        """
        const style = document.createElement('style');
        style.textContent = `/* Custom CSS */
        \(css)`;
        document.head.appendChild(style);
        """
    }

    /// Clears the in-page find selection and resets the find state, mirroring the
    /// macOS `FindBarViewController` reset.
    static func makeResetFindScript() -> String {
        """
        (() => {
          if (window.__quiperFindState) {
              window.__quiperFindState.search = "";
              window.__quiperFindState.total = 0;
              window.__quiperFindState.index = 0;
          }
          const sel = window.getSelection();
          if (sel) { sel.removeAllRanges(); }
        })();
        """
    }

    /// Counts visible-text occurrences for the iOS native find UI. WebKit's
    /// native find API performs the selection and scrolling but does not expose
    /// a total, so this supplies the denominator for the status label.
    static func makeFindMatchCountScript(search: String) -> String {
        """
        (() => {
            const root = document.body || document.documentElement;
            const needle = "\(search)".toLocaleLowerCase();
            if (!root || !needle) return 0;
            const text = (root.innerText || root.textContent || "").toLocaleLowerCase();
            let total = 0;
            let offset = 0;
            while ((offset = text.indexOf(needle, offset)) !== -1) {
                total += 1;
                offset += Math.max(needle.length, 1);
            }
            return total;
        })();
        """
    }

    /// Centers WebKit's selected find result. If the native find selection is
    /// not exposed through `window.getSelection()`, falls back to the indexed
    /// visible-text occurrence so pages with nested scrollers still move.
    static func makeScrollToFindMatchScript(search: String, index: Int) -> String {
        """
        (() => {
            const root = document.body || document.documentElement;
            const needle = "\(search)".toLocaleLowerCase();
            const targetIndex = \(index);
            if (!root || !needle || targetIndex < 1) return false;

            const scrollNode = (node) => {
                const element = node?.nodeType === Node.TEXT_NODE ? node.parentElement : node;
                if (!element?.scrollIntoView) return false;
                element.scrollIntoView({ block: "center", inline: "nearest", behavior: "smooth" });
                return true;
            };

            const selection = window.getSelection();
            if (selection?.rangeCount && !selection.isCollapsed) {
                const range = selection.getRangeAt(0);
                if (scrollNode(range.startContainer)) return true;
            }

            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    const parent = node.parentElement;
                    if (!parent || !node.nodeValue) return NodeFilter.FILTER_REJECT;
                    if (["SCRIPT", "STYLE", "NOSCRIPT"].includes(parent.tagName)) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    const style = getComputedStyle(parent);
                    if (style.display === "none" || style.visibility === "hidden") {
                        return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            let matchIndex = 0;
            let node;
            while ((node = walker.nextNode())) {
                const text = node.nodeValue.toLocaleLowerCase();
                let offset = 0;
                while ((offset = text.indexOf(needle, offset)) !== -1) {
                    matchIndex += 1;
                    if (matchIndex === targetIndex) return scrollNode(node);
                    offset += Math.max(needle.length, 1);
                }
            }
            return false;
        })();
        """
    }

    /// Finds the next (or previous) occurrence of `search` in the page and returns
    /// `{ match, current, total }`. Identical to the macOS `FindBarViewController`
    /// find script. `search` must already be JavaScript-escaped.
    static func makeFindScript(search: String, backwards: Bool, resetSelection: Bool) -> String {
        let backwardsLiteral = backwards ? "true" : "false"
        let resetLiteral = resetSelection ? "true" : "false"
        return """
        (() => {
            const search = "\(search)";
            const backwards = \(backwardsLiteral);
            let forceReset = \(resetLiteral);
            const root = document.body || document.documentElement;
            const selection = window.getSelection();
            if (!root || !selection) {
                return { match: false, current: 0, total: 0 };
            }
            if (!document.getElementById("__quiperFindSelectionStyle")) {
                const style = document.createElement("style");
                style.id = "__quiperFindSelectionStyle";
                style.textContent = `
                    ::selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                    ::-moz-selection {
                        background-color: rgba(255, 210, 0, 0.95) !important;
                        color: #000 !important;
                    }
                `;
                (document.head || document.body || document.documentElement).appendChild(style);
            }
            const textContent = root.innerText || root.textContent || "";
            const escapedPattern = search.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&");
            const regex = escapedPattern ? new RegExp(escapedPattern, "gi") : null;
            if (!window.__quiperFindState) {
                window.__quiperFindState = { search: "", total: 0, index: 0 };
            }
            const state = window.__quiperFindState;
            if (state.search !== search) {
                state.search = search;
                forceReset = true;
            }
            if (!search) {
                state.total = 0;
                state.index = 0;
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            if (forceReset) {
                state.total = regex ? (textContent.match(regex) || []).length : 0;
                state.index = backwards ? state.total + 1 : 0;
                selection.removeAllRanges();
                const range = document.createRange();
                range.selectNodeContents(root);
                range.collapse(!backwards);
                selection.addRange(range);
            }
            const total = state.total;
            if (!total) {
                selection.removeAllRanges();
                return { match: false, current: 0, total: 0 };
            }
            const match = window.find(search, false, backwards, true, false, true, false);
            if (!match) {
                return { match: false, current: 0, total };
            }
            if (backwards) {
                state.index = state.index <= 1 ? total : state.index - 1;
            } else {
                state.index = state.index >= total ? 1 : state.index + 1;
            }
            const selectionNode = selection.focusNode && selection.focusNode.nodeType === Node.TEXT_NODE
                ? selection.focusNode.parentElement
                : selection.focusNode;
            if (selectionNode && selectionNode.scrollIntoView) {
                selectionNode.scrollIntoView({ block: 'center', inline: 'nearest' });
            }
            return { match: true, current: state.index, total };
        })();
        """
    }

    /// Intercepts programmatic `value` writes on textarea/input so the tracker can
    /// react to framework-managed composers that bypass native events.
    static func makeValueSetterInterceptorScript() -> WKUserScript {
        let source = """
        (function() {
            if (window.__quiperInputStartInstalled) return;
            window.__quiperInputStartInstalled = true;

            function interceptProperty(proto, prop) {
                try {
                    const descriptor = Object.getOwnPropertyDescriptor(proto, prop);
                    if (!descriptor) return;
                    const originalSet = descriptor.set;
                    if (!originalSet) return;
                    descriptor.set = function(val) {
                        originalSet.call(this, val);
                        try {
                            this.dispatchEvent(new CustomEvent('quiper-value-set', { detail: { value: val } }));
                        } catch(e) {}
                    };
                    Object.defineProperty(proto, prop, descriptor);
                } catch (e) {
                    console.error("Quiper: failed to intercept " + prop, e);
                }
            }
            interceptProperty(HTMLTextAreaElement.prototype, 'value');
            interceptProperty(HTMLInputElement.prototype, 'value');
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Input-state tracker (document end)

    /// Tracks typing in the engine composer and reports input state / submitted prompts
    /// through the `quiperInputState` message handler. Recording-indicator behavior is
    /// gated by `__quiperRecordingEnabled` / `__quiperRecordingIndicatorStyle`, which
    /// platform code sets only when that feature is in use.
    static func makeInputStateTrackerScript(selector: String, initiallyActive: Bool) -> WKUserScript {
        let escapedSelector = escapeForJavaScript(selector)
        let source = """
        (function() {
            if (window.__quiperInputTrackerInstalled) return;
            window.__quiperInputTrackerInstalled = true;
            window.__quiperInputTrackerActive = \(initiallyActive ? "true" : "false");
            if (typeof window.__quiperRecordingEnabled !== 'boolean') {
                window.__quiperRecordingEnabled = false;
            }

            const selector = "\(escapedSelector)";
            window.__quiperLatestTypedText = "";
            window.__quiperLastInputWasTrustedClear = false;
            if (typeof window.__quiperRecordingIndicatorStyle !== 'string') {
                window.__quiperRecordingIndicatorStyle = "dashed";
            }
            let indicatorOverlay = null;
            let layoutInterval = null;
            let indicatedElement = null;
            const ARC_LAYER_COUNT = 18;
            const ARC_MAX_LEN = 18;
            const ARC_MIN_LEN = 2.5;
            const ARC_MIN_OPACITY = 0.04;
            const ARC_MAX_OPACITY = 0.46;
            const ARC_SPIN_SECONDS = 5;

            function ensureRecordingStyles() {
                if (document.getElementById('__quiper-recording-style')) return;
                const style = document.createElement('style');
                style.id = '__quiper-recording-style';
                const parts = [
                    '#__quiper-recording-glow {',
                    '  position: fixed;',
                    '  pointer-events: none;',
                    '  z-index: 2147483646;',
                    '  display: none;',
                    '  overflow: visible;',
                    '}',
                    '#__quiper-recording-glow svg {',
                    '  display: block;',
                    '  overflow: visible;',
                    '}',
                    '#__quiper-recording-glow rect {',
                    '  fill: none;',
                    '  stroke-linecap: round;',
                    '}',
                    '#__quiper-recording-glow .__quiper-recording-border {',
                    '  display: none;',
                    '  stroke: rgba(148, 148, 148, 0.35);',
                    '  stroke-width: 4;',
                    '  stroke-dasharray: 2 3;',
                    '}',
                    '#__quiper-recording-glow[data-style="dashed"] .__quiper-recording-border {',
                    '  display: block;',
                    '  animation: __quiper-recording-border-motion 2s linear infinite;',
                    '}',
                    '@keyframes __quiper-recording-border-motion {',
                    '  from { stroke-dashoffset: 0; }',
                    '  to { stroke-dashoffset: 5; }',
                    '}',
                    '@keyframes __quiper-recording-border-bounce {',
                    '  0% {',
                    '    stroke: rgba(148, 148, 148, 0.35);',
                    '    stroke-width: 4;',
                    '    stroke-dasharray: 2 3;',
                    '    animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);',
                    '  }',
                    '  23% {',
                    '    stroke: rgba(132, 166, 198, 0.72);',
                    '    stroke-width: 6;',
                    '    stroke-dasharray: 3 2;',
                    '    animation-timing-function: linear;',
                    '  }',
                    '  33% {',
                    '    stroke: rgba(132, 166, 198, 0.72);',
                    '    stroke-width: 6;',
                    '    stroke-dasharray: 3 2;',
                    '    animation-timing-function: cubic-bezier(0.22, 1, 0.36, 1);',
                    '  }',
                    '  100% {',
                    '    stroke: rgba(148, 148, 148, 0.35);',
                    '    stroke-width: 4;',
                    '    stroke-dasharray: 2 3;',
                    '  }',
                    '}',
                    '#__quiper-recording-glow[data-style="dashed"].__quiper-prompt-saved .__quiper-recording-border {',
                    '  animation: __quiper-recording-border-motion 2s linear infinite, __quiper-recording-border-bounce 780ms linear 1;',
                    '}',
                    '#__quiper-recording-glow .__quiper-glow-arc {',
                    '  display: none;',
                    '}',
                    '#__quiper-recording-glow .__quiper-save-ripple {',
                    '  display: none;',
                    '  stroke: rgba(96, 165, 250, 0.92);',
                    '  stroke-width: 2;',
                    '  opacity: 0;',
                    '  transform-box: fill-box;',
                    '  transform-origin: center;',
                    '}',
                    '#__quiper-recording-glow[data-style="glow"] .__quiper-save-ripple {',
                    '  display: block;',
                    '}',
                    '@keyframes __quiper-prompt-saved-ripple {',
                    '  from { opacity: 0.92; transform: scale(1); }',
                    '  to { opacity: 0; transform: scale(var(--__quiper-ripple-scale-x, 1), var(--__quiper-ripple-scale-y, 1)); }',
                    '}',
                    '#__quiper-recording-glow[data-style="glow"].__quiper-prompt-saved .__quiper-save-ripple {',
                    '  animation: __quiper-prompt-saved-ripple 520ms cubic-bezier(0.16, 1, 0.3, 1);',
                    '}',
                    '@media (prefers-reduced-motion: reduce) {',
                    '  #__quiper-recording-glow .__quiper-recording-border,',
                    '  #__quiper-recording-glow .__quiper-glow-arc {',
                    '    animation: none !important;',
                    '  }',
                    '  #__quiper-recording-glow .__quiper-save-ripple {',
                    '    animation: none !important;',
                    '    opacity: 0 !important;',
                    '  }',
                    '}'
                ];
                for (let i = 0; i < ARC_LAYER_COUNT; i++) {
                    const t = ARC_LAYER_COUNT === 1 ? 1 : i / (ARC_LAYER_COUNT - 1);
                    const ease = t * t;
                    const len = ARC_MAX_LEN - t * (ARC_MAX_LEN - ARC_MIN_LEN);
                    const base = -(ARC_MAX_LEN - len) / 2;
                    const opacity = ARC_MIN_OPACITY + ease * (ARC_MAX_OPACITY - ARC_MIN_OPACITY);
                    const width = 2.05 - t * 0.55;
                    parts.push(
                        '@keyframes __quiper-recording-spin-' + i + ' {',
                        '  from { stroke-dashoffset: ' + base.toFixed(3) + '; }',
                        '  to { stroke-dashoffset: ' + (base - 100).toFixed(3) + '; }',
                        '}',
                        '#__quiper-recording-glow[data-style="glow"] .__quiper-arc-' + i + ' {',
                        '  display: block;',
                        '  stroke: rgba(96, 165, 250, ' + opacity.toFixed(3) + ');',
                        '  stroke-width: ' + width.toFixed(2) + ';',
                        '  stroke-dasharray: ' + len.toFixed(2) + ' ' + (100 - len).toFixed(2) + ';',
                        '  animation: __quiper-recording-spin-' + i + ' ' + ARC_SPIN_SECONDS + 's linear infinite;',
                        '}'
                    );
                }
                const blurUntil = Math.min(6, ARC_LAYER_COUNT - 1);
                for (let i = 0; i < blurUntil; i++) {
                    const blur = (0.85 * (1 - i / blurUntil)).toFixed(2);
                    parts.push(
                        '#__quiper-recording-glow .__quiper-arc-' + i + ' {',
                        '  filter: blur(' + blur + 'px);',
                        '}'
                    );
                }
                style.textContent = parts.join('\\n');
                (document.head || document.documentElement).appendChild(style);
            }

            function ensureIndicatorOverlay() {
                ensureRecordingStyles();
                if (indicatorOverlay && indicatorOverlay.isConnected) return indicatorOverlay;
                indicatorOverlay = document.createElement('div');
                indicatorOverlay.id = '__quiper-recording-glow';
                indicatorOverlay.setAttribute('aria-hidden', 'true');
                const svgNamespace = 'http://www.w3.org/2000/svg';
                const svg = document.createElementNS(svgNamespace, 'svg');
                for (let i = 0; i < ARC_LAYER_COUNT; i++) {
                    const arc = document.createElementNS(svgNamespace, 'rect');
                    arc.setAttribute('class', '__quiper-glow-arc __quiper-arc-' + i);
                    arc.setAttribute('pathLength', '100');
                    svg.appendChild(arc);
                }
                const saveRipple = document.createElementNS(svgNamespace, 'rect');
                saveRipple.setAttribute('class', '__quiper-save-ripple');
                svg.appendChild(saveRipple);
                const recordingBorder = document.createElementNS(svgNamespace, 'rect');
                recordingBorder.setAttribute('class', '__quiper-recording-border');
                recordingBorder.setAttribute('pathLength', '300');
                svg.appendChild(recordingBorder);
                indicatorOverlay.appendChild(svg);
                const root = document.documentElement || document.body;
                if (root) root.appendChild(indicatorOverlay);
                return indicatorOverlay;
            }

            function stopIndicatorTracking() {
                if (layoutInterval) {
                    clearInterval(layoutInterval);
                    layoutInterval = null;
                }
                if (indicatorOverlay) {
                    indicatorOverlay.style.display = 'none';
                    indicatorOverlay.classList.remove('__quiper-prompt-saved');
                }
                indicatedElement = null;
            }

            function recordingIndicatorStyle() {
                const style = window.__quiperRecordingIndicatorStyle;
                return style === 'glow' || style === 'dashed' ? style : 'off';
            }

            function parseBorderRadius(el, width, height) {
                let rx = 12;
                try {
                    const cs = window.getComputedStyle(el);
                    if (cs && cs.borderRadius) {
                        const first = String(cs.borderRadius).split(' ')[0];
                        const n = parseFloat(first);
                        if (!isNaN(n)) {
                            rx = first.indexOf('%') >= 0 ? (n / 100) * Math.min(width, height) : n;
                        }
                    }
                } catch (e) {}
                return Math.max(0, Math.min(rx + 4, width / 2, height / 2));
            }

            function positionIndicatorOverlay() {
                const indicatorStyle = recordingIndicatorStyle();
                if (!window.__quiperRecordingEnabled || indicatorStyle === 'off') {
                    stopIndicatorTracking();
                    return;
                }
                const el = selector ? document.querySelector(selector) : null;
                if (!el) {
                    if (indicatorOverlay) indicatorOverlay.style.display = 'none';
                    indicatedElement = null;
                    return;
                }
                const ring = ensureIndicatorOverlay();
                if (!ring) return;
                const r = el.getBoundingClientRect();
                if (r.width < 2 || r.height < 2 || (r.bottom < 0 && r.top < 0)) {
                    ring.style.display = 'none';
                    return;
                }
                const pad = 4;
                const w = Math.max(8, Math.round(r.width + pad * 2));
                const h = Math.max(8, Math.round(r.height + pad * 2));
                const inset = 1.5;
                const rx = parseBorderRadius(el, w, h);
                const svg = ring.querySelector('svg');
                const rects = ring.querySelectorAll('rect');
                if (!svg || !rects.length) return;

                if (ring.dataset.style !== indicatorStyle) {
                    ring.classList.remove('__quiper-prompt-saved');
                    ring.dataset.style = indicatorStyle;
                }
                ring.style.display = 'block';
                ring.style.left = Math.round(r.left - pad) + 'px';
                ring.style.top = Math.round(r.top - pad) + 'px';
                ring.style.width = w + 'px';
                ring.style.height = h + 'px';
                svg.setAttribute('width', String(w));
                svg.setAttribute('height', String(h));
                svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);

                const rw = Math.max(1, w - inset * 2);
                const rh = Math.max(1, h - inset * 2);
                const rectRx = Math.min(rx, rw / 2, rh / 2);
                rects.forEach(function(rect) {
                    rect.setAttribute('x', String(inset));
                    rect.setAttribute('y', String(inset));
                    rect.setAttribute('width', String(rw));
                    rect.setAttribute('height', String(rh));
                    rect.setAttribute('rx', String(rectRx));
                    rect.setAttribute('ry', String(rectRx));
                });
                const saveRipple = ring.querySelector('.__quiper-save-ripple');
                if (saveRipple) {
                    const expansion = 4;
                    saveRipple.style.setProperty('--__quiper-ripple-scale-x', String((rw + expansion * 2) / rw));
                    saveRipple.style.setProperty('--__quiper-ripple-scale-y', String((rh + expansion * 2) / rh));
                }
                indicatedElement = el;
            }

            function startIndicatorTracking() {
                positionIndicatorOverlay();
                // Layout sync only (composer moves/resizes). Indicator motion is CSS-only.
                if (layoutInterval) return;
                layoutInterval = setInterval(positionIndicatorOverlay, 250);
            }

            function updateRecordingIndicator() {
                if (!window.__quiperRecordingEnabled || recordingIndicatorStyle() === 'off') {
                    stopIndicatorTracking();
                    return;
                }
                startIndicatorTracking();
            }

            function acknowledgePromptSaved() {
                if (!window.__quiperRecordingEnabled) return;

                positionIndicatorOverlay();
                const ring = indicatorOverlay;
                if (!ring || !ring.isConnected || ring.style.display !== 'block') return;

                ring.classList.remove('__quiper-prompt-saved');
                void ring.offsetWidth;
                ring.classList.add('__quiper-prompt-saved');
            }

            window.__quiperUpdateRecordingIndicator = updateRecordingIndicator;
            window.__quiperAcknowledgePromptSaved = acknowledgePromptSaved;
            window.addEventListener('resize', function() {
                if (window.__quiperRecordingEnabled) positionIndicatorOverlay();
            }, true);
            window.addEventListener('scroll', function() {
                if (window.__quiperRecordingEnabled) positionIndicatorOverlay();
            }, true);


            function getContentEditableSelection(el) {
                try {
                    const selection = window.getSelection();
                    if (!selection.rangeCount) return { start: 0, end: 0, debug: "no rangeCount" };
                    const range = selection.getRangeAt(0);
                    
                    if (!el.contains(range.startContainer)) {
                        return { start: 0, end: 0, debug: "el does not contain startContainer" };
                    }
                    
                    const preCaretRange = range.cloneRange();
                    preCaretRange.selectNodeContents(el);
                    preCaretRange.setEnd(range.startContainer, range.startOffset);
                    const startOffset = preCaretRange.toString().length;
                    preCaretRange.setEnd(range.endContainer, range.endOffset);
                    const endOffset = preCaretRange.toString().length;
                    return { start: startOffset, end: endOffset, debug: "ok" };
                } catch (e) {
                    console.error("Quiper: error getting contenteditable selection", e);
                    return { start: 0, end: 0, debug: "exception: " + e.message };
                }
            }

            function setContentEditableSelection(el, start, end) {
                const range = document.createRange();
                const selection = window.getSelection();
                
                let currentOffset = 0;
                let startNode = null;
                let startNodeOffset = 0;
                let endNode = null;
                let endNodeOffset = 0;
                
                function traverse(node) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const len = node.length;
                        if (!startNode && currentOffset + len >= start) {
                            startNode = node;
                            startNodeOffset = start - currentOffset;
                        }
                        if (!endNode && currentOffset + len >= end) {
                            endNode = node;
                            endNodeOffset = end - currentOffset;
                        }
                        currentOffset += len;
                    } else {
                        for (let i = 0; i < node.childNodes.length; i++) {
                            traverse(node.childNodes[i]);
                            if (startNode && endNode) break;
                        }
                    }
                }
                
                traverse(el);
                
                if (!startNode) {
                    startNode = el;
                    startNodeOffset = el.childNodes.length;
                }
                if (!endNode) {
                    endNode = el;
                    endNodeOffset = el.childNodes.length;
                }
                
                try {
                    range.setStart(startNode, startNodeOffset);
                    range.setEnd(endNode, endNodeOffset);
                    selection.removeAllRanges();
                    selection.addRange(range);
                } catch (e) {
                    console.error("Error setting contenteditable selection", e);
                }
            }

            function getElementState(el) {
                if (!el) return null;
                const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                if (isContentEditable) {
                    const sel = getContentEditableSelection(el);
                    const text = el.innerText || "";
                    return {
                        text: text,
                        isContentEditable: true,
                        start: typeof sel.start === 'number' ? sel.start : 0,
                        end: typeof sel.end === 'number' ? sel.end : 0,
                        debug: sel.debug || ""
                    };
                } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                    let start = 0;
                    let end = 0;
                    try {
                        start = typeof el.selectionStart === 'number' ? el.selectionStart : 0;
                        end = typeof el.selectionEnd === 'number' ? el.selectionEnd : 0;
                    } catch (e) {
                        // ignore if selection is not supported by input type
                    }
                    const text = el.value || "";
                    return {
                        text: text,
                        isContentEditable: false,
                        start: start,
                        end: end,
                        debug: "input"
                    };
                }
                return null;
            }

            function getTargetElement() {
                if (!selector) return null;
                return document.querySelector(selector);
            }

            let lastSentText = null;
            let lastSentStart = null;
            let lastSentEnd = null;

            function setPendingClearType(clearType) {
                window.__quiperLastClearType = clearType;
            }

            function clearPendingClearType() {
                window.__quiperLastClearType = null;
            }

            function consumePendingClearType(defaultClearType) {
                const clearType = window.__quiperLastClearType || defaultClearType;
                clearPendingClearType();
                return clearType;
            }

            function sendState(immediate) {
                if (window.__quiperInputTrackerActive === false) return;
                const el = getTargetElement();
                if (!el) return;
                
                const hasFocus = document.hasFocus();
                const state = getElementState(el);
                if (!state) return;

                let start = state.start;
                let end = state.end;
                if (!hasFocus) {
                    start = lastSentStart !== null ? lastSentStart : state.start;
                    end = lastSentEnd !== null ? lastSentEnd : state.end;
                }

                if (!window.__quiperForceRecordPrompt && state.text && state.text.trim() !== "") {
                    window.__quiperLatestTypedText = state.text;
                }

                let wasSent = false;
                let wasSentText = "";
                let clearType = "submit";
                
                if (window.__quiperForceRecordPrompt && window.__quiperLatestTypedText && window.__quiperLatestTypedText.trim() !== "") {
                    wasSent = true;
                    wasSentText = window.__quiperLatestTypedText;
                    clearType = consumePendingClearType("submit");
                    window.__quiperForceRecordPrompt = false;
                    window.__quiperLatestTypedText = "";
                } else {
                    const isTextEmpty = !state.text || state.text.trim() === "";
                    if (isTextEmpty && window.__quiperLatestTypedText && window.__quiperLatestTypedText.trim() !== "") {
                        wasSent = true;
                        wasSentText = window.__quiperLatestTypedText;
                        clearType = consumePendingClearType("submit");
                        window.__quiperLatestTypedText = "";
                    }
                }

                if (!wasSent && state.text === lastSentText && start === lastSentStart && end === lastSentEnd) {
                    return;
                }

                lastSentText = state.text;
                lastSentStart = start;
                lastSentEnd = end;

                const payload = {
                    text: state.text,
                    isContentEditable: state.isContentEditable,
                    start: start,
                    end: end,
                    wasSent: wasSent,
                    wasSentText: wasSentText,
                    clearType: clearType,
                    debug: state.debug || ""
                };

                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quiperInputState) {
                    window.webkit.messageHandlers.quiperInputState.postMessage(payload);
                }
            }

            let debounceTimer = null;
            function debouncedSend() {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => {
                    sendState(false);
                }, 150);
            }

            // User interaction tracking & clear type detection
            window.__quiperLastInteractionTime = 0;
            let selectionLengthBeforeInput = 0;
            let textLengthBeforeInput = 0;
            let textBeforeInput = "";
            let selectedTextBeforeInput = "";
            let hasCapturedBeforeState = false;
            let inputOccurredSinceLastKeydown = false;
            window.__quiperLastClearType = null;
            window.__quiperForceRecordPrompt = false;
            
            function updateInteractionTime(e) {
                window.__quiperLastInteractionTime = Date.now();
                window.__quiperHasSavedSelection = false;
            }
            document.addEventListener('mousedown', updateInteractionTime, true);
            document.addEventListener('touchstart', updateInteractionTime, true);
            
            function captureBeforeState() {
                if (hasCapturedBeforeState) return;
                const el = getTargetElement();
                if (!el) return;
                const state = getElementState(el);
                if (!state) return;
                textBeforeInput = state.text || "";
                textLengthBeforeInput = textBeforeInput.length;
                if (state.isContentEditable) {
                    const sel = window.getSelection();
                    selectedTextBeforeInput = sel ? sel.toString() : "";
                    selectionLengthBeforeInput = selectedTextBeforeInput.length;
                } else {
                    const start = (typeof el.selectionStart === 'number') ? el.selectionStart : 0;
                    const end = (typeof el.selectionEnd === 'number') ? el.selectionEnd : 0;
                    selectionLengthBeforeInput = (end - start) || 0;
                    selectedTextBeforeInput = el.value ? el.value.substring(start, end) : "";
                }
                hasCapturedBeforeState = true;
            }

            document.addEventListener('keydown', (e) => {
                updateInteractionTime(e);
                inputOccurredSinceLastKeydown = false;
                captureBeforeState();
                const el = getTargetElement();
                if (el && e.isTrusted) {
                    const isDeleteKey = e.key === 'Backspace' || e.key === 'Delete';
                    const isCmd = e.metaKey || e.ctrlKey;
                    
                    if (isDeleteKey) {
                        if (isCmd) {
                            setPendingClearType("cmdBackspace");
                        } else if (selectionLengthBeforeInput > 0) {
                            setPendingClearType("selectionClear");
                        } else {
                            setPendingClearType("normalDelete");
                        }
                    } else if ((e.key === 'x' || e.key === 'X') && isCmd) {
                        setPendingClearType("selectionClear");
                    }
                }
            }, true);

            document.addEventListener('keyup', (e) => {
                if (!inputOccurredSinceLastKeydown) {
                    clearPendingClearType();
                }
                inputOccurredSinceLastKeydown = false;
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('mouseup', (e) => {
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('cut', (e) => {
                if (e && e.isTrusted) {
                    setPendingClearType("selectionClear");
                }
            }, true);

            document.addEventListener('beforeinput', (e) => {
                if (e && e.isTrusted) {
                    captureBeforeState();
                    if (e.inputType && e.inputType.startsWith('delete')) {
                        if (window.__quiperLastClearType === null) {
                            setPendingClearType(selectionLengthBeforeInput > 0 ? "selectionClear" : "normalDelete");
                        }
                    }
                }
            }, true);

            document.addEventListener('input', (e) => {
                const el = getTargetElement();
                if (el && (el === e.target || el.contains(e.target))) {
                    inputOccurredSinceLastKeydown = true;
                    const state = getElementState(el);
                    if (state) {
                        const normSel = selectedTextBeforeInput.replace(/\\s/g, '');
                        const normFull = textBeforeInput.replace(/\\s/g, '');
                        const wasSelectAll = normSel.length > 0 && (normSel === normFull || (normFull.length > 0 && normSel.length / normFull.length >= 0.95));
                        
                        if (wasSelectAll && textBeforeInput && textBeforeInput.trim() !== "") {
                            setPendingClearType("selectionClear");
                            window.__quiperLatestTypedText = textBeforeInput;
                            window.__quiperForceRecordPrompt = true;
                            sendState(true);
                            selectedTextBeforeInput = "";
                            selectionLengthBeforeInput = 0;
                            textBeforeInput = "";
                        }
                        
                        if (state.text && state.text.trim() !== "") {
                            window.__quiperLatestTypedText = state.text;
                            clearPendingClearType();
                        }
                        
                        const isTextEmpty = !state.text || state.text.trim() === "";
                        if (isTextEmpty) {
                            sendState(true);
                        } else {
                            debouncedSend();
                        }
                    }
                }
                hasCapturedBeforeState = false;
            }, true);

            document.addEventListener('selectionchange', () => {
                const el = getTargetElement();
                if (el && (document.activeElement === el || el.contains(document.activeElement))) {
                    const lastInteract = window.__quiperLastInteractionTime || 0;
                    if (Date.now() - lastInteract < 500) {
                        debouncedSend();
                    } else if (window.__quiperHasSavedSelection) {
                        const current = getElementState(el);
                        if (current && (current.start !== window.__quiperSavedStart || current.end !== window.__quiperSavedEnd)) {
                            if (current.isContentEditable) {
                                setContentEditableSelection(el, window.__quiperSavedStart, window.__quiperSavedEnd);
                            } else {
                                el.setSelectionRange(window.__quiperSavedStart, window.__quiperSavedEnd);
                            }
                        }
                    }
                }
            });

            window.addEventListener('blur', () => {
                sendState(true);
            });

            window.addEventListener('pagehide', () => {
                sendState(true);
            });

            // Listen to value updates programmatically intercepted by the document start script
            document.addEventListener('quiper-value-set', (e) => {
                const el = getTargetElement();
                if (el && (e.target === el || el.contains(e.target))) {
                    window.__quiperLastInputWasTrustedClear = false;
                    sendState(true);
                }
            }, true);

            // Setup MutationObserver on document body to find target element if it's contenteditable
            let observer = null;
            function setupMutationObserver() {
                try {
                    if (observer) observer.disconnect();
                    observer = new MutationObserver((mutations) => {
                        let structureChanged = false;
                        for (const m of mutations) {
                            if (m.type === 'childList') {
                                structureChanged = true;
                                break;
                            }
                        }
                        // SPA remounts replace the composer; keep the indicator attached.
                        if (structureChanged || (indicatedElement && !indicatedElement.isConnected)) {
                            if (window.__quiperRecordingEnabled) {
                                updateRecordingIndicator();
                            }
                        }
                        const el = getTargetElement();
                        if (el) {
                            const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                            if (isContentEditable) {
                                sendState(true);
                            }
                        }
                    });
                    observer.observe(document.body, { childList: true, characterData: true, subtree: true });
                    updateRecordingIndicator();
                } catch (e) {
                    console.error("Quiper: failed to setup MutationObserver", e);
                }
            }
            if (document.body) {
                setupMutationObserver();
            } else {
                document.addEventListener('DOMContentLoaded', setupMutationObserver);
            }
            // Re-apply if Swift already pushed recording state before this script finished installing.
            updateRecordingIndicator();
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.quiperInputTrackerReady) {
                window.webkit.messageHandlers.quiperInputTrackerReady.postMessage({});
            }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    // MARK: - Focus composer

    /// Focuses the composer, optionally restoring preserved text and caret position.
    static func makeFocusInputScript(selector: String, hasSaved: Bool, text: String, start: Int, end: Int) -> String {
        let escapedSelector = escapeForJavaScript(selector)
        let jsString = """
        (function() {
            const selector = "\(escapedSelector)";
            const hasSaved = \(hasSaved);
            const text = \(escapeForJavaScriptLiteral(text));
            const start = \(start);
            const end = \(end);
            
            function getContentEditableSelection(el) {
                const selection = window.getSelection();
                if (!selection.rangeCount) return { start: 0, end: 0 };
                const range = selection.getRangeAt(0);
                const preCaretRange = range.cloneRange();
                preCaretRange.selectNodeContents(el);
                preCaretRange.setEnd(range.startContainer, range.startOffset);
                const startOffset = preCaretRange.toString().length;
                preCaretRange.setEnd(range.endContainer, range.endOffset);
                const endOffset = preCaretRange.toString().length;
                return { start: startOffset, end: endOffset };
            }

            function setContentEditableSelection(el, start, end) {
                const range = document.createRange();
                const selection = window.getSelection();
                
                let currentOffset = 0;
                let startNode = null;
                let startNodeOffset = 0;
                let endNode = null;
                let endNodeOffset = 0;
                
                function traverse(node) {
                    if (node.nodeType === Node.TEXT_NODE) {
                        const len = node.length;
                        if (!startNode && currentOffset + len >= start) {
                            startNode = node;
                            startNodeOffset = start - currentOffset;
                        }
                        if (!endNode && currentOffset + len >= end) {
                            endNode = node;
                            endNodeOffset = end - currentOffset;
                        }
                        currentOffset += len;
                    } else {
                        for (let i = 0; i < node.childNodes.length; i++) {
                            traverse(node.childNodes[i]);
                            if (startNode && endNode) break;
                        }
                    }
                }
                
                traverse(el);
                
                if (!startNode) {
                    startNode = el;
                    startNodeOffset = el.childNodes.length;
                }
                if (!endNode) {
                    endNode = el;
                    endNodeOffset = el.childNodes.length;
                }
                
                try {
                    range.setStart(startNode, startNodeOffset);
                    range.setEnd(endNode, endNodeOffset);
                    selection.removeAllRanges();
                    selection.addRange(range);
                } catch (e) {
                    console.error("Error setting contenteditable selection", e);
                }
            }

            function tryFocusAndRestore(el) {
                const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                
                if (hasSaved) {
                    window.__quiperHasSavedSelection = true;
                    window.__quiperSavedStart = start;
                    window.__quiperSavedEnd = end;
                    
                    if (isContentEditable) {
                        if (typeof text === 'string' && el.innerText !== text) {
                            el.innerText = text;
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                        }
                    } else {
                        if (typeof text === 'string' && el.value !== text) {
                            el.value = text;
                            el.dispatchEvent(new Event('input', { bubbles: true }));
                            el.dispatchEvent(new Event('change', { bubbles: true }));
                        }
                    }
                } else {
                    window.__quiperHasSavedSelection = false;
                }
                
                el.focus();
                
                if (hasSaved) {
                    if (isContentEditable) {
                        setContentEditableSelection(el, start, end);
                    } else {
                        el.setSelectionRange(start, end);
                    }
                }

                // Register a focus listener to override programmatic focus resets
                if (!el.__quiperFocusListenerAdded) {
                    el.__quiperFocusListenerAdded = true;
                    el.addEventListener('focus', () => {
                        const lastInteract = window.__quiperLastInteractionTime || 0;
                        if (hasSaved && (Date.now() - lastInteract > 300)) {
                            if (isContentEditable) {
                                setContentEditableSelection(el, start, end);
                            } else {
                                el.setSelectionRange(start, end);
                            }
                        }
                    });
                }
            }

            if (window.__quiperFocusInterval) {
                clearInterval(window.__quiperFocusInterval);
                window.__quiperFocusInterval = null;
            }

            const initialEl = document.querySelector(selector);
            if (initialEl) {
                tryFocusAndRestore(initialEl);
                return;
            }

            const startTime = Date.now();
            const timeout = 15000;
            window.__quiperFocusInterval = setInterval(() => {
                const polledEl = document.querySelector(selector);
                if (polledEl) {
                    clearInterval(window.__quiperFocusInterval);
                    window.__quiperFocusInterval = null;
                    tryFocusAndRestore(polledEl);
                } else if (Date.now() - startTime > timeout) {
                    clearInterval(window.__quiperFocusInterval);
                    window.__quiperFocusInterval = null;
                }
            }, 100);
        })();
        """
        return jsString
    }

    // MARK: - Inject and submit

    /// Sets the composer value and dispatches a return-key press.
    static func makeInjectAndSubmitScript(selector: String, text: String) -> String {
        let escapedSelector = escapeForJavaScript(selector)
        let jsString = """
        (function() {
            const selector = "\(escapedSelector)";
            const text = \(escapeForJavaScriptLiteral(text));
            function setTextAndSubmit(el) {
                const isContentEditable = el.contentEditable === 'true' || el.getAttribute('contenteditable') === 'true';
                if (isContentEditable) {
                    if (el.innerText !== text) {
                        el.innerText = text;
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                } else {
                    if (el.value !== text) {
                        el.value = text;
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                    }
                }
                el.focus();
                const range = document.createRange();
                const selection = window.getSelection();
                range.selectNodeContents(el);
                selection.removeAllRanges();
                selection.addRange(range);
                const event = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true });
                el.dispatchEvent(event);
            }
            const initialEl = document.querySelector(selector);
            if (initialEl) { setTextAndSubmit(initialEl); return; }
            const startTime = Date.now();
            const interval = setInterval(() => {
                const el = document.querySelector(selector);
                if (el) {
                    clearInterval(interval);
                    setTextAndSubmit(el);
                } else if (Date.now() - startTime > 15000) {
                    clearInterval(interval);
                }
            }, 100);
        })();
        """
        return jsString
    }

    // MARK: - Action runner

    /// Wraps a custom-action script body so thrown exceptions surface as a
    /// `{ quiperError: ... }` result instead of failing silently.
    static func makeActionRunnerScript(script: String) -> String {
        """
        try {
          const wrapper = async () => {
            \(script)
          };
          await wrapper();
          return "ok";
        } catch (err) {
          return { quiperError: (err && err.message) ? err.message : String(err) };
        }
        """
    }

    /// Fallback script logged when an action has no implementation for a service.
    static func makeActionFallbackScript(actionName: String, serviceName: String) -> String {
        let message = "Action \(escapeForJavaScript(actionName.isEmpty ? "Action" : actionName)) not implemented for \(escapeForJavaScript(serviceName))"
        return "console.log(\"\(message)\")"
    }
}
