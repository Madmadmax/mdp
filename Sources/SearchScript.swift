import Foundation

/// Runs only inside the rendered document. Ranges and canvas overlays leave
/// Markdown markup, links, text selection, and copy/paste intact.
enum SearchScript {
    static let source = #"""
    (() => {
      const content = document.getElementById('content');
      const highlights = document.createElement('canvas');
      const overview = document.createElement('canvas');
      highlights.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:10';
      overview.style.cssText = 'position:fixed;top:0;right:1px;width:7px;height:100%;pointer-events:none;z-index:11';
      highlights.setAttribute('aria-hidden', 'true');
      overview.setAttribute('aria-hidden', 'true');
      document.body.append(highlights, overview);
      let query = '', ranges = [], geometry = [], index = 0, pendingFrame = 0;

      // Separate block elements so adjacent paragraphs cannot become a match,
      // while inline formatting such as "**hello** world" remains searchable.
      function textGroups() {
        const groups = [];
        let text = '', segments = [];
        function flush() {
          if (segments.length) groups.push({text, segments});
          text = ''; segments = [];
        }
        function visit(node) {
          if (node.nodeType === Node.TEXT_NODE) {
            segments.push({node, start: text.length, end: text.length + node.length});
            text += node.data;
            return;
          }
          if (node.nodeType !== Node.ELEMENT_NODE) return;
          if (['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(node.tagName)) return;
          const style = getComputedStyle(node);
          if (style.display === 'none' || style.visibility === 'hidden') return;
          if (node.tagName === 'BR') { text += '\n'; return; }
          const block = !['inline', 'contents'].includes(style.display);
          if (block) flush();
          for (const child of node.childNodes) visit(child);
          if (block) flush();
        }
        visit(content);
        flush();
        return groups;
      }

      function collect(value) {
        if (!value.trim()) return [];
        const escaped = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
        const pattern = new RegExp(escaped, 'giu');
        const matches = [];
        for (const group of textGroups()) {
          pattern.lastIndex = 0;
          let match;
          while ((match = pattern.exec(group.text)) !== null) {
            const start = match.index, end = start + match[0].length;
            const first = group.segments.find(s => s.start <= start && s.end > start);
            const last = group.segments.find(s => s.start < end && s.end >= end);
            if (!first || !last) continue;
            const range = document.createRange();
            range.setStart(first.node, start - first.start);
            range.setEnd(last.node, end - last.start);
            if (range.getClientRects().length) matches.push(range);
          }
        }
        return matches;
      }

      function measure() {
        geometry = ranges.map(range => {
          const clips = [];
          for (let element = range.startContainer.parentElement; element && element !== document.body;
               element = element.parentElement) {
            const style = getComputedStyle(element);
            if (['auto', 'scroll', 'hidden', 'clip'].includes(style.overflowX) ||
                ['auto', 'scroll', 'hidden', 'clip'].includes(style.overflowY)) {
              const bounds = element.getBoundingClientRect();
              clips.push({
                left: style.overflowX === 'visible' ? -Infinity : bounds.left + element.clientLeft,
                right: style.overflowX === 'visible' ? Infinity : bounds.left + element.clientLeft + element.clientWidth,
                top: style.overflowY === 'visible' ? -Infinity : bounds.top + element.clientTop,
                bottom: style.overflowY === 'visible' ? Infinity : bounds.top + element.clientTop + element.clientHeight
              });
            }
          }
          return Array.from(range.getClientRects(), rect => {
            let left = rect.left, right = rect.right, top = rect.top, bottom = rect.bottom;
            for (const clip of clips) {
              left = Math.max(left, clip.left); right = Math.min(right, clip.right);
              top = Math.max(top, clip.top); bottom = Math.min(bottom, clip.bottom);
            }
            return {x: left + scrollX, y: top + scrollY,
                    width: Math.max(0, right - left), height: Math.max(0, bottom - top),
                    matchY: rect.top + scrollY};
          });
        });
      }

      function context(canvas, width, height) {
        const scale = devicePixelRatio || 1;
        const pixelWidth = Math.round(width * scale), pixelHeight = Math.round(height * scale);
        if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
          canvas.width = pixelWidth; canvas.height = pixelHeight;
        }
        canvas.style.width = width + 'px'; canvas.style.height = height + 'px';
        const ctx = canvas.getContext('2d');
        ctx.setTransform(scale, 0, 0, scale, 0, 0);
        ctx.clearRect(0, 0, width, height);
        return ctx;
      }

      function draw() {
        pendingFrame = 0;
        const ctx = context(highlights, innerWidth, innerHeight);
        const marks = context(overview, 7, innerHeight);
        const height = Math.max(document.documentElement.scrollHeight, innerHeight);
        for (let i = 0; i < geometry.length; i++) {
          ctx.fillStyle = i === index ? 'rgba(255,157,48,.48)' : 'rgba(255,215,64,.28)';
          for (const rect of geometry[i]) {
            const y = rect.y - scrollY;
            if (y + rect.height >= 0 && y <= innerHeight) {
              ctx.fillRect(rect.x - scrollX, y, rect.width, rect.height);
            }
          }
          const first = geometry[i][0];
          if (first && i !== index) {
            marks.fillStyle = '#e8bd48';
            marks.fillRect(0, Math.min(innerHeight - 3, first.matchY / height * innerHeight), 7, 3);
          }
        }
        // Draw the active marker last so nearby matches cannot obscure it.
        const active = geometry[index]?.[0];
        if (active) {
          marks.fillStyle = '#ff9d30';
          marks.fillRect(0, Math.min(innerHeight - 4, active.matchY / height * innerHeight), 7, 4);
        }
      }

      function scheduleDraw() {
        if (!pendingFrame) pendingFrame = requestAnimationFrame(draw);
      }

      function reveal() {
        const range = ranges[index];
        if (!range) return;
        for (let element = range.startContainer.parentElement; element && element !== document.body;
             element = element.parentElement) {
          const rect = range.getClientRects()[0];
          if (!rect) break;
          const bounds = element.getBoundingClientRect(), style = getComputedStyle(element);
          const left = bounds.left + element.clientLeft, top = bounds.top + element.clientTop;
          if (['auto', 'scroll'].includes(style.overflowX) &&
              (rect.left < left || rect.right > left + element.clientWidth)) {
            element.scrollLeft += rect.left - left - Math.max(0, (element.clientWidth - rect.width) / 2);
          }
          if (['auto', 'scroll'].includes(style.overflowY) &&
              (rect.top < top || rect.bottom > top + element.clientHeight)) {
            element.scrollTop += rect.top - top - Math.max(0, (element.clientHeight - rect.height) / 2);
          }
        }
        measure();
        const rect = geometry[index]?.[0];
        if (rect) window.scrollTo({top: Math.max(0, rect.matchY - innerHeight / 2), behavior: 'instant'});
      }

      window.mdpSearch = (value, targetIndex) => {
        if (value !== query) {
          query = value;
          ranges = collect(query);
          measure();
        }
        index = ranges.length ? ((targetIndex % ranges.length) + ranges.length) % ranges.length : 0;
        highlights.hidden = overview.hidden = !ranges.length;
        if (ranges.length) reveal();
        draw();
        return {count: ranges.length, index};
      };

      function layoutChanged() { measure(); scheduleDraw(); }
      // Element scroll events do not bubble; capture them and update clipped geometry.
      addEventListener('scroll', event => {
        if (event.target !== document) {
          measure();
          draw();
        } else {
          scheduleDraw();
        }
      }, {passive: true, capture: true});
      addEventListener('resize', layoutChanged);
      content.addEventListener('load', layoutChanged, true);
      new ResizeObserver(layoutChanged).observe(content);
      document.fonts.ready.then(layoutChanged);
      highlights.hidden = overview.hidden = true;
    })();
    """#
}
