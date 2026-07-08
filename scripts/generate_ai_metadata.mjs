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
  (provider === "kimi" ? "kimi-k2.5" : "gpt-5.5");
const targetIssue = process.env.AI_ISSUE_ID || "latest";
const limit = Number.parseInt(process.env.AI_LIMIT || "0", 10);
const force = process.env.AI_FORCE === "1" || process.env.AI_FORCE === "true";

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

const buildPrompt = (article) => [
  "你是氣機導引電子報的繁體中文編輯助理，請根據文章內容產生網站用 metadata。",
  "只回傳 JSON，不要 Markdown，不要解釋。",
  'JSON schema: {"quote":"50字以內的重點金句","tags":["2到5個中文主題標籤"]}',
  "",
  "規則：",
  "1. quote 必須是 50 個中文字以內，適合放在首頁或文章摘要的重點金句。",
  "2. quote 可以精煉原文意思，但不可編造文章沒有的主張。",
  "3. tags 使用簡短中文詞，最多 5 個，不要放作者、日期、期數或文章分類本身。",
  "4. 若文章內容不足以判斷，quote 請留空字串，tags 請留空陣列。",
  "",
  `文章分類：${article.category || ""}`,
  `文章標題：${article.title || ""}`,
  `作者：${article.author || ""}`,
  "",
  "文章內容：",
  articleText(article)
].join("\n");

const requestMetadata = async (article) => {
  const response = await fetch(`${apiBaseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content: "你只輸出合法 JSON。"
        },
        {
          role: "user",
          content: buildPrompt(article)
        }
      ],
      temperature: 0.2,
      max_tokens: 500
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`AI API failed for ${article.slug}: ${response.status} ${errorText}`);
  }

  const data = await response.json();
  const text = data.choices?.[0]?.message?.content || "";
  const parsed = parseAiJson(text);
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
      reason: "KIMI_API_KEY, OPENAI_API_KEY, or AI_API_KEY is not set",
      generatedAt: new Date().toISOString()
    };
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
    console.log("No AI API key is set; skipped AI metadata generation.");
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
        provider,
        apiBaseUrl,
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
  console.log(`AI metadata completed: ${results.length} article(s), provider=${provider}, issue=${issueId}`);
};

await main();
