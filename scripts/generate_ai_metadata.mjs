import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = process.cwd();
const generatedArticlesPath = path.join(root, "src/data/generatedArticles.ts");
const reviewDraftArticlesPath = path.join(root, "src/data/reviewDraftArticles.ts");
const aiMetadataPath = path.join(root, "src/data/aiMetadata.json");
const aiFeedbackExamplesPath = path.join(root, "src/data/aiFeedbackExamples.json");
const tagVocabularyPath = path.join(root, "src/data/tagVocabulary.json");
const reportPath = path.join(root, "reports/ai-metadata-report.json");
const importChangedReportPath = path.join(root, "public/data/import-changed-files.json");
const defaultSourceRoot = "H:\\我的雲端硬碟\\氣機導引\\電子報新版網頁\\各期電子報";
const aiSourceRoot = process.env.AI_SOURCE_ROOT || defaultSourceRoot;
const aiWriteSidecar =
  process.env.AI_WRITE_SIDECAR === "1" || process.env.AI_WRITE_SIDECAR === "true";

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
const aiRequestTimeoutMs = Number.parseInt(process.env.AI_REQUEST_TIMEOUT_MS || "180000", 10);
const useOllamaNative =
  provider === "ollama" ||
  provider === "qwen" ||
  /(^|\/\/)(127\.0\.0\.1|localhost):11434(\/|$)/.test(apiBaseUrl);
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

const tagVocabulary = readJson(tagVocabularyPath, {});
const aiFeedbackExamplesData = readJson(aiFeedbackExamplesPath, { examples: [] });
const aiFeedbackExamples = Array.isArray(aiFeedbackExamplesData.examples)
  ? aiFeedbackExamplesData.examples
  : [];
const allowedAiTags = [
  ...(tagVocabulary.categoryTags || []),
  ...(tagVocabulary.keywordTags || []).map((rule) => rule.label)
].filter(Boolean);
const compactTagLabel = (value = "") =>
  String(value)
    .normalize("NFKC")
    .replace(/[\s　·・．.／/｜|,，、:：;；「」『』()（）［\]\[\-—–_]+/g, "")
    .trim()
    .toLowerCase();
const allowedAiTagMap = new Map(allowedAiTags.map((tag) => [compactTagLabel(tag), tag]));
const allowedAiTagText = allowedAiTags.join("、");

