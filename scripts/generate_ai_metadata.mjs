import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = process.cwd();
const generatedArticlesPath = path.join(root, "src/data/generatedArticles.ts");
const aiMetadataPath = path.join(root, "src/data/aiMetadata.json");
const reportPath = path.join(root, "reports/ai-metadata-report.json");

const provider = process.env.AI_PROVIDER || (process.env.KIMI_API_KEY ? "kimi" : "openai");
const apiKey = process.env.KIMI_API_KEY || process.env.OPENAI_API_KEY || process.env.AI_API_KEY;
const apiBaseUrl =
  process.env.AI_API_BASE_URL ||
  (provider === "kimi" ? "https://api.moonshot.ai/v1" : "https://api.openai.com/v1");
const model =
  process.env.AI_MODEL ||
  process.env.KIMI_MODEL ||
  process.env.OPENAI_MODEL ||
  (provider === "kimi" ? "kimi-k2.6" : "gpt-5.5");
const temperature = Number.parseFloat(
  process.env.AI_TEMPERATURE || (provider === "kimi" ? "0.6" : "0.2")
);
const targetIssue = process.env.AI_ISSUE_ID || "latest";
const limit = Number.parseInt(process.env.AI_LIMIT || "0", 10);
const force = process.env.AI_FORCE === "1" || process.env.AI_FORCE === "true";
const allowPaidApi =
  process.env.AI_ALLOW_PAID_API === "1" || process.env.AI_ALLOW_PAID_API === "true";

const readJson = (filePath, fallback) => {
  if (!fs.existsSync(filePath)) return fallback;
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) return fallback;
  return JSON.parse(raw);
};

const extractExportedArray = (source, name) => {
  const startToken = `export const ${name} =`;
  const start = source.indexOf(startToken);
  if (start < 0) throw new Error(`Cannot find ${name} in generatedArticles.ts`);

  const arrayStart = source.indexOf("[", start);
  const endToken = `] satisfies`;
  const end = source.indexOf(endToken, arrayStart);
  if (arrayStart < 0 || end < 0) throw new Error(`Cannot extract ${name} array`);

  const code = `(${source.slice(arrayStart, end + 1)})`;
  return vm.runInNewContext(code, {}, { timeout: 5000 });
};

const compactText = (value) => String(value || "").replace(/\s+/g, " ").trim();

const articleText = (article, maxLength = 6000) => {
  const blocks = Array.isArray(article.contentBlocks)
    ? article.contentBlocks.map((block) => block.text || block.caption || "")
    : [];
  const sections = Array.isArray(article.sections)
    ? article.sections.flatMap((section) => [section.heading, ...(section.paragraphs || [])])
    : [];
  return [article.excerpt, article.lede, ...blocks, ...sections]
    .filter(Boolean)
    .join("\n")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
};

const contentHashFor = (article) => {
  const payload = {
    slug: article.slug,
    sourceId: article.sourceId,
    issueId: article.issueId,
    title: article.title,
    category: article.category,
    author: article.author,
    date: article.date,
    text: articleText(article, 20000)
  };
  return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex");
};

const sourceKeyFor = (article) =>
  [article.issueId, article.sourceId, article.slug].filter(Boolean).join(":");

const parseAiJson = (text) => {
  const trimmed = text.trim().replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  const first = trimmed.indexOf("{");
  const last = trimmed.lastIndexOf("}");
  if (first < 0 || last < first) throw new Error(`AI response is not JSON: ${text.slice(0, 200)}`);
  return JSON.parse(trimmed.slice(first, last + 1));
};

const normalizeStringArray = (value, maxItems) =>
  Array.isArray(value)
    ? value.map((item) => String(item).trim()).filter(Boolean).slice(0, maxItems)
    : [];

const buildPrompt = (article) => [
  "你是氣機導引電子報的繁體中文編輯助理，請根據文章內容產生網站用 AI metadata。",
  "只回傳 JSON，不要 Markdown，不要解釋。",
  'JSON schema: {"quote":"50字以內的重點金句","tags":["2到5個中文主題標籤"],"summary":"80字以內短摘要","themes":["3到6個文章核心主題"]}',
  "",
  "規則：",
  "1. quote 必須是 50 個中文字以內，適合放在首頁或文章摘要的重點金句。",
  "2. quote 可以精煉原文意思，但不可編造文章沒有的主張。",
  "3. summary 必須是 80 個中文字以內，說明本文重點，不要加入作者、日期或期數。",
  "4. tags 使用簡短中文詞，最多 5 個，不要放作者、日期、期數或文章分類本身。",
  "5. themes 可比 tags 稍具體，用來判斷相似文章。",
  "6. 若文章內容不足以判斷，quote/summary 請留空字串，tags/themes 請留空陣列。",
  "",
  `文章分類：${article.category || ""}`,
  `文章標題：${article.title || ""}`,
  `作者：${article.author || ""}`,
  "",
  "文章內容：",
  articleText(article)
].join("\n");

