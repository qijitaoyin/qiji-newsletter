import html
import json
import re
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXTRACTED = ROOT / "各期電子報" / "202605" / "extracted-2605.json"
DIST = ROOT / "dist"

SLUG_MAP = {
    "2605-1": "surf-with-the-soul",
    "2605-2": "wave-maker-in-the-collective-wave",
    "2605-3-1": "awaken-the-spiritual-root",
    "2605-3-2": "cultivating-desire-into-great-mirror-wisdom",
    "2605-3-3": "spiritual-life-returning-to-nature",
    "2605-3-4": "reason-and-boundaries",
    "2605-3-5": "are-you-willing-to-be-an-npc",
    "2605-3-6": "eight-oclock-soul-practice",
    "2605-3-7": "effect-precedes-cause",
    "2605-4": "fear-or-not-fear",
}

TAG_MAP = {
    "2605-1": ["編輯小語", "同頻共振", "靈魂修煉"],
    "2605-2": ["同頻共振", "身體感知", "集體練功"],
    "2605-3-1": ["如是我聞", "靈魂修煉", "覺性修煉"],
    "2605-3-2": ["如是我聞", "慾望修煉", "覺性修煉"],
    "2605-3-3": ["如是我聞", "精神生活", "覺性修煉"],
    "2605-3-4": ["如是我聞", "理性修煉", "界樁"],
    "2605-3-5": ["如是我聞", "AI時代", "靈魂修煉"],
    "2605-3-6": ["如是我聞", "八點檔", "靈魂修煉"],
    "2605-3-7": ["如是我聞", "AI時代", "果因論"],
    "2605-4": ["體證道德經", "道德經", "恐懼修煉"],
}

TAG_SLUGS = {
    "編輯小語": "editor-note",
    "同頻共振": "resonance",
    "靈魂修煉": "soul-practice",
    "身體感知": "body-awareness",
    "集體練功": "collective-practice",
    "如是我聞": "rushi-wowen",
    "覺性修煉": "awareness-practice",
    "慾望修煉": "desire-practice",
    "精神生活": "spiritual-life",
    "理性修煉": "reason-practice",
    "界樁": "boundaries",
    "AI時代": "ai-era",
    "八點檔": "eight-oclock",
    "果因論": "effect-cause",
    "體證道德經": "daodejing-practice",
    "道德經": "daodejing",
    "恐懼修煉": "fear-practice",
}

TAG_DESCRIPTIONS = {
    "編輯小語": "本期編輯部導讀與主題開場。",
    "同頻共振": "身體氣流、群體波動與集體練功經驗。",
    "靈魂修煉": "從日常感受、覺察與選擇中鍛鍊靈魂。",
    "身體感知": "透過身體經驗辨識氣流、頻率與狀態轉換。",
    "集體練功": "多人同場練習時形成的互動與共振。",
    "如是我聞": "課堂聆聽與學員整理的修煉筆記。",
    "覺性修煉": "以覺察、感受與精神性作為修煉核心。",
    "慾望修煉": "面對慾望、痛苦與人性本能的修煉方法。",
    "精神生活": "以精神活動與內在感受開展生命經驗。",
    "理性修煉": "看見大腦習慣、界線與判斷模式。",
    "界樁": "固定認知、制式理解與內在框架的觀察。",
    "AI時代": "AI、資料化社會與靈魂主體性的反思。",
    "八點檔": "覺性同頻共振交流會相關筆記與體會。",
    "果因論": "由結果回看因緣與生命安排的修煉觀點。",
    "體證道德經": "從身心實踐體會《道德經》。",
    "道德經": "《道德經》章句與生活修煉的互證。",
    "恐懼修煉": "面對害怕、威壓與安定感的身心功課。",
}


def h(value):
    return html.escape(str(value), quote=True)


def title_markup(title):
    parts = [part for part in str(title).split() if part] or [str(title)]
    return "".join(f'<span class="title-phrase">{h(part)}</span>' for part in parts)


def header(article):
    blocks = [b["text"].strip() for b in article.get("headerBlocks", []) if b.get("text", "").strip()]
    category = article["section"]
    title_parts = []
    author_parts = []
    for text in blocks:
        if text.startswith("【") and text.endswith("】"):
            category = text.strip("【】 ")
        elif text.startswith("文") or text.startswith("編輯部"):
            author_parts.append(text)
        else:
            title_parts.append(text)
    title = article.get("title") or " ".join(title_parts).strip() or article.get("author") or article["section"]
    author = " / ".join(author_parts) or article.get("author", "")
    category = category.replace("\u30fb", "")
    return category, title, author


def menu_category(category):
    if category.startswith("如是我"):
        return "如是我聞"
    if category == "同頻共振時":
        return "導引專欄"
    return category


