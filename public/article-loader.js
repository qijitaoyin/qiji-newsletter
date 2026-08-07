(function () {
  const page = document.querySelector("[data-article-page]");
  if (!page) return;

  const searchParams = new URLSearchParams(window.location.search);
  const isReviewFrame = searchParams.get("reviewFrame") === "1";
  const reviewViewport = searchParams.get("reviewViewport") || "";
  const basePath = document.documentElement.dataset.basePath || "/";
  const articleUrl = page.getAttribute("data-article-json");
  const isReviewArticlePage =
    window.location.pathname.includes("/review-articles/") || articleUrl?.includes("/data/review-articles/");

  const withBase = (path) => {
    if (!path) return "";
    if (/^https?:\/\//.test(path)) return path;
    if (basePath === "/") return path;
    return `${basePath.replace(/\/$/, "")}/${path.replace(/^\//, "")}`;
  };

  const reviewArticleUrl = withBase(`/data/review-articles/${page.dataset.slug}.json`);
  const dataUrl = isReviewFrame ? reviewArticleUrl : articleUrl;

  const normalizeCategory = (category = "") => {
    if (category.startsWith("如是我")) return "如是我聞";
    return category;
  };

  const cleanTitle = (title = "") =>
    title.replace(/([\u3400-\u9fff])[\s?]+(?=[\u3400-\u9fff])/g, "$1");

  const setText = (selector, value) => {
    const element = document.querySelector(selector);
    if (!element) return;
    element.textContent = value || "";
    element.hidden = !value;
  };

  const make = (tag, className, text) => {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  };

  const articleHref = (slug) => {
    const href = withBase(isReviewArticlePage || isReviewFrame ? `/review-articles/${slug}/` : `/articles/${slug}/`);
    if (!isReviewFrame) return href;
    const url = new URL(href, window.location.href);
    url.searchParams.set("reviewFrame", "1");
    if (reviewViewport) url.searchParams.set("reviewViewport", reviewViewport);
    return `${url.pathname}${url.search}${url.hash}`;
  };

  const renderMeta = (article) => {
    const meta = document.querySelector("[data-article-meta]");
    if (!meta) return;
    meta.textContent = "";
    [normalizeCategory(article.category), article.issue, article.readTime].filter(Boolean).forEach((item) => {
      meta.appendChild(make("span", "", item));
    });
  };

  const renderByline = (article) => {
    const byline = document.querySelector("[data-article-byline]");
    if (!byline) return;
    byline.textContent = "";
    if (article.author) byline.appendChild(make("span", "", article.author));
  };

  const renderCover = (article) => {
    const grid = document.querySelector("[data-article-hero-grid]");
    const cover = document.querySelector("[data-article-cover]");
    const image = document.querySelector("[data-article-cover-img]");
    const caption = document.querySelector("[data-article-cover-caption]");
    const hasHeroImage = Boolean(article.image && !article.image.includes("/assets/qiji-logo"));
    grid?.classList.toggle("has-no-cover", !hasHeroImage);
    if (!cover || !image) return;
    cover.hidden = !hasHeroImage;
    if (!hasHeroImage) return;
    image.src = article.image;
    image.alt = "";
    if (caption) {
      caption.textContent = article.imageCaption || "";
      caption.hidden = !article.imageCaption;
    }
  };

  const renderIssueMenu = (article, issueArticles) => {
    const container = document.querySelector("[data-article-issue-menu]");
    if (!container) return;
    container.textContent = "";
    const groups = [];
    issueArticles.forEach((item) => {
      const category = normalizeCategory(item.category);
      let group = groups.find((entry) => entry.category === category);
      if (!group) {
        group = { category, items: [] };
        groups.push(group);
      }
      group.items.push(item);
    });

    groups.forEach((group) => {
      const groupElement = make("div", "article-issue-group");
      groupElement.appendChild(make("span", "article-issue-group-title", group.category));
      group.items.forEach((item) => {
        const link = make("a", item.slug === article.slug ? "is-current" : "", item.title);
        link.href = articleHref(item.slug);
        if (item.slug === article.slug) link.setAttribute("aria-current", "page");
        groupElement.appendChild(link);
      });
      container.appendChild(groupElement);
    });
  };

  const renderTags = (article, articleTags) => {
    const container = document.querySelector("[data-article-tags]");
    if (!container) return;
    const tagByLabel = Object.fromEntries(articleTags.map((tag) => [tag.label, tag]));
    container.textContent = "";
    const category = normalizeCategory(article.category || "");
    const columnTags = category ? [category] : [];
    const keywordTags = (article.tags || []).filter(
      (tag) => tag !== category && tagByLabel[tag]?.kind === "keyword"
    );
    const groupedTags = [
      ["\u5c08\u6b04", columnTags],
      ["\u95dc\u9375\u5b57", keywordTags]
    ].filter(([, tags]) => tags.length > 0);

    groupedTags.forEach(([title, tags]) => {
      const group = make("div", "article-tag-group");
      group.appendChild(make("span", "article-tag-group-title", title));
      const list = make("div", "article-tag-list-items");
      tags.forEach((tag) => {
        const tagMeta = tagByLabel[tag];
        const link = make("a", "", tag);
        link.href = tagMeta?.slug ? withBase(`/tags/${tagMeta.slug}/`) : "#";
        if (!tagMeta?.slug) link.setAttribute("aria-disabled", "true");
        list.appendChild(link);
      });
      group.appendChild(list);
      container.appendChild(group);
    });
  };

  const keywordTagsFor = (article, articleTags) => {
    const tagByLabel = Object.fromEntries(articleTags.map((tag) => [tag.label, tag]));
    const category = normalizeCategory(article.category || "");
    return (article.tags || []).filter((tag) => tag !== category && tagByLabel[tag]?.kind === "keyword");
  };

  const renderReviewArticleAiPreview = (article, articleTags) => {
    const section = document.querySelector("[data-review-article-ai-preview]");
    if (!section) return;
    const quote = article.aiQuote || "";
    const summary = article.aiSummary || "";
    const category = normalizeCategory(article.category || "");
    const keywords = keywordTagsFor(article, articleTags);
    const hasRequiredAiData = Boolean(quote && summary && keywords.length);

    const quoteElement = section.querySelector("[data-review-article-quote]");
    const summaryElement = section.querySelector("[data-review-article-summary]");
    const categoryElement = section.querySelector("[data-review-article-category]");
    const keywordElement = section.querySelector("[data-review-article-keywords]");
    const emptyElement = section.querySelector("[data-review-article-ai-empty]");

    if (quoteElement) quoteElement.textContent = quote;
    if (summaryElement) summaryElement.textContent = summary;
    if (categoryElement) categoryElement.textContent = category;
    if (keywordElement) {
      keywordElement.textContent = "";
      keywords.forEach((tag) => keywordElement.appendChild(make("span", "", tag)));
    }
    if (emptyElement) emptyElement.hidden = hasRequiredAiData;
  };

  const renderAi = (article) => {
    const section = document.querySelector("[data-article-ai-guide]");
    const summary = document.querySelector("[data-article-ai-summary]");
    if (!section || !summary) return;
    section.hidden = !article.aiSummary;
    summary.textContent = article.aiSummary || "";
  };

  const renderBody = (article) => {
    const body = document.querySelector("[data-article-body]");
    if (!body) return;
    body.textContent = "";
    if (article.lede) body.appendChild(make("p", "article-lede", article.lede));

    const headingLevelFromText = (text, fallback = 2) => {
      const value = String(text || "").trim();
      if (/^([一二三四五六七八九十百千]+|\d{1,2})[、.．]\s*\S+/.test(value)) return 3;
      if (/^[（(]\s*([一二三四五六七八九十百千]+|\d{1,2})\s*[)）]\s*\S+/.test(value)) return 3;
      return fallback;
    };

    const looksLikeLegacyHeading = (text) => {
      const value = String(text || "").trim();
      if (!value) return false;
      if (headingLevelFromText(value, 0) >= 3) return true;
      if (value.length > 42) return false;
      if (/[。！？；：]$/.test(value)) return false;
      return true;
    };

    const orderedTextItem = (text) => String(text || "").match(/^(\d{1,2})[.．、]\s*(.+)$/);
    const colonListItem = (text) => String(text || "").trim().match(/^([^：:，,。！？；]{1,18})[：:]\s*(.+)$/);

    const appendList = (parent, items, ordered) => {
      if (items.length === 0) return;
      const list = document.createElement(ordered ? "ol" : "ul");
      list.className = "article-list";
      items.forEach((itemText) => list.appendChild(make("li", "", itemText)));
      parent.appendChild(list);
    };

    const blocks = article.contentBlocks || [];
    if (blocks.length > 0) {
      const mergedBlocks = [];
      blocks.forEach((block) => {
        const previous = mergedBlocks[mergedBlocks.length - 1];
        if (block.type === "quote" && previous?.type === "quote") {
          previous.text = [previous.text, block.text].filter(Boolean).join("\n\n");
          return;
        }
        mergedBlocks.push({ ...block });
      });

      let activeList = null;
      const flushList = () => {
        activeList = null;
      };

      mergedBlocks.forEach((block) => {
        if (block.type === "heading") {
          flushList();
          body.appendChild(make(Number(block.level) >= 3 ? "h3" : "h2", "", block.text));
          return;
        }
        if (block.type === "quote") {
          flushList();
          body.appendChild(make("blockquote", "article-classic-quote", block.text));
          return;
        }
        if (block.type === "image") {
          flushList();
          const figure = make("figure", "article-inline-image");
          const image = document.createElement("img");
          image.src = block.src;
          image.alt = block.caption || "";
          image.loading = "lazy";
          figure.appendChild(image);
          if (block.caption) figure.appendChild(make("figcaption", "", block.caption));
          body.appendChild(figure);
          return;
        }
        if (block.type === "listItem") {
          const ordered = Boolean(block.ordered);
          if (!activeList || activeList.tagName.toLowerCase() !== (ordered ? "ol" : "ul")) {
            activeList = document.createElement(ordered ? "ol" : "ul");
            activeList.className = "article-list";
            body.appendChild(activeList);
          }
          const item = make("li", "", block.text);
          const level = Number(block.level) || 0;
          if (level > 0) item.style.marginLeft = `${Math.min(level, 3) * 1.5}em`;
          activeList.appendChild(item);
          return;
        }
        flushList();
        body.appendChild(make("p", "", block.text));
      });
      return;
    }

    (article.sections || []).forEach((section, index) => {
      const sectionElement = document.createElement("section");
      sectionElement.id = `section-${index + 1}`;
      if (section.heading) {
        sectionElement.appendChild(make(headingLevelFromText(section.heading) >= 3 ? "h3" : "h2", "", section.heading));
      }

      const paragraphs = section.paragraphs || [];
      for (let paragraphIndex = 0; paragraphIndex < paragraphs.length; paragraphIndex += 1) {
        const paragraph = paragraphs[paragraphIndex];
        const orderedMatch = orderedTextItem(paragraph);
        if (orderedMatch) {
          const items = [];
          while (paragraphIndex < paragraphs.length) {
            const match = orderedTextItem(paragraphs[paragraphIndex]);
            if (!match) break;
            items.push(match[2]);
            paragraphIndex += 1;
          }
          paragraphIndex -= 1;
          appendList(sectionElement, items, true);
          continue;
        }

        const colonItems = [];
        let scanIndex = paragraphIndex;
        while (scanIndex < paragraphs.length) {
          const match = colonListItem(paragraphs[scanIndex]);
          if (!match) break;
          colonItems.push(`${match[1]}：${match[2]}`);
          scanIndex += 1;
        }
        if (colonItems.length >= 2) {
          appendList(sectionElement, colonItems, false);
          paragraphIndex = scanIndex - 1;
          continue;
        }

        if (looksLikeLegacyHeading(paragraph)) {
          sectionElement.appendChild(make(headingLevelFromText(paragraph) >= 3 ? "h3" : "h2", "", paragraph));
          continue;
        }

        sectionElement.appendChild(make("p", "", paragraph));
      }
      body.appendChild(sectionElement);
    });
  };

  const renderPager = (previousArticle, nextArticle) => {
    const pager = document.querySelector("[data-article-pager]");
    if (!pager) return;
    pager.textContent = "";
    pager.hidden = !previousArticle && !nextArticle;
    pager.classList.toggle("has-single-link", !previousArticle || !nextArticle);
    [
      [previousArticle, "上一篇"],
      [nextArticle, "下一篇"]
    ].forEach(([item, label]) => {
      if (!item) return;
      const link = document.createElement("a");
      link.href = articleHref(item.slug);
      link.appendChild(make("span", "", label));
      link.appendChild(make("strong", "", item.title));
      pager.appendChild(link);
    });
  };

  const renderRelated = (relatedArticles) => {
    const section = document.querySelector("[data-article-related-section]");
    const container = document.querySelector("[data-article-related]");
    if (!section || !container) return;
    section.hidden = !relatedArticles.length;
    container.textContent = "";
    relatedArticles.forEach((item) => {
      const card = document.createElement("article");
      const link = document.createElement("a");
      link.href = articleHref(item.slug);
      if (item.image && !item.image.includes("/assets/qiji-logo")) {
        const image = document.createElement("img");
        image.src = item.image;
        image.alt = "";
        image.loading = "lazy";
        link.appendChild(image);
      }
      const copy = document.createElement("div");
      const meta = make("p", "meta-line");
      meta.appendChild(make("span", "", item.category));
      meta.appendChild(make("span", "", item.date));
      copy.appendChild(meta);
      copy.appendChild(make("h3", "", item.title));
      if (item.aiSummary || item.excerpt) copy.appendChild(make("p", "", item.aiSummary || item.excerpt));
      if (item.author) copy.appendChild(make("p", "byline", item.author));
      link.appendChild(copy);
      card.appendChild(link);
      container.appendChild(card);
    });
  };

  const initArticleControls = () => {
    const body = document.querySelector("[data-article-body]");
    const controls = Array.from(document.querySelectorAll(".font-size-control [data-font-size]"));
    const key = "qiji-article-font-size";
    const applySize = (size) => {
      if (!body) return;
      body.setAttribute("data-font-size", size);
      controls.forEach((control) => {
        const isActive = control.getAttribute("data-font-size") === size;
        control.classList.toggle("is-active", isActive);
        control.setAttribute("aria-pressed", String(isActive));
      });
      window.localStorage.setItem(key, size);
    };
    const savedSize = window.localStorage.getItem(key);
    applySize(savedSize === "small" || savedSize === "large" ? savedSize : "medium");
    controls.forEach((control) => {
      control.addEventListener("click", () => applySize(control.getAttribute("data-font-size") || "medium"));
    });
  };

  const initArticleMenu = () => {
    const toggle = document.querySelector("[data-article-menu-toggle]");
    const sidebar = document.getElementById("article-side-menu");
    const closeControls = Array.from(document.querySelectorAll("[data-article-menu-close]"));
    const setOpen = (isOpen) => {
      document.body.classList.toggle("is-article-menu-open", isOpen);
      toggle?.setAttribute("aria-expanded", String(isOpen));
      if (isOpen) sidebar?.scrollTo({ top: 0 });
    };
    toggle?.addEventListener("click", () => setOpen(!document.body.classList.contains("is-article-menu-open")));
    closeControls.forEach((control) => control.addEventListener("click", () => setOpen(false)));
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") setOpen(false);
    });
  };

  const renderArticle = ({ article, issueArticles, relatedArticles, previousArticle, nextArticle, articleTags }) => {
    document.title = `${article.title} - 氣機導引電子報`;
    document.querySelector('meta[name="description"]')?.setAttribute("content", article.excerpt || "");
    renderMeta(article);
    setText("[data-article-title]", cleanTitle(article.title));
    setText("[data-article-quote]", article.aiQuote);
    setText("[data-article-subtitle]", article.subtitle);
    renderByline(article);
    renderCover(article);
    renderIssueMenu(article, issueArticles || []);
    renderTags(article, articleTags || []);
    renderReviewArticleAiPreview(article, articleTags || []);
    renderAi(article);
    renderBody(article);
    renderPager(previousArticle, nextArticle);
    renderRelated(relatedArticles || []);
  };

  const notifyReviewFrameReady = () => {
    if (!isReviewFrame || !window.parent || window.parent === window) return;
    window.requestAnimationFrame(() => {
      const height = Math.max(
        document.documentElement?.scrollHeight || 0,
        document.body?.scrollHeight || 0,
        document.querySelector(".article-page")?.scrollHeight || 0
      );
      window.parent.postMessage(
        {
          type: "qiji-review-frame-ready",
          slug: page.dataset.slug || "",
          viewport: reviewViewport,
          height
        },
        window.location.origin
      );
    });
  };

  fetch(dataUrl, { headers: { accept: "application/json" }, cache: isReviewFrame ? "no-store" : "default" })
    .then((response) => {
      if (!response.ok) throw new Error(`Article JSON not found: ${response.status}`);
      return response.json();
    })
    .then(renderArticle)
    .catch(() => {
      const body = document.querySelector("[data-article-body]");
      if (body) body.innerHTML = "<p>文章載入失敗，請稍後再試。</p>";
    })
    .finally(() => {
      if (isReviewFrame) {
        document.documentElement.classList.add("is-review-frame");
        document.body.classList.add("is-review-frame");
        if (reviewViewport === "mobile") {
          document.documentElement.classList.add("is-review-mobile-frame");
          document.body.classList.add("is-review-mobile-frame");
        }
      }
      initArticleControls();
      initArticleMenu();
      document.querySelectorAll("img").forEach((image) => {
        if (!image.complete) image.addEventListener("load", notifyReviewFrameReady, { once: true });
      });
      notifyReviewFrameReady();
      window.setTimeout(notifyReviewFrameReady, 250);
      window.setTimeout(notifyReviewFrameReady, 900);
    });
})();
