(function () {
  "use strict";

  const content = document.getElementById("content");

  function post(name, payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
      window.webkit.messageHandlers[name].postMessage(payload);
    }
  }

  function reportHeight() {
    requestAnimationFrame(function () {
      const body = document.body;
      const html = document.documentElement;
      const height = Math.max(
        body.scrollHeight,
        body.offsetHeight,
        html.clientHeight,
        html.scrollHeight,
        html.offsetHeight
      );
      post("heightChanged", height);
    });
  }

  function escapeHTML(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function preprocessTaskLists(markdown) {
    return markdown.replace(
      /^(\s*[-*+]\s+)\[( |x|X)\]\s+/gm,
      function (_, prefix, checked) {
        const className = checked.trim().length > 0 ? "task-marker checked" : "task-marker";
        return prefix + '<span class="' + className + '" aria-label="task item"></span> ';
      }
    );
  }

  function extractFootnotes(markdown) {
    const notes = [];
    const withoutDefinitions = markdown
      .split(/\r?\n/)
      .filter(function (line) {
        const match = line.match(/^\[\^([^\]]+)\]:\s*(.*)$/);
        if (!match) {
          return true;
        }
        notes.push({ id: match[1], text: match[2] });
        return false;
      })
      .join("\n");

    const withReferences = withoutDefinitions.replace(/\[\^([^\]]+)\]/g, function (_, id) {
      const index = notes.findIndex(function (note) { return note.id === id; });
      if (index < 0) {
        return "[^" + id + "]";
      }
      const number = index + 1;
      return '<sup id="fnref-' + escapeHTML(id) + '"><a href="#fn-' + escapeHTML(id) + '">' + number + "</a></sup>";
    });

    return { markdown: withReferences, notes: notes };
  }

  function protectFencedCode(markdown) {
    const fences = [];
    const protectedMarkdown = markdown.replace(
      /(^|\n)(`{3,}|~{3,})[\s\S]*?\n\2[^\n]*(?=\n|$)/g,
      function (match, prefix) {
        const token = "@@LEAFY_FENCE_" + fences.length + "@@";
        fences.push(match.slice(prefix.length));
        return prefix + token;
      }
    );
    return { markdown: protectedMarkdown, fences: fences };
  }

  function restoreFencedCode(markdown, fences) {
    return markdown.replace(/@@LEAFY_FENCE_(\d+)@@/g, function (_, index) {
      return fences[Number(index)] || "";
    });
  }

  function extractMath(markdown) {
    const protectedCode = protectFencedCode(markdown);
    const math = [];
    let text = protectedCode.markdown;

    function placeholder(expression, display) {
      const index = math.push({ expression: expression, display: display }) - 1;
      const tag = display ? "div" : "span";
      const className = display ? "math-block" : "math-inline";
      return "<" + tag + ' class="' + className + '" data-math-id="' + index + '"></' + tag + ">";
    }

    text = text.replace(/\$\$([\s\S]+?)\$\$/g, function (_, expression) {
      return placeholder(expression, true);
    });
    text = text.replace(/\\\[([\s\S]+?)\\\]/g, function (_, expression) {
      return placeholder(expression, true);
    });
    text = text.replace(/\\\(([\s\S]+?)\\\)/g, function (_, expression) {
      return placeholder(expression, false);
    });
    text = text.replace(/(^|[^\\$])\$([^\n$]+?)\$/g, function (_, prefix, expression) {
      return prefix + placeholder(expression, false);
    });

    return {
      markdown: restoreFencedCode(text, protectedCode.fences),
      math: math
    };
  }

  function createMarkdownIt() {
    if (!window.markdownit) {
      return null;
    }
    return window.markdownit({
      html: true,
      linkify: true,
      typographer: false,
      breaks: false,
      highlight: function (source, language) {
        if (!window.hljs) {
          return escapeHTML(source);
        }
        try {
          if (language && window.hljs.getLanguage(language)) {
            return window.hljs.highlight(source, { language: language, ignoreIllegals: true }).value;
          }
          return window.hljs.highlightAuto(source).value;
        } catch (_) {
          return escapeHTML(source);
        }
      }
    });
  }

  function renderFootnotes(notes, md) {
    if (!notes.length) {
      return "";
    }
    const items = notes.map(function (note, index) {
      return '<li id="fn-' + escapeHTML(note.id) + '">' + md.renderInline(note.text) + "</li>";
    });
    return '<section class="footnotes"><ol>' + items.join("") + "</ol></section>";
  }

  function sanitize(html) {
    if (!window.DOMPurify) {
      return html;
    }
    return window.DOMPurify.sanitize(html, {
      ADD_TAGS: ["details", "summary"],
      ADD_ATTR: [
        "aria-label",
        "class",
        "data-math-id",
        "href",
        "id",
        "rel",
        "src",
        "target",
        "title",
        "alt"
      ],
      FORBID_TAGS: ["script", "style", "iframe", "form", "input", "object", "embed", "textarea", "select"],
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto):|[^a-z]|[a-z+.\-]+(?:[^a-z+.\-:]|$))/i
    });
  }

  function hardenLinksAndImages(root) {
    root.querySelectorAll("a").forEach(function (link) {
      const href = link.getAttribute("href") || "";
      if (/^(https?:|mailto:)/i.test(href)) {
        link.setAttribute("target", "_blank");
        link.setAttribute("rel", "noopener noreferrer");
      } else if (!href.startsWith("#")) {
        link.removeAttribute("href");
      }
    });

    root.querySelectorAll("img").forEach(function (image) {
      const src = image.getAttribute("src") || "";
      if (!/^https:\/\//i.test(src)) {
        image.remove();
      }
    });
  }

  function renderMath(root, math) {
    if (!window.katex) {
      return;
    }
    root.querySelectorAll("[data-math-id]").forEach(function (node) {
      const item = math[Number(node.getAttribute("data-math-id"))];
      if (!item) {
        return;
      }
      try {
        window.katex.render(item.expression, node, {
          displayMode: item.display,
          throwOnError: false,
          output: "html"
        });
      } catch (_) {
        node.textContent = item.expression;
      }
    });
  }

  function decorateCodeBlocks(root) {
    root.querySelectorAll("pre > code").forEach(function (code) {
      const pre = code.parentElement;
      if (!pre || pre.parentElement.classList.contains("code-block")) {
        return;
      }

      const languageClass = Array.from(code.classList).find(function (className) {
        return className.indexOf("language-") === 0;
      });
      const language = languageClass ? languageClass.replace("language-", "") : "";
      const wrapper = document.createElement("div");
      wrapper.className = "code-block";
      const header = document.createElement("div");
      header.className = "code-header";
      const label = document.createElement("span");
      label.className = "code-language";
      label.textContent = language || "text";
      const button = document.createElement("button");
      button.className = "copy-code";
      button.type = "button";
      button.textContent = "\u590d\u5236";
      button.addEventListener("click", function () {
        post("copyCode", code.textContent || "");
        button.textContent = "\u5df2\u590d\u5236";
        window.setTimeout(function () {
          button.textContent = "\u590d\u5236";
        }, 1200);
      });
      header.appendChild(label);
      header.appendChild(button);
      pre.parentNode.insertBefore(wrapper, pre);
      wrapper.appendChild(header);
      wrapper.appendChild(pre);
    });
  }

  function render(markdown) {
    try {
      const md = createMarkdownIt();
      if (!md) {
        content.innerHTML = "<p>" + escapeHTML(markdown).replace(/\n/g, "<br>") + "</p>";
        reportHeight();
        return;
      }

      const footnoteResult = extractFootnotes(preprocessTaskLists(markdown || ""));
      const mathResult = extractMath(footnoteResult.markdown);
      const rawHTML = md.render(mathResult.markdown) + renderFootnotes(footnoteResult.notes, md);
      content.innerHTML = sanitize(rawHTML);
      hardenLinksAndImages(content);
      renderMath(content, mathResult.math);
      decorateCodeBlocks(content);
      reportHeight();
    } catch (error) {
      content.innerHTML = "<p>" + escapeHTML(markdown || "").replace(/\n/g, "<br>") + "</p>";
      post("renderFailed", String(error && error.message ? error.message : error));
      reportHeight();
    }
  }

  if (window.ResizeObserver) {
    new ResizeObserver(reportHeight).observe(document.body);
  }

  window.LeafyMarkdown = {
    render: render
  };
  post("rendererReady", true);
})();