def terminal(text):
    return bool(re.search(r'[。！？；：]$|[。！？；：]」$', text))


def is_heading(blocks, index, article_id):
    text = blocks[index]["text"].strip()
    if blocks[index].get("type") == "heading":
        return True
    if index == 0 and article_id == "2605-4":
        return True
    if len(text) > 24 or index + 1 >= len(blocks):
        return False
    next_text = blocks[index + 1]["text"].strip()
    if len(next_text) < 34:
        return False
    if text in {"民不畏威，則大威至。", "無狎其所居，無厭其所生。", "夫唯不厭，是以不厭。"}:
        return False
    if terminal(text) and not text.endswith("？"):
        return False
    return True


def sections_for(article):
    sections = []
    current = {"paragraphs": []}
    blocks = article.get("blocks", [])
    for index, block in enumerate(blocks):
        text = block["text"].strip()
        if not text:
            continue
        if is_heading(blocks, index, article["id"]):
            if current.get("paragraphs") or current.get("heading"):
                sections.append(current)
            current = {"heading": text, "paragraphs": []}
        else:
            current.setdefault("paragraphs", []).append(text)
    if current.get("paragraphs") or current.get("heading"):
        sections.append(current)
    return sections


def excerpt(article):
    for block in article.get("blocks", []):
        text = block["text"].strip()
        if len(text) >= 40:
            return text[:90] + ("…" if len(text) > 90 else "")
    return ""


def read_time(article):
    chars = sum(len(block["text"]) for block in article.get("blocks", []))
    return f"約 {max(3, round(chars / 520))} 分鐘"


def image_path(article):
    image = next((img for img in article.get("images", []) if img.get("localPath")), None)
    if not image:
        return ""
    return f"/assets/articles/202605/{Path(image['localPath']).name}"


def layout(title, body):
    return f"""<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
  <meta http-equiv="Pragma" content="no-cache">
  <meta http-equiv="Expires" content="0">
  <link rel="icon" href="/assets/qiji-logo.png" type="image/png">
  <link rel="stylesheet" href="/styles/global.css?v=phrase-title-20260612-1">
  <title>{h(title)} - 氣機導引電子報</title>
</head>
<body>
  <header class="site-header">
    <a class="brand" href="/" aria-label="氣機導引電子報首頁">
      <span class="brand-mark"><img src="/assets/qiji-logo.png" alt=""></span>
      <span class="brand-text"><strong>氣機導引電子報</strong><small>Qiji Newsletter</small></span>
    </a>
    <div class="header-actions">
      <nav class="top-nav" aria-label="主要導覽">
        <a href="/#newest">最新一期</a>
        <a href="/topics/">依主題瀏覽</a>
        <a href="/archive/">歷史期數</a>
        <a href="https://www.qiji.org.tw/" target="_blank" rel="noreferrer">回氣機導引</a>
      </nav>
      <form class="site-search" action="#" aria-label="搜尋文章">
        <input name="keyword" type="search" placeholder="搜尋文章">
        <button type="submit" aria-label="搜尋">SEARCH</button>
      </form>
    </div>
  </header>
  {body}
  <footer class="site-footer">
    <div class="footer-inner">
      <strong>財團法人氣機導引文化教育基金會</strong>
      <p>10046 台北市中正區博愛路 25 號 5 樓</p>
      <p>電話：<span>02-23111166</span>　傳真：<span>02-23757878</span></p>
      <p>電子信箱 <a href="mailto:chiji.taoyin@msa.hinet.net">chiji.taoyin@msa.hinet.net</a></p>
      <p class="footer-copy">© QIJI-DAOYIN. All Rights Reserved.</p>
    </div>
  </footer>
</body>
</html>"""


def write_page(path, content):
    path.mkdir(parents=True, exist_ok=True)
    (path / "index.html").write_text(content, encoding="utf-8")


def copy_homepage():
    html_text = (ROOT / "public" / "prototype.html").read_text(encoding="utf-8")
    html_text = html_text.replace("../src/styles/global.css", "/styles/global.css?v=homepage-locked-20260611")
    html_text = html_text.replace("./assets/", "/assets/")
    html_text = html_text.replace("./prototype.html", "/")
    html_text = html_text.replace("./topics.html", "/topics/")
    html_text = html_text.replace("./archive.html", "/archive/")
    (DIST / "index.html").write_text(html_text, encoding="utf-8")


