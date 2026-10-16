import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { mergeScopedReviewImport } from "./merge_scoped_review_import.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "qiji-scoped-import-"));
const write = (name, value) => {
  const file = path.join(root, name);
  fs.writeFileSync(file, value, "utf8");
  return file;
};
const articleModule = (prefix, articles, issues) => `import type { Article, IssueArchive } from "./articles";\nexport const ${prefix}Articles = ${JSON.stringify(articles)} satisfies Article[];\nexport const ${prefix}Issues = ${JSON.stringify(issues)} satisfies IssueArchive[];\n`;
const reviewModule = (items) => `import type { ReviewItem } from "./review";\nexport const generatedReviewItems = ${JSON.stringify(items)} satisfies ReviewItem[];\n`;

try {
  const selection = write("selection.json", JSON.stringify({ selectedIssueIds: ["202611"] }));
  const previousDraft = write("previous-draft.ts", articleModule("reviewDraft", [
    { issueId: "202610", slug: "old-published" },
    { issueId: "202508", slug: "old-draft" }
  ], [{ id: "202610" }, { id: "202508" }]));
  const generated = write("generated.ts", articleModule("generated", [
    { issueId: "202611", slug: "new-draft" }
  ], [{ id: "202611" }]));
  const previousReview = write("previous-review.ts", reviewModule([
    { issueId: "202508", id: "keep", status: "needs-review", file: "keep.docx" }
  ]));
  const generatedReview = write("generated-review.ts", reviewModule([
    { issueId: "202611", id: "new", status: "needs-review", file: "new.docx" }
  ]));
  const previousCache = write("previous-cache.json", JSON.stringify({ version: 1, entries: [
    { signature: { key: "old" }, article: { issueId: "202508" } }
  ] }));
  const cache = write("cache.json", JSON.stringify({ version: 1, entries: [
    { signature: { key: "new" }, article: { issueId: "202611" } }
  ] }));

  mergeScopedReviewImport({ selectionFile: selection, previousDraftFile: previousDraft,
    previousReviewFile: previousReview, previousCacheFile: previousCache,
    generatedFile: generated, generatedReviewFile: generatedReview, cacheFile: cache });

  const output = fs.readFileSync(generated, "utf8");
  assert.match(output, /old-published/);
  assert.match(output, /old-draft/);
  assert.match(output, /new-draft/);
  const review = fs.readFileSync(generatedReview, "utf8");
  assert.match(review, /"keep"/);
  assert.match(review, /"new"/);
  assert.equal(JSON.parse(fs.readFileSync(cache, "utf8")).entries.length, 2);

  fs.writeFileSync(selection, JSON.stringify({ selectedIssueIds: ["202508"] }), "utf8");
  fs.writeFileSync(previousDraft, fs.readFileSync(generated, "utf8")
    .replaceAll("generatedArticles", "reviewDraftArticles")
    .replaceAll("generatedIssues", "reviewDraftIssues"), "utf8");
  fs.writeFileSync(generated, articleModule("generated", [
    { issueId: "202508", slug: "old-draft-updated" }
  ], { id: "202508", title: "updated" }), "utf8");
  fs.writeFileSync(previousReview, fs.readFileSync(generatedReview, "utf8"), "utf8");
  fs.writeFileSync(generatedReview, reviewModule([
    { issueId: "202508", id: "updated", status: "needs-review", file: "updated.docx" }
  ]), "utf8");
  fs.copyFileSync(cache, previousCache);
  fs.writeFileSync(cache, JSON.stringify({ version: 1, entries: [
    { signature: { key: "updated" }, article: { issueId: "202508" } }
  ] }), "utf8");

  mergeScopedReviewImport({ selectionFile: selection, previousDraftFile: previousDraft,
    previousReviewFile: previousReview, previousCacheFile: previousCache,
    generatedFile: generated, generatedReviewFile: generatedReview, cacheFile: cache });
  const secondOutput = fs.readFileSync(generated, "utf8");
  assert.doesNotMatch(secondOutput, /"old-draft"/);
  assert.match(secondOutput, /old-draft-updated/);
  assert.match(secondOutput, /old-published/);
  assert.match(secondOutput, /new-draft/);
  assert.equal(JSON.parse(fs.readFileSync(cache, "utf8")).entries.length, 2);
  console.log("Scoped review import merge regression passed.");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