const extractExportedArray = (source, name, sourceLabel = "source file") => {
  const startToken = `export const ${name} =`;
  const start = source.indexOf(startToken);
  if (start < 0) throw new Error(`Cannot find ${name} in ${sourceLabel}`);

  const arrayStart = source.indexOf("[", start);
  const endToken = `] satisfies`;
  const end = source.indexOf(endToken, arrayStart);
  if (arrayStart < 0 || end < 0) throw new Error(`Cannot extract ${name} array from ${sourceLabel}`);

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

const feedbackExamplesFor = (article, maxExamples = 4) =>
  aiFeedbackExamples
    .filter((example) => example?.corrected && example.slug !== article.slug)
    .map((example) => ({
      example,
      score:
        (example.category && article.category && example.category === article.category ? 2 : 0) +
        (example.corrected?.quote ? 1 : 0) +
        (example.corrected?.summary ? 1 : 0) +
        (Array.isArray(example.corrected?.tags) && example.corrected.tags.length ? 1 : 0)
    }))
    .sort((a, b) => b.score - a.score)
    .slice(0, maxExamples)
    .map(({ example }) => ({
      category: example.category || "",
      title: example.title || "",
      original: example.original || {},
      humanCorrection: example.corrected || {},
      reason: example.reason || ""
    }));

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

const fileStem = (value = "") =>
  path.basename(String(value), path.extname(String(value))).trim();

const normalizeSourceId = (value = "") =>
  String(value)
    .normalize("NFKC")
    .replace(/\s+/g, "")
    .toLowerCase();

const readArticleBundle = (filePath, articleExportName, issueExportName) => {
  if (!fs.existsSync(filePath)) return { articles: [], issues: [] };
  const source = fs.readFileSync(filePath, "utf8");
  return {
    articles: extractExportedArray(source, articleExportName, path.relative(root, filePath)),
    issues: extractExportedArray(source, issueExportName, path.relative(root, filePath))
  };
};

const mergeArticlesBySlug = (...articleGroups) => {
  const merged = new Map();
  articleGroups.flat().forEach((article) => {
    if (!article?.slug) return;
    merged.set(article.slug, article);
  });
  return Array.from(merged.values());
};

const changedFilesForAi = () => {
  const report = readJson(importChangedReportPath, { changedFiles: [] });
  return Array.isArray(report.changedFiles)
    ? report.changedFiles.filter((file) => file?.status === "new" || file?.status === "updated")
    : [];
};

const articleMatchesChangedFile = (article, file) => {
  if (!article?.issueId || !file?.issueId || article.issueId !== file.issueId) return false;
  const stem = normalizeSourceId(fileStem(file.fileName || file.relativePath || file.path || ""));
  const sourceId = normalizeSourceId(article.sourceId || "");
  return Boolean(sourceId && stem.startsWith(sourceId));
};

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

const normalizeAllowedTags = (value, maxItems) => {
  const tags = [];
  for (const item of normalizeStringArray(value, maxItems * 2)) {
    const tag = allowedAiTagMap.get(compactTagLabel(item));
    if (!tag || tags.includes(tag)) continue;
    tags.push(tag);
    if (tags.length >= maxItems) break;
  }
  return tags;
};

const cleanString = (value = "") => String(value || "").trim();

const sourceIndexes = new Map();

const walkFiles = (dirPath, files = []) => {
  if (!fs.existsSync(dirPath)) return files;
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const entryPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      walkFiles(entryPath, files);
    } else {
      files.push(entryPath);
    }
  }
  return files;
};

const sourceRootForIssue = (issueId) => {
  if (!aiSourceRoot || !fs.existsSync(aiSourceRoot)) return "";
  const issueDir = path.join(aiSourceRoot, issueId);
  return fs.existsSync(issueDir) ? issueDir : aiSourceRoot;
};

const sourceIndexForIssue = (issueId) => {
  if (sourceIndexes.has(issueId)) return sourceIndexes.get(issueId);
  const issueRoot = sourceRootForIssue(issueId);
  const docxFiles = issueRoot
    ? walkFiles(issueRoot).filter((filePath) => path.extname(filePath).toLowerCase() === ".docx")
    : [];
  const index = { issueRoot, docxFiles };
  sourceIndexes.set(issueId, index);
  return index;
};

const sourceDocxForArticle = (article) => {
  const sourceId = normalizeSourceId(article.sourceId || "");
  if (!sourceId || !article.issueId) return "";
  const { docxFiles } = sourceIndexForIssue(article.issueId);
  return (
    docxFiles.find((filePath) => normalizeSourceId(fileStem(filePath)).startsWith(sourceId)) || ""
  );
};

const sidecarCandidatesForArticle = (article) => {
  const sourceDocx = sourceDocxForArticle(article);
  const candidates = [];
  if (sourceDocx) {
    const dirPath = path.dirname(sourceDocx);
    const stem = fileStem(sourceDocx);
    candidates.push(
      path.join(dirPath, `${stem}.metadata.json`),
      path.join(dirPath, `${stem}.ai.json`)
    );
    if (article.sourceId) candidates.push(path.join(dirPath, `${article.sourceId}.metadata.json`));
    if (article.slug) candidates.push(path.join(dirPath, `${article.slug}.metadata.json`));
  }
  const { issueRoot } = sourceIndexForIssue(article.issueId || "");
  if (issueRoot) {
    if (article.sourceId) candidates.push(path.join(issueRoot, `${article.sourceId}.metadata.json`));
    if (article.slug) candidates.push(path.join(issueRoot, `${article.slug}.metadata.json`));
  }
  return [...new Set(candidates)];
};