def build_articles():
    data = json.loads(EXTRACTED.read_text(encoding="utf-8"))
    articles = []
    for item in data["articles"]:
        category, title, author = header(item)
        articles.append({
            "source_id": item["id"],
            "source_url": item["sourceUrl"],
            "slug": SLUG_MAP[item["id"]],
            "category": category,
            "menu_category": menu_category(category),
            "title": title,
            "author": author,
            "date": "2026.05.10",
            "issue": "第243期 / 2026.05電子報",
            "read_time": read_time(item),
            "excerpt": excerpt(item),
            "image": image_path(item),
            "image_caption": item.get("caption") or "圖片來源 / WIX",
            "sections": sections_for(item),
            "tags": TAG_MAP[item["id"]],
        })
    return articles


def article_page(article, articles):
    current = articles.index(article)
    prev_article = articles[current - 1]
    next_article = articles[(current + 1) % len(articles)]
    groups = []
    for item in articles:
        group = next((entry for entry in groups if entry["category"] == item["menu_category"]), None)
        if group:
            group["items"].append(item)
        else:
            groups.append({"category": item["menu_category"], "items": [item]})
    menu = "".join(
        '<div class="article-issue-group">'
        f'<span class="article-issue-group-title">{h(group["category"])}</span>'
        + "".join(
            f'<a href="/articles/{h(item["slug"])}/" class="{"is-current" if item["slug"] == article["slug"] else ""}">{h(item["title"])}</a>'
            for item in group["items"]
        )
        + "</div>"
        for group in groups
    )
    tags = "".join(
        f'<a href="/tags/{h(TAG_SLUGS[tag])}/">{h(tag)}</a>'
        for tag in article["tags"]
    )
    sections = []
    for index, section in enumerate(article["sections"], 1):
        heading = f'<h2>{h(section["heading"])}</h2>' if section.get("heading") else ""
        paragraphs = "".join(f"<p>{h(paragraph)}</p>" for paragraph in section.get("paragraphs", []))
        sections.append(f'<section id="section-{index}">{heading}{paragraphs}</section>')
    body = f"""
<main class="article-page">
  <article>
    <header class="article-hero">
      <div class="article-hero-grid">
        <div class="article-hero-copy">
          <p class="meta-line"><span>{h(article["category"])}</span><span>{h(article["issue"])}</span><span>{h(article["read_time"])}</span></p>
          <h1 class="title-fixed" aria-label="{h(article["title"])}">{title_markup(article["title"])}</h1>
          <p class="article-byline"><span>{h(article["author"])}</span><time datetime="{h(article["date"])}">{h(article["date"])}</time></p>
        </div>
        <figure class="article-cover">
          <img src="{h(article["image"])}" alt="">
          <figcaption>{h(article["image_caption"])}</figcaption>
        </figure>
      </div>
    </header>
    <div class="article-shell">
      <aside class="article-sidebar" aria-label="文章導覽">
        <nav class="article-sidebar-block article-issue-menu" aria-label="本期電子報目錄"><strong>目錄</strong>{menu}</nav>
        <div class="article-sidebar-block"><strong>主題分類</strong><div class="article-tag-list">{tags}</div></div>
      </aside>
      <div class="article-main">
        <div class="article-tools" aria-label="閱讀設定">
          <span>字級</span>
          <div class="font-size-control" role="group" aria-label="選擇文章字級">
            <button type="button" data-font-size="small">小</button>
            <button type="button" data-font-size="medium" class="is-active">中</button>
            <button type="button" data-font-size="large">大</button>
          </div>
        </div>
        <div class="article-body" data-article-body data-font-size="medium">{''.join(sections)}</div>
      </div>
    </div>
  </article>
  <nav class="article-pager" aria-label="上一篇與下一篇">
    <a href="/articles/{h(prev_article["slug"])}/"><span>上一篇</span><strong>{h(prev_article["title"])}</strong></a>
    <a href="/articles/{h(next_article["slug"])}/"><span>下一篇</span><strong>{h(next_article["title"])}</strong></a>
  </nav>
</main>
<script>
  const body = document.querySelector("[data-article-body]");
  const controls = Array.from(document.querySelectorAll("[data-font-size]"));
  const key = "qiji-article-font-size";
  const applySize = (size) => {{
    if (!body) return;
    body.setAttribute("data-font-size", size);
    controls.forEach((control) => {{
      const isActive = control.getAttribute("data-font-size") === size;
      control.classList.toggle("is-active", isActive);
      control.setAttribute("aria-pressed", String(isActive));
    }});
    window.localStorage.setItem(key, size);
  }};
  const savedSize = window.localStorage.getItem(key);
  applySize(["small", "medium", "large"].includes(savedSize) ? savedSize : "medium");
  controls.forEach((control) => control.addEventListener("click", () => applySize(control.getAttribute("data-font-size") || "medium")));
</script>"""
    return layout(article["title"], body)


