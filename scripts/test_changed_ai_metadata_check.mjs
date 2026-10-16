import assert from "node:assert/strict";
import { contentHashFor, validateChangedMetadata } from "./check_changed_ai_metadata.mjs";

const article = {
  slug: "202508-2508-2-1",
  sourceId: "2508-2-1",
  issueId: "202508",
  title: "在自己的真相裡成就",
  category: "如是我聞",
  author: "文稿彙整 / 日早班",
  date: "2025.08.10",
  excerpt: "測試摘要內容",
  contentBlocks: [{ type: "paragraph", text: "測試文章內容" }]
};
const changedFiles = [
  { issueId: "202508", fileName: "2508-2-1如是我聞之一.docx", status: "updated" }
];
const validItem = {
  sourceKey: "202508:2508-2-1:202508-2508-2-1",
  contentHash: contentHashFor(article),
  quote: "測試金句",
  summary: "測試摘要",
  tags: ["覺醒"],
  themes: ["內在自由"]
};
const run = (item, files = changedFiles, articles = [article]) =>
  validateChangedMetadata({
    articles,
    changedFiles: files,
    metadata: { articles: item ? { [article.slug]: item } : {} },
    keywordLabels: ["覺醒", "生命修煉"]
  });

assert.equal(run(validItem).issues.length, 0, "complete current metadata should pass");
assert.match(run(null).issues[0].missing.join("、"), /AI metadata/, "missing metadata should fail");
assert.match(
  run({ ...validItem, quote: "" }).issues[0].missing.join("、"),
  /金句/,
  "missing quote should fail"
);
assert.match(
  run({ ...validItem, tags: ["如是我聞"] }).issues[0].missing.join("、"),
  /有效關鍵字/,
  "category-only tags should fail"
);
assert.match(
  run(validItem, changedFiles, [{ ...article, excerpt: "文章內容已更新" }]).issues[0].missing.join("、"),
  /目前文章內容相符/,
  "stale metadata should fail after article content changes"
);
assert.equal(
  run(null, [{ ...changedFiles[0], status: "unchanged" }]).issues.length,
  0,
  "unchanged files should not require regenerated metadata"
);

console.log("Changed AI metadata checks passed.");