const normalizeSidecarMetadata = (data) => {
  const quote = cleanString(data.quote ?? data.aiQuote ?? data.goldQuote ?? "");
  const summary = cleanString(data.summary ?? data.aiSummary ?? "");
  const tags = normalizeAllowedTags(data.tags ?? data.keywordTags ?? data.keywords ?? [], 5);
  const themes = normalizeStringArray(data.themes ?? data.aiThemes ?? tags, 6);
  if (!quote || !summary || !tags.length) return null;
  return { quote, summary, tags, themes };
};

const sidecarMetadataForArticle = (article) => {
  for (const filePath of sidecarCandidatesForArticle(article)) {
    if (!fs.existsSync(filePath)) continue;
    const parsed = normalizeSidecarMetadata(readJson(filePath, {}));
    if (parsed) return { ...parsed, sidecarPath: path.relative(root, filePath) };
  }
  return null;
};

const writeSidecarMetadataForArticle = (article, item) => {
  if (!aiWriteSidecar) return "";
  const sourceDocx = sourceDocxForArticle(article);
  if (!sourceDocx) return "";
  const sidecarPath = path.join(path.dirname(sourceDocx), `${fileStem(sourceDocx)}.metadata.json`);
  fs.writeFileSync(
    sidecarPath,
    JSON.stringify(
      {
        slug: article.slug,
        issueId: article.issueId,
        sourceId: article.sourceId,
        title: article.title,
        quote: item.quote || "",
        summary: item.summary || "",
        tags: item.tags || [],
        themes: item.themes || [],
        updatedAt: new Date().toISOString()
      },
      null,
      2
    ),
    "utf8"
  );
  return path.relative(root, sidecarPath);
};

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
  const feedbackExamples = feedbackExamplesFor(article);
  const prompt = [
    "You are helping a Traditional Chinese newsletter website generate review-only metadata.",
    "Return exactly one valid JSON object. Do not include Markdown, explanations, or code fences.",
    'JSON schema: {"quote":"a highlighted sentence under 50 Chinese characters","tags":["0 to 5 labels selected from the allowed tag list"],"summary":"a concise Traditional Chinese summary under 80 Chinese characters","themes":["3 to 6 short Traditional Chinese core themes"]}',
    "",
    "Rules:",
    "1. quote must be copied or lightly compressed from the article and stay under 50 Chinese characters.",
    "2. summary must be under 80 Chinese characters and describe the article, not the website.",
    "3. tags must only use exact labels from the allowed tag list. Do not invent new tags.",
    "4. themes can be broader than tags, but still concise.",
    "5. Use Traditional Chinese for every value.",
    "6. If the article is too short, still return valid JSON with your best concise suggestions.",
    `Allowed tag list: ${allowedAiTagText || "none"}`,
    "",
    feedbackExamples.length
      ? [
          "Human correction examples from this website. Treat these as project-specific style guidance, not as model training:",
          JSON.stringify(feedbackExamples, null, 2),
          ""
        ].join("\n")
      : "",
    `Category: ${article.category || ""}`,
    `Title: ${article.title || ""}`,
    `Author: ${article.author || ""}`,
    "",
    "Article text:",
    articleText(article, useOllamaNative ? 900 : 6000)
  ].join("\n");

  const requestMessages = [
    {
      role: "system",
      content:
        'Return only valid JSON with keys "quote", "tags", "summary", and "themes". Tags must be exact labels from the allowed list.'
    },
    { role: "user", content: prompt }
  ];

  const requestWithTimeout = async (url, options) => {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), aiRequestTimeoutMs);
    try {
      return await fetch(url, { ...options, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
  };

  if (useOllamaNative) {
    const ollamaBaseUrl = apiBaseUrl.replace(/\/v1\/?$/, "").replace(/\/$/, "");
    const response = await requestWithTimeout(`${ollamaBaseUrl}/api/chat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model,
        messages: requestMessages,
        stream: false,
        think: false,
        format: "json",
        options: {
          temperature,
          num_ctx: 4096,
          num_predict: 360
        }
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`AI API failed for ${article.slug}: ${response.status} ${errorText}`);
    }

    const data = await response.json();
    const text = data.message?.content || data.response || "";
    if (!text.trim()) {
      throw new Error(
        `AI response is empty: done_reason=${data.done_reason || "unknown"} raw=${JSON.stringify(data).slice(0, 500)}`
      );
    }
    const parsed = parseAiJson(text);

    return {
      quote: String(parsed.quote || "").trim().slice(0, 50),
      tags: normalizeAllowedTags(parsed.tags, 5),
      summary: String(parsed.summary || "").trim().slice(0, 80),
      themes: normalizeStringArray(parsed.themes, 6)
    };
  }

  const requestBody = {
    model,
    messages: requestMessages,
    temperature,
    max_tokens: 700
  };

  if (provider === "kimi") {
    requestBody.response_format = { type: "json_object" };
    requestBody.thinking = { type: "disabled" };
  }

  const response = await requestWithTimeout(`${apiBaseUrl.replace(/\/$/, "")}/chat/completions`, {
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
    tags: normalizeAllowedTags(parsed.tags, 5),
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

const writeMetadataProgress = (metadata, results, issueId) => {
  metadata.generatedAt = new Date().toISOString();
  fs.writeFileSync(aiMetadataPath, JSON.stringify(metadata, null, 2), "utf8");
  fs.writeFileSync(
    reportPath,
    JSON.stringify(
      {
        status: "running",
        generatedAt: metadata.generatedAt,
        provider,
        apiBaseUrl,
        issueId,
        model,
        count: results.length,
        cacheHits: results.filter((result) => result.status === "cache-hit").length,
        sidecar: results.filter((result) => result.status === "sidecar").length,
        generated: results.filter((result) => result.status === "generated").length,
        errors: results.filter((result) => result.status === "error").length,
        results
      },
      null,
      2
    ),
    "utf8"
  );
};

const cacheHitForArticle = (existing, sourceKey, contentHash) =>
  existing &&
  !force &&
  existing.sourceKey === sourceKey &&
  existing.contentHash === contentHash &&
  existing.quote &&
  existing.tags?.length &&
  existing.summary &&
  existing.themes?.length;

const useSidecarMetadata = (metadata, article, existing, sourceKey, contentHash, sidecar) => {
  metadata.articles[article.slug] = {
    ...existing,
    ...sidecar,
    provider: "sidecar",
    model: "sidecar",
    apiBaseUrl: "",
    sourceKey,
    contentHash,
    generatedAt: new Date().toISOString()
  };
  syncCompatibilityMaps(metadata, article.slug, metadata.articles[article.slug]);
};

const reuseMetadataWithoutApi = (metadata, candidates, issueId, reason) => {
  const results = [];
  let changed = false;

  for (const article of candidates) {
    const slug = article.slug;
    const sourceKey = sourceKeyFor(article);
    const contentHash = contentHashFor(article);
    const existing = metadata.articles[slug];

    if (cacheHitForArticle(existing, sourceKey, contentHash)) {
      syncCompatibilityMaps(metadata, slug, existing);
      results.push({ slug, title: article.title, status: "cache-hit" });
      continue;
    }

    const sidecar = sidecarMetadataForArticle(article);
    if (sidecar) {
      useSidecarMetadata(metadata, article, existing, sourceKey, contentHash, sidecar);
      changed = true;
      results.push({ slug, title: article.title, status: "sidecar", sidecarPath: sidecar.sidecarPath });
      continue;
    }

    if (existing) {
      syncCompatibilityMaps(metadata, slug, existing);
    }
    results.push({ slug, title: article.title, status: "skipped", reason });
  }

  const generatedAt = new Date().toISOString();
  metadata.generatedAt = generatedAt;
  if (changed) {
    fs.writeFileSync(aiMetadataPath, JSON.stringify(metadata, null, 2), "utf8");
  }
  fs.writeFileSync(
    reportPath,
    JSON.stringify(
      {
        status: "skipped",
        reason,
        generatedAt,
        provider,
        apiBaseUrl,
        issueId,
        model,
        count: results.length,
        cacheHits: results.filter((result) => result.status === "cache-hit").length,
        sidecar: results.filter((result) => result.status === "sidecar").length,
        skipped: results.filter((result) => result.status === "skipped").length,
        results
      },
      null,
      2
    ),
    "utf8"
  );

  console.log(`${reason}; reused cache/sidecar metadata where available.`);
};

const main = async () => {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });

  const publishedBundle = readArticleBundle(
    generatedArticlesPath,
    "generatedArticles",
    "generatedIssues"
  );
  const reviewBundle = readArticleBundle(
    reviewDraftArticlesPath,
    "reviewDraftArticles",
    "reviewDraftIssues"
  );
  const articles = mergeArticlesBySlug(publishedBundle.articles, reviewBundle.articles);
  const issues = [...reviewBundle.issues, ...publishedBundle.issues];
  const latestIssueId = issues[0]?.id;
  const issueId = targetIssue === "latest" ? latestIssueId : targetIssue;
  const changedFiles = targetIssue === "changed" ? changedFilesForAi() : [];
  const candidates = articles
    .filter((article) => {
      if (targetIssue === "changed") {
        return changedFiles.some((file) => articleMatchesChangedFile(article, file));
      }
      return !issueId || article.issueId === issueId;
    })
    .slice(0, limit > 0 ? limit : undefined);

  const metadata = normalizeMetadata(readJson(aiMetadataPath, {}));
  const results = [];
  const touchedSlugs = new Set(candidates.map((article) => article.slug));

  if (!apiKey) {
    reuseMetadataWithoutApi(
      metadata,
      candidates,
      issueId,
      "KIMI_API_KEY, OPENAI_API_KEY, or AI_API_KEY is not set"
    );
    return;
  }

  if (!allowPaidApi) {
    reuseMetadataWithoutApi(
      metadata,
      candidates,
      issueId,
      "AI_ALLOW_PAID_API is not true; existing metadata and sidecar metadata were reused only"
    );
    return;
  }

  for (const article of candidates) {
    const slug = article.slug;
    const sourceKey = sourceKeyFor(article);
    const contentHash = contentHashFor(article);
    const existing = metadata.articles[slug];
    const cacheHit = cacheHitForArticle(existing, sourceKey, contentHash);

    if (cacheHit) {
      syncCompatibilityMaps(metadata, slug, existing);
      results.push({ slug, title: article.title, status: "cache-hit" });
      console.log(`[ai] cache-hit ${slug}`);
      continue;
    }

    const sidecar = sidecarMetadataForArticle(article);
    if (sidecar) {
      useSidecarMetadata(metadata, article, existing, sourceKey, contentHash, sidecar);
      results.push({ slug, title: article.title, status: "sidecar", sidecarPath: sidecar.sidecarPath });
      writeMetadataProgress(metadata, results, issueId);
      console.log(`[ai] sidecar ${slug}`);
      continue;
    }

    try {
      console.log(`[ai] generating ${slug}`);
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
      const sidecarPath = writeSidecarMetadataForArticle(article, metadata.articles[slug]);
      results.push({ slug, title: article.title, status: "generated", sidecarPath, ...generated });
      writeMetadataProgress(metadata, results, issueId);
      console.log(`[ai] generated ${slug}`);
    } catch (error) {
      results.push({ slug, title: article.title, status: "error", error: error.message });
      writeMetadataProgress(metadata, results, issueId);
      console.log(`[ai] error ${slug}: ${error.message}`);
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
        sidecar: results.filter((result) => result.status === "sidecar").length,
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