def index_page(articles):
    cards = "".join(
        f"""<article class="issue-card" id="article-{h(article["slug"])}">
          <a href="/articles/{h(article["slug"])}/">
            <img src="{h(article["image"])}" alt="">
            <p class="meta-line"><span>{h(article["category"])}</span><span>{h(article["author"])}</span></p>
            <h4>{h(article["title"])}</h4>
            <p class="read-more">閱讀全文</p>
          </a>
        </article>"""
        for article in articles
    )
    body = f"""
<main>
  <section class="headline-stage" id="latest" aria-labelledby="hero-title">
    <article class="hero-story is-active">
      <img src="{h(articles[0]["image"])}" alt="">
      <div class="hero-overlay"></div>
      <div class="hero-content">
        <p class="meta-line"><span>第243期</span><span>電子報</span></p>
        <h1 id="hero-title"><a class="hero-title-link" href="/articles/{h(articles[0]["slug"])}/">{h(articles[0]["title"])}</a></h1>
        <p class="byline">{h(articles[0]["author"])} · {h(articles[0]["date"])}</p>
      </div>
    </article>
  </section>
  <section class="content-block newest-post" id="newest" aria-labelledby="newest-title">
    <div class="block-title"><h2 id="newest-title">本期文章</h2></div>
    <div class="issue-card-grid">{cards}</div>
  </section>
</main>"""
    return layout("氣機導引電子報", body)


def topics_page(articles):
    tag_counts = {tag: sum(tag in article["tags"] for article in articles) for tag in TAG_SLUGS}
    cards = "".join(
        f'<a href="/tags/{h(TAG_SLUGS[tag])}/"><strong>#{h(tag)}</strong><span>{h(TAG_DESCRIPTIONS[tag])}</span><em>{count} 篇文章</em></a>'
        for tag, count in tag_counts.items()
        if count
    )
    body = f"""
<main>
  <section class="tag-page-hero"><a href="/">← 回首頁</a><h1>依主題瀏覽</h1><p>用文章主題快速找到同一類修煉筆記、身體經驗與道德經體證。</p></section>
  <section class="content-block"><div class="block-title"><h2>TOPICS</h2></div><div class="topic-grid">{cards}</div></section>
</main>"""
    return layout("依主題瀏覽", body)


def tag_page(tag, articles):
    tag_articles = [article for article in articles if tag in article["tags"]]
    rows = "".join(
        f"""<article class="tag-result-card"><a href="/articles/{h(article["slug"])}/">
          <img src="{h(article["image"])}" alt="">
          <div><p class="meta-line"><span>{h(article["category"])}</span><span>{h(article["date"])}</span></p><h2>{h(article["title"])}</h2><p>{h(article["excerpt"])}</p><p class="byline">{h(article["author"])}</p></div>
        </a></article>"""
        for article in tag_articles
    )
    body = f"""
<main>
  <section class="tag-page-hero"><a href="/topics/">← 依主題瀏覽</a><h1>#{h(tag)}</h1><p>{h(TAG_DESCRIPTIONS[tag])}</p></section>
  <section class="content-block"><div class="block-title"><h2>文章列表</h2></div><div class="tag-results">{rows}</div></section>
</main>"""
    return layout(f"#{tag}", body)


def archive_page():
    body = """
<main>
  <section class="tag-page-hero"><a href="/">← 回首頁</a><h1>歷史期數</h1><p>瀏覽各期電子報與官方來源頁。</p></section>
  <section class="content-block archive-page"><div class="block-title"><h2>ISSUES</h2></div><div class="archive-grid">
    <a href="/#newest"><strong>五月電子報</strong><span>第243期</span><em>查看內容</em></a>
    <a href="https://www.qiji.org.tw/5%E6%9C%88%E9%9B%BB%E5%AD%90%E5%A0%B1"><strong>官方 5 月電子報</strong><span>來源頁</span><em>查看內容</em></a>
  </div></section>
</main>"""
    return layout("歷史期數", body)


def main():
    articles = build_articles()
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    shutil.copytree(ROOT / "public" / "assets", DIST / "assets")
    (DIST / "styles").mkdir()
    shutil.copy2(ROOT / "src" / "styles" / "global.css", DIST / "styles" / "global.css")
    copy_homepage()
    write_page(DIST / "topics", topics_page(articles))
    write_page(DIST / "archive", archive_page())
    for article in articles:
        write_page(DIST / "articles" / article["slug"], article_page(article, articles))
    for tag, slug in TAG_SLUGS.items():
        if any(tag in article["tags"] for article in articles):
            write_page(DIST / "tags" / slug, tag_page(tag, articles))
    print(f"Built {len(articles)} articles into {DIST}")


if __name__ == "__main__":
    main()
