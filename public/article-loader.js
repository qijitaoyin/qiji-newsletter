(function () {
  const page = document.querySelector("[data-article-page]");
  if (!page) return;

  const searchParams = new URLSearchParams(window.location.search);
  const isReviewFrame = searchParams.get("reviewFrame") === "1";
  const reviewViewport = searchParams.get("reviewViewport") || "";
  const basePath = document.documentElement.dataset.basePath || "/";
  const articleUrl = page.getAttribute("data-article-json");

  const withBase = (path) => {
    if (!path) return "";
    if (/^https?:\/\//.test(path)) return path;
    if (basePath === "/") return path;
    return `${basePath.replace(/\/$/, "")}/${path.replace(/^\//, "")}`;
  };

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
    const href = withBase(`/articles/${slug}/`);
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
    const time = make("time", "", article.date);
    time.setAttribute("datetime", article.date || "");
    byline.appendChild(time);
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
    const groupedTags = [
      ["\u5c08\u6b04", article.tags.filter((tag) => (tagByLabel[tag]?.kind || "column") === "column")],
      ["\u95dc\u9375\u5b57", article.tags.filter((tag) => tagByLabel[tag]?.kind === "keyword")]
    ].filter(([, tags]) => tags.length > 0);

    groupedTags.forEach(([title, tags]) => {
      const group = make("div", "article-tag-group");
      group.appendChild(make("span", "article-tag-group-title", title));
      const list = make("div", "article-tag-list-items");
      tags.forEach((tag) => {
        const link = make("a", "", tag);
        link.href = withBase(`/tags/${tagByLabel[tag]?.slug || tag}/`);
        list.appendChild(link);
      });
      group.appendChild(list);
      container.appendChild(group);
    });
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

    const blocks = article.contentBlocks || [];
    if (blocks.length > 0) {
      blocks.forEach((block) => {
        if (block.type === "heading") {
          body.appendChild(make("h2", "", block.text));
          return;
        }
        if (block.type === "image") {
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
        body.appendChild(make("p", "", block.text));
      });
      return;
    }

    (article.sections || []).forEach((section, index) => {
      const sectionElement = document.createElement("section");
      sectionElement.id = `section-${index + 1}`;
      if (section.heading) sectionElement.appendChild(make("h2", "", section.heading));
      (section.paragraphs || []).forEach((paragraph) => {
        sectionElement.appendChild(make("p", "", paragraph));
      });
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

  fetch(articleUrl, { headers: { accept: "application/json" } })
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