const requestMetadata = async (article) => {
  const prompt = [
    "You are helping a Traditional Chinese newsletter website generate review-only metadata.",
    "Return exactly one valid JSON object. Do not include Markdown, explanations, or code fences.",
    'JSON schema: {"quote":"a highlighted sentence under 50 Chinese characters","tags":["2 to 5 short Traditional Chinese topic tags"],"summary":"a concise Traditional Chinese summary under 80 Chinese characters","themes":["3 to 6 short Traditional Chinese core themes"]}',
    "",
    "Rules:",
    "1. quote must be copied or lightly compressed from the article and stay under 50 Chinese characters.",
    "2. summary must be under 80 Chinese characters and describe the article, not the website.",
    "3. tags should be reader-facing topic labels, not issue numbers, author names, or generic words.",
    "4. themes can be broader than tags, but still concise.",
    "5. Use Traditional Chinese for every value.",
    "6. If the article is too short, still return valid JSON with your best concise suggestions.",
    "",
    `Category: ${article.category || ""}`,
    `Title: ${article.title || ""}`,
    `Author: ${article.author || ""}`,
    "",
    "Article text:",
    articleText(article)
  ].join("\n");

  const requestBody = {
    model,
    messages: [
      {
        role: "system",
        content:
          'Return only valid JSON with keys "quote", "tags", "summary", and "themes". All values must be Traditional Chinese.'
      },
      { role: "user", content: prompt }
    ],
    temperature,
    max_tokens: 700
  };

  if (provider === "kimi") {
    requestBody.response_format = { type: "json_object" };
    requestBody.thinking = { type: "disabled" };
  }

  const response = await fetch(`${apiBaseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(requestBody)
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`AI API failed for ${article.slug}: ${response.status} ${errorText}`);
  }

  const data = await response.json();
  const choice = data.choices?.[0];
  const text = choice?.message?.content || "";
  if (!text.trim()) {
    throw new Error(
      `AI response is empty: finish_reason=${choice?.finish_reason || "unknown"} raw=${JSON.stringify(data).slice(0, 500)}`
    );
  }
  const parsed = parseAiJson(text);

  return {
    quote: String(parsed.quote || "").trim().slice(0, 50),
    tags: normalizeStringArray(parsed.tags, 5),
    summary: String(parsed.summary || "").trim().slice(0, 80),
    themes: normalizeStringArray(parsed.themes, 6)
  };
};

const searchableTokensFor = (article, meta) =>
  new Set(
    [
      article.category,
      ...(article.tags || []),
      ...(meta?.tags || []),
      ...(meta?.themes || [])
    ]
      .map(compactText)
      .filter(Boolean)
  );

const scoreSimilarity = (leftArticle, leftMeta, rightArticle, rightMeta) => {
  if (leftArticle.slug === rightArticle.slug) return -1;

  const leftTokens = searchableTokensFor(leftArticle, leftMeta);
  const rightTokens = searchableTokensFor(rightArticle, rightMeta);
  let score = 0;

  leftTokens.forEach((token) => {
    if (rightTokens.has(token)) score += 4;
  });

  if (leftArticle.category === rightArticle.category) score += 5;
  if (leftArticle.issueId === rightArticle.issueId) score += 2;

  const leftTitle = compactText(leftArticle.title);
  const rightTitle = compactText(rightArticle.title);
  if (leftTitle && rightTitle && (leftTitle.includes(rightTitle) || rightTitle.includes(leftTitle))) {
    score += 2;
  }

  return score;
};

const updateSimilarCandidates = (metadata, articles, targetSlugs) => {
  const articleBySlug = new Map(articles.map((article) => [article.slug, article]));

  targetSlugs.forEach((slug) => {
    const article = articleBySlug.get(slug);
    const meta = metadata.articles?.[slug];
    if (!article || !meta) return;

    const candidates = articles
      .map((candidate) => ({
        slug: candidate.slug,
        score: scoreSimilarity(article, meta, candidate, metadata.articles?.[candidate.slug])
      }))
      .filter((candidate) => candidate.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map((candidate) => candidate.slug);

    meta.similarCandidates = candidates;
  });
};

const normalizeMetadata = (metadata) => ({
  version: metadata.version || 2,
  generatedAt: metadata.generatedAt || "",
  quotes: metadata.quotes || {},
  tags: metadata.tags || {},
  summaries: metadata.summaries || {},
  themes: metadata.themes || {},
  similar: metadata.similar || {},
  articles: metadata.articles || {}
});

const syncCompatibilityMaps = (metadata, slug, item) => {
  if (item.quote) metadata.quotes[slug] = item.quote;
  if (item.tags?.length) metadata.tags[slug] = item.tags;
  if (item.summary) metadata.summaries[slug] = item.summary;
  if (item.themes?.length) metadata.themes[slug] = item.themes;
  if (item.similarCandidates?.length) metadata.similar[slug] = item.similarCandidates;
};

const main = async () => {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });

  const source = fs.readFileSync(generatedArticlesPath, "utf8");
  const articles = extractExportedArray(source, "generatedArticles");
  const issues = extractExportedArray(source, "generatedIssues");
  const latestIssueId = issues[0]?.id;
  const issueId = targetIssue === "latest" ? latestIssueId : targetIssue;
  const candidates = articles
    .filter((article) => !issueId || article.issueId === issueId)
    .slice(0, limit > 0 ? limit : undefined);

  const metadata = normalizeMetadata(readJson(aiMetadataPath, {}));
  const results = [];
  const touchedSlugs = new Set(candidates.map((article) => article.slug));

  if (!apiKey) {
    fs.writeFileSync(
      reportPath,
      JSON.stringify(
        {
          status: "skipped",
          reason: "KIMI_API_KEY, OPENAI_API_KEY, or AI_API_KEY is not set",
          generatedAt: new Date().toISOString(),
          issueId,
          count: candidates.length
        },
        null,
        2
      ),
      "utf8"
    );
    console.log("No AI API key is set; skipped AI metadata generation.");
    return;
  }

  if (!allowPaidApi) {
    for (const article of candidates) {
      const existing = metadata.articles[article.slug];
      if (existing) {
        syncCompatibilityMaps(metadata, article.slug, existing);
        results.push({ slug: article.slug, title: article.title, status: "cache-hit" });
      } else {
        results.push({
          slug: article.slug,
          title: article.title,
          status: "skipped",
          reason: "AI_ALLOW_PAID_API is not true"
        });
      }
    }

    const generatedAt = new Date().toISOString();
    fs.writeFileSync(
      reportPath,
      JSON.stringify(
        {
          status: "skipped",
          reason: "AI_ALLOW_PAID_API is not true; existing metadata was reused only",
          generatedAt,
          provider,
          apiBaseUrl,
          issueId,
          model,
          count: results.length,
          cacheHits: results.filter((result) => result.status === "cache-hit").length,
          skipped: results.filter((result) => result.status === "skipped").length,
          results
        },
        null,
        2
      ),
      "utf8"
    );
    console.log("AI_ALLOW_PAID_API is not true; skipped paid AI calls and reused existing metadata.");
    return;
  }

  for (const article of candidates) {
    const slug = article.slug;
    const sourceKey = sourceKeyFor(article);
    const contentHash = contentHashFor(article);
    const existing = metadata.articles[slug];
    const cacheHit =
      existing &&
      !force &&
      existing.sourceKey === sourceKey &&
      existing.contentHash === contentHash &&
      existing.quote &&
      existing.tags?.length &&
      existing.summary &&
      existing.themes?.length;

    if (cacheHit) {
      syncCompatibilityMaps(metadata, slug, existing);
      results.push({ slug, title: article.title, status: "cache-hit" });
      continue;
    }

    try {
      const generated = await requestMetadata(article);
      metadata.articles[slug] = {
        ...existing,
        ...generated,
        provider,
        model,
        apiBaseUrl,
        sourceKey,
        contentHash,
        generatedAt: new Date().toISOString()
      };
      syncCompatibilityMaps(metadata, slug, metadata.articles[slug]);
      results.push({ slug, title: article.title, status: "generated", ...generated });
    } catch (error) {
      results.push({ slug, title: article.title, status: "error", error: error.message });
    }
  }

  updateSimilarCandidates(metadata, articles, touchedSlugs);
  touchedSlugs.forEach((slug) => syncCompatibilityMaps(metadata, slug, metadata.articles[slug] || {}));
  metadata.generatedAt = new Date().toISOString();

  fs.writeFileSync(aiMetadataPath, JSON.stringify(metadata, null, 2), "utf8");
  fs.writeFileSync(
    reportPath,
    JSON.stringify(
      {
        status: "done",
        generatedAt: metadata.generatedAt,
        provider,
        apiBaseUrl,
        issueId,
        model,
        count: results.length,
        cacheHits: results.filter((result) => result.status === "cache-hit").length,
        generated: results.filter((result) => result.status === "generated").length,
        errors: results.filter((result) => result.status === "error").length,
        results
      },
      null,
      2
    ),
    "utf8"
  );
  console.log(`AI metadata completed: ${results.length} article(s), provider=${provider}, issue=${issueId}`);
};

await main();

