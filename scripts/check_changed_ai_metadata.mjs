import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { pathToFileURL } from "node:url";

const compactText = (value) => String(value || "").replace(/\s+/g, " ").trim();

export const articleText = (article, maxLength = 20000) => {
  const blocks = Array.isArray(article.contentBlocks)
    ? article.contentBlocks.map((block) => block.text || block.caption || "")
    : [];
  const sections = Array.isArray(article.sections)
    ? article.sections.flatMap((section) => [section.heading, ...(section.paragraphs || [])])
    : [];
  return compactText([article.excerpt, article.lede, ...blocks, ...sections].filter(Boolean).join("\n"))
    .slice(0, maxLength);
};

export const contentHashFor = (article) => {
  const payload = {
    slug: article.slug,
    sourceId: article.sourceId,
    issueId: article.issueId,
    title: article.title,
    category: article.category,
    author: article.author,
    date: article.date,
    text: articleText(article)
  };
  return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex");
};

const sourceKeyFor = (article) =>
  [article.issueId, article.sourceId, article.slug].filter(Boolean).join(":");

const fileStem = (value = "") =>
  path.basename(String(value), path.extname(String(value))).trim();

const normalizeSourceId = (value = "") =>
  String(value).normalize("NFKC").replace(/\s+/g, "").toLowerCase();

const changedFileKey = (file) =>
  `${file.issueId || ""}:${file.fileName || file.relativePath || file.path || ""}`;

const articleMatchesChangedFile = (article, file) => {
  if (!article?.issueId || !file?.issueId || article.issueId !== file.issueId) return false;
  const stem = normalizeSourceId(fileStem(file.fileName || file.relativePath || file.path || ""));
  const sourceId = normalizeSourceId(article.sourceId || "");
  return Boolean(sourceId && stem.startsWith(sourceId));
};

export const validateChangedMetadata = ({ articles, changedFiles, metadata, keywordLabels }) => {
  const activeFiles = (changedFiles || []).filter(
    (file) => file?.status === "new" || file?.status === "updated"
  );
  const issues = [];
  const candidates = [];
  const seenSlugs = new Set();

  for (const file of activeFiles) {
    const article = (articles || []).find((candidate) => articleMatchesChangedFile(candidate, file));
    if (!article) {
      issues.push({ target: changedFileKey(file), missing: ["對應文章資料"] });
      continue;
    }
    if (!seenSlugs.has(article.slug)) {
      candidates.push(article);
      seenSlugs.add(article.slug);
    }
  }

  const allowedKeywords = new Set(keywordLabels || []);
  for (const article of candidates) {
    const item = metadata?.articles?.[article.slug];
    const missing = [];
    if (!item) {
      missing.push("AI metadata");
    } else {
      if (item.sourceKey !== sourceKeyFor(article) || item.contentHash !== contentHashFor(article)) {
        missing.push("與目前文章內容相符的 metadata");
      }
      if (!String(item.quote || "").trim()) missing.push("金句");
      if (!String(item.summary || "").trim()) missing.push("摘要");
      if (!Array.isArray(item.tags) || !item.tags.some((tag) => allowedKeywords.has(tag))) {
        missing.push("有效關鍵字");
      }
      if (!Array.isArray(item.themes) || item.themes.length === 0) missing.push("核心主題");
    }
    if (missing.length) issues.push({ target: article.slug, missing });
  }

  return { candidates, issues };
};

const readJson = (filePath, fallback) => {
  if (!fs.existsSync(filePath)) return fallback;
  const raw = fs.readFileSync(filePath, "utf8").trim();
  return raw ? JSON.parse(raw) : fallback;
};

const extractExportedArray = (filePath, exportName) => {
  if (!fs.existsSync(filePath)) return [];
  const source = fs.readFileSync(filePath, "utf8");
  const start = source.indexOf(`export const ${exportName} =`);
  const arrayStart = source.indexOf("[", start);
  const end = source.indexOf("] satisfies", arrayStart);
  if (start < 0 || arrayStart < 0 || end < 0) return [];
  return vm.runInNewContext(`(${source.slice(arrayStart, end + 1)})`, {}, { timeout: 5000 });
};

const mergeBySlug = (...groups) => {
  const merged = new Map();
  groups.flat().forEach((article) => {
    if (article?.slug) merged.set(article.slug, article);
  });
  return [...merged.values()];
};

export const checkProject = (root = process.cwd()) => {
  const published = extractExportedArray(
    path.join(root, "src/data/generatedArticles.ts"),
    "generatedArticles"
  );
  const drafts = extractExportedArray(
    path.join(root, "src/data/reviewDraftArticles.ts"),
    "reviewDraftArticles"
  );
  const report = readJson(path.join(root, "public/data/import-changed-files.json"), {
    changedFiles: []
  });
  const metadata = readJson(path.join(root, "src/data/aiMetadata.json"), { articles: {} });
  const vocabulary = readJson(path.join(root, "src/data/tagVocabulary.json"), { keywordTags: [] });
  return validateChangedMetadata({
    articles: mergeBySlug(published, drafts),
    changedFiles: report.changedFiles,
    metadata,
    keywordLabels: (vocabulary.keywordTags || []).map((tag) => tag.label)
  });
};

const isCli = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isCli) {
  const rootIndex = process.argv.indexOf("--root");
  const root = rootIndex >= 0 && process.argv[rootIndex + 1]
    ? path.resolve(process.argv[rootIndex + 1])
    : process.cwd();
  const { candidates, issues } = checkProject(root);

  if (issues.length) {
    console.error("AI metadata 檢查失敗，停止 push：");
    issues.forEach((issue) => console.error(`- ${issue.target}：缺少 ${issue.missing.join("、")}`));
    console.error("請先使用本機 metadata 流程補齊，再重新執行檢查。");
    process.exitCode = 1;
  } else {
    console.log(`AI metadata 檢查通過：${candidates.length} 篇新增或更新文章。`);
  }
}
