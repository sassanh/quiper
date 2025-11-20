(function () {
if (window.__quiperFindInitialized__) {
  return;
}
window.__quiperFindInitialized__ = true;

const FIND_HIGHLIGHT_ATTR = "data-quiper-find-highlight";
const FIND_HIGHLIGHT_STYLE_ID = "quiper-find-highlight-style";

window.FindNext = function FindNext(options, callback) {
  window.webkit.messageHandlers.log.postMessage(`FindNext called with search: ${options.search}, forward: ${options.forward}`);
  const search = options.search.trim();
  if (!search) {
    if (window.findNext) {
      window.findNext.reset();
    }
    return callback(null, { match: false });
  }

  const findOptions = {
    search: search,
    forward: options.forward,
    matchCase: false,
    wholeWord: false
  };

  if (!window.findNext || window.findNext.search !== search) {
    if (window.findNext) {
      window.findNext.reset();
    }
    window.findNext = new FindNextInstance(findOptions);
  } else {
    window.findNext.forward = options.forward;
  }
  
  window.findNext.next(callback);
};

function FindNextInstance(options) {
  window.webkit.messageHandlers.log.postMessage(`FindNextInstance created with search: ${options.search}`);
  this.search = options.search;
  this.forward = options.forward;
  this.matchCase = options.matchCase;
  this.wholeWord = options.wholeWord;
  this.ranges = [];
  this.currentIndex = -1;
  this.observer = null;
  this.findStyle = null;
  this.scrollListenerAttached = false;
  this.relayoutScheduled = false;
  this.boundRelayout = null;

  this.isHighlightNode = (node) => {
    return !!(node &&
      node.nodeType === Node.ELEMENT_NODE &&
      node.getAttribute &&
      node.getAttribute(FIND_HIGHLIGHT_ATTR) === "true");
  };

  this.isIgnorableMutation = (mutation) => {
    if (mutation.type === "childList") {
      const nodes = [...mutation.addedNodes, ...mutation.removedNodes];
      if (nodes.length === 0) {
        return true;
      }
      return nodes.every(this.isHighlightNode);
    }
    if (mutation.type === "characterData") {
      return this.isHighlightNode(mutation.target.parentElement);
    }
    return false;
  };

  this.observe = () => {
    if (this.observer) {
      return;
    }
    this.observer = new MutationObserver((mutations) => {
      const onlyHighlights = mutations.every(this.isIgnorableMutation);
      if (onlyHighlights) {
        return;
      }
      this.requestRelayout();
    });
    this.observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: false
    });
  };

  this.next = (callback) => {
    if (this.ranges.length === 0) {
      this.initRanges(() => {
        this.step(callback);
      });
    } else {
      this.step(callback);
    }
    this.observe();
  };
  
  this.requestRelayout = () => {
    if (this.relayoutScheduled) {
      return;
    }
    this.relayoutScheduled = true;
    requestAnimationFrame(() => {
      this.relayoutScheduled = false;
      this.relayoutHighlights();
    });
  };

  this.relayoutHighlights = () => {
    this.ranges.forEach(range => {
      const rects = range.nativeRange.getClientRects();
      range.highlights.forEach((span, index) => {
        const rect = rects[index];
        if (!rect) {
          span.style.display = 'none';
          return;
        }
        span.style.display = 'block';
        span.style.left = `${window.scrollX + rect.left}px`;
        span.style.top = `${window.scrollY + rect.top}px`;
        span.style.width = `${rect.width}px`;
        span.style.height = `${rect.height}px`;
      });
    });
  };

  this.attachScrollListeners = () => {
    if (this.scrollListenerAttached) {
      return;
    }
    this.boundRelayout = () => this.requestRelayout();
    window.addEventListener('scroll', this.boundRelayout, true);
    window.addEventListener('resize', this.boundRelayout);
    this.scrollListenerAttached = true;
  };

  this.detachScrollListeners = () => {
    if (!this.scrollListenerAttached || !this.boundRelayout) {
      return;
    }
    window.removeEventListener('scroll', this.boundRelayout, true);
    window.removeEventListener('resize', this.boundRelayout);
    this.scrollListenerAttached = false;
    this.boundRelayout = null;
  };

  this.step = (callback) => {
    if (this.ranges.length === 0) {
      return callback(null, { total: 0, current: 0, match: false });
    }
    const nextIndex = this.findNextIndex(this.currentIndex);
    this.highlight(this.currentIndex, false);
    this.highlight(nextIndex, true);
    this.currentIndex = nextIndex;
    if (this.currentIndex >= 0) {
      this.ranges[this.currentIndex].nativeRange.startContainer.parentElement.scrollIntoView({
        block: 'nearest',
        inline: 'nearest'
      });
    }
    callback(null, {
      total: this.ranges.length,
      current: this.currentIndex + 1,
      match: this.currentIndex >= 0
    });
  };

  this.findNextIndex = (from) => {
    const total = this.ranges.length;
    if (total === 0) {
      return -1;
    }
    if (from === -1) {
      return this.forward ? 0 : total - 1;
    }
    const next = from + (this.forward ? 1 : -1);
    if (next < 0) {
      return total - 1;
    }
    if (next >= total) {
      return 0;
    }
    return next;
  };

  this.highlight = (index, toggle) => {
    if (index < 0 || index >= this.ranges.length) {
      return;
    }
    const range = this.ranges[index];
    range.highlights.forEach(span => {
      span.classList.toggle('find-highlight-active', toggle);
    });
  };

  this.initRanges = (callback) => {
    window.webkit.messageHandlers.log.postMessage('initRanges');
    const walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      (node) => {
        if (node.parentElement.tagName === 'SCRIPT' ||
            node.parentElement.tagName === 'STYLE' ||
            node.parentElement.tagName === 'NOSCRIPT') {
          return NodeFilter.FILTER_REJECT;
        }
        if (!node.textContent.trim()) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
      false
    );

    const regex = new RegExp(this.search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), this.matchCase ? 'g' : 'ig');
    let node;
    while (node = walker.nextNode()) {
      const text = node.textContent;
      let match;
      while (match = regex.exec(text)) {
        if (this.wholeWord) {
          if (match.index > 0 && /\w/.test(text[match.index - 1])) {
            continue;
          }
          if (match.index + match[0].length < text.length && /\w/.test(text[match.index + match[0].length])) {
            continue;
          }
        }
        const nativeRange = new Range();
        nativeRange.setStart(node, match.index);
        nativeRange.setEnd(node, match.index + match[0].length);
        this.ranges.push({ nativeRange: nativeRange, highlights: [] });
      }
    }
    window.webkit.messageHandlers.log.postMessage(`Found ${this.ranges.length} ranges`);
    this.applyHighlights(callback);
  };
  
  this.applyHighlights = (callback) => {
    window.webkit.messageHandlers.log.postMessage('applyHighlights');
    if (this.ranges.length === 0) {
      return callback();
    }
    
    if (!this.findStyle) {
      this.findStyle = document.getElementById(FIND_HIGHLIGHT_STYLE_ID);
    }
    if (!this.findStyle) {
      const style = document.createElement('style');
      style.id = FIND_HIGHLIGHT_STYLE_ID;
      style.setAttribute(FIND_HIGHLIGHT_ATTR, 'true');
      style.textContent = `
        .find-highlight {
          background-color: rgba(255, 229, 0, 0.45);
          border-radius: 4px;
          pointer-events: none;
          border: 1px solid rgba(0, 0, 0, 0.25);
          box-shadow:
            0 0 0 1px rgba(255, 255, 255, 0.35) inset;
        }
        .find-highlight-active {
          background-color: rgba(255, 174, 0, 0.55);
          border-color: rgba(0, 0, 0, 0.4);
          box-shadow:
            0 0 0 1px rgba(255, 255, 255, 0.45) inset,
            0 0 4px rgba(0, 0, 0, 0.15);
        }
        @media (prefers-color-scheme: dark) {
          .find-highlight {
            background-color: rgba(255, 214, 10, 0.4);
            mix-blend-mode: screen;
            border-color: rgba(255, 255, 255, 0.15);
            box-shadow:
              0 0 0 1px rgba(0, 0, 0, 0.55);
          }
          .find-highlight-active {
            background-color: rgba(255, 180, 0, 0.55);
            border-color: rgba(255, 255, 255, 0.35);
            box-shadow:
              0 0 0 1px rgba(0, 0, 0, 0.7),
              0 0 4px rgba(0, 0, 0, 0.4);
          }
        }
      `;
      document.head.appendChild(style);
      this.findStyle = style;
    }

    this.ranges.forEach(range => {
      const rects = range.nativeRange.getClientRects();
      for (let i = 0; i < rects.length; i++) {
        const rect = rects[i];
        const span = document.createElement('span');
        span.className = 'find-highlight';
        span.setAttribute(FIND_HIGHLIGHT_ATTR, 'true');
        span.style.position = 'absolute';
        span.style.left = `${window.scrollX + rect.left}px`;
        span.style.top = `${window.scrollY + rect.top}px`;
        span.style.width = `${rect.width}px`;
        span.style.height = `${rect.height}px`;
        span.style.zIndex = 9998;
        span.style.pointerEvents = 'none';
        document.body.appendChild(span);
        range.highlights.push(span);
      }
    });
    
    this.attachScrollListeners();
    this.requestRelayout();
    
    callback();
  };
  
  this.reset = () => {
    window.webkit.messageHandlers.log.postMessage('reset');
    this.ranges.forEach(range => {
      range.highlights.forEach(span => span.remove());
    });
    this.ranges = [];
    this.currentIndex = -1;
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
    this.detachScrollListeners();
    if (this.findStyle) {
      this.findStyle.remove();
      this.findStyle = null;
    }
  };
}

})();
