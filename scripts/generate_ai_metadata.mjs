import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root = process.cwd();
const generatedArticlesPath = path.join(root, "src/data/generatedArticles.ts");
const aiMetadataPath = path.join(root, "src/data/aiMetadata.json");
const reportPath = path.join(root, "reports/ai-metadata-report.json");

const apiKey = process.env.OPENAI_API_KEY;
const model = process.env.OPENAI_MODEL || "gpt-5.5";
const targetIssue = process.env.AI_ISSUE_ID || "latest";
const limit = Number.parseInt(process.env.AI_LIMIT || "0", 10);
const force = process.env.AI_FORCE === "1" || process.env.AI_FORCE === "true";

const readJson = (filePath, fallback) => {
  if (!fs.existsSync(filePath)) return fallback;
  const raw = fs.readFileSync(filePath, "utf8").trim();
  if (!raw) return fallback;
  return JSON.parse(raw);
};

const normalizeOutputText = (response) => {
  if (typeof response.output_text === "string") return response.output_text;
  return (response.output || [])
    .flatMap((item) => item.content || [])
    .map((part) => part.text || "")
    .join("")
    .trim();
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

const articleText = (article) => {
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
    .slice(0, 6000);
};

const parseAiJson = (text) => {
  const trimmed = text.trim().replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  const first = trimmed.indexOf("{");
  const last = trimmed.lastIndexOf("}");
  if (first < 0 || last < first) throw new Error(`AI response is not JSON: ${text.slice(0, 200)}`);
  return JSON.parse(trimmed.slice(first, last + 1));
};

const requestMetadata = async (article) => {
  const prompt = [
    "你是氣機導引電子報的編輯助理，請根據文章內容產生網站 metadata。",
    "請只回傳有效 JSON，不要加入 Markdown 或額外說明。",
    'JSON schema: {"quote":"50字以內的重點金句","tags":["2到5個中文主題標籤"]}',
    "規則：",
    "1. quote 必須從文章精神萃取，適合放在網站首頁或文章摘要，長度必須在 50 個中文字以內。",
    "2. tags 使用精簡中文名詞，不要超過 5 個；可包含既有分類，但不要產生太細碎的標籤。",
    "3. 不要捏造文章沒有的內容，不要加入作者名、日期或期數。",
    "",
    `文章分類：${article.category || ""}`,
    `文章標題：${article.title || ""}`,
    `作者：${article.author || ""}`,
    "正文：",
    articleText(article)
  ].join("\n");

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      input: prompt,
      max_output_tokens: 500
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API failed for ${article.slug}: ${response.status} ${errorText}`);
  }

  const data = await response.json();
  const parsed = parseAiJson(normalizeOutputText(data));
  const quote = String(parsed.quote || "").trim().slice(0, 50);
  const tags = Array.isArray(parsed.tags)
    ? parsed.tags.map((tag) => String(tag).trim()).filter(Boolean).slice(0, 5)
    : [];

  return { quote, tags };
};

const main = async () => {
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });

  if (!apiKey) {
    const report = {
      status: "skipped",
      reason: "OPENAI_API_KEY is not set",
      generatedAt: new Date().toISOString()
    };
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
    console.log("OPENAI_API_KEY is not set; skipped AI metadata generation.");
    return;
  }

  const source = fs.readFileSync(generatedArticlesPath, "utf8");
  const articles = extractExportedArray(source, "generatedArticles");
  const issues = extractExportedArray(source, "generatedIssues");
  const latestIssueId = issues[0]?.id;
  const issueId = targetIssue === "latest" ? latestIssueId : targetIssue;
  const candidates = articles
    .filter((article) => !issueId || article.issueId === issueId)
    .slice(0, limit > 0 ? limit : undefined);

  const metadata = readJson(aiMetadataPath, { quotes: {}, tags: {} });
  metadata.quotes ||= {};
  metadata.tags ||= {};

  const results = [];
  for (const article of candidates) {
    const alreadyDone = metadata.quotes[article.slug] && metadata.tags[article.slug]?.length;
    if (alreadyDone && !force) {
      results.push({ slug: article.slug, title: article.title, status: "kept-existing" });
      continue;
    }

    try {
      const generated = await requestMetadata(article);
      if (generated.quote) metadata.quotes[article.slug] = generated.quote;
      if (generated.tags.length) metadata.tags[article.slug] = generated.tags;
      results.push({ slug: article.slug, title: article.title, status: "generated", ...generated });
    } catch (error) {
      results.push({ slug: article.slug, title: article.title, status: "error", error: error.message });
    }
  }

  fs.writeFileSync(aiMetadataPath, JSON.stringify(metadata, null, 2), "utf8");
  fs.writeFileSync(
    reportPath,
    JSON.stringify(
      {
        status: "done",
        generatedAt: new Date().toISOString(),
        issueId,
        model,
        count: results.length,
        results
      },
      null,
      2
    ),
    "utf8"
  );
  console.log(`AI metadata completed: ${results.length} article(s), issue=${issueId}`);
};

await main();
