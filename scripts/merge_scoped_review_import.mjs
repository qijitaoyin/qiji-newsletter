import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));

const readExport = (file, name) => {
  const source = fs.readFileSync(file, "utf8");
  const match = source.match(new RegExp(`export const ${name} = ([\\s\\S]*?) satisfies [^;]+;`));
  if (!match) throw new Error(`Cannot read ${name} from ${file}`);
  return JSON.parse(match[1]);
};

const writeArticleModule = (file, articles, issues) => {
  const content = `import type { Article, IssueArchive } from "./articles";\n\nexport const generatedArticles = ${JSON.stringify(articles, null, 2)} satisfies Article[];\n\nexport const generatedIssues = ${JSON.stringify(issues, null, 2)} satisfies IssueArchive[];\n`;
  fs.writeFileSync(file, content, "utf8");
};

const writeReviewModule = (file, items) => {
  const content = `import type { ReviewItem } from "./review";\n\nexport const generatedReviewItems = ${JSON.stringify(items, null, 2)} satisfies ReviewItem[];\n`;
  fs.writeFileSync(file, content, "utf8");
};

const asArray = (value) => Array.isArray(value) ? value : value == null ? [] : [value];

const replaceSelected = (previous, current, selected, issueOf) => [
  ...asArray(previous).filter((item) => !selected.has(String(issueOf(item) || ""))),
  ...asArray(current)
];

export function mergeScopedReviewImport({
  selectionFile,
  previousDraftFile,
  previousReviewFile,
  previousCacheFile,
  generatedFile,
  generatedReviewFile,
  cacheFile
}) {
  const selection = readJson(selectionFile);
  const selected = new Set((selection.selectedIssueIds || []).map(String));
  if (!selected.size) return { selectedIssueIds: [], articleCount: 0, reviewCount: 0 };

  const previousArticles = readExport(previousDraftFile, "reviewDraftArticles");
  const previousIssues = readExport(previousDraftFile, "reviewDraftIssues");
  const currentArticles = readExport(generatedFile, "generatedArticles");
  const currentIssues = readExport(generatedFile, "generatedIssues");
  const previousReview = readExport(previousReviewFile, "generatedReviewItems");
  const currentReview = readExport(generatedReviewFile, "generatedReviewItems");

  const articles = replaceSelected(previousArticles, currentArticles, selected, (item) => item.issueId)
    .sort((a, b) => String(b.issueId).localeCompare(String(a.issueId)) || Number(a.order || 0) - Number(b.order || 0));
  const issues = replaceSelected(previousIssues, currentIssues, selected, (item) => item.id)
    .sort((a, b) => String(b.id).localeCompare(String(a.id)));
  const statusOrder = { error: 0, "needs-review": 1, approved: 2 };
  const reviewItems = replaceSelected(previousReview, currentReview, selected, (item) => item.issueId)
    .sort((a, b) => (statusOrder[a.status] ?? 9) - (statusOrder[b.status] ?? 9)
      || String(a.issueId).localeCompare(String(b.issueId))
      || String(a.file).localeCompare(String(b.file)));

  writeArticleModule(generatedFile, articles, issues);
  writeReviewModule(generatedReviewFile, reviewItems);

  if (previousCacheFile && fs.existsSync(previousCacheFile) && fs.existsSync(cacheFile)) {
    const previousCache = readJson(previousCacheFile);
    const currentCache = readJson(cacheFile);
    const entries = replaceSelected(
      previousCache.entries || [],
      currentCache.entries || [],
      selected,
      (item) => item.article?.issueId
    ).sort((a, b) => String(a.signature?.key || "").localeCompare(String(b.signature?.key || "")));
    fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
    fs.writeFileSync(cacheFile, `${JSON.stringify({ ...currentCache, entries }, null, 2)}\n`, "utf8");
  }

  return { selectedIssueIds: [...selected], articleCount: articles.length, reviewCount: reviewItems.length };
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  const args = Object.fromEntries(process.argv.slice(2).map((arg) => {
    const split = arg.indexOf("=");
    return [arg.slice(2, split), arg.slice(split + 1)];
  }));
  const result = mergeScopedReviewImport({
    selectionFile: args.selection,
    previousDraftFile: args.previousDraft,
    previousReviewFile: args.previousReview,
    previousCacheFile: args.previousCache,
    generatedFile: args.generated,
    generatedReviewFile: args.generatedReview,
    cacheFile: args.cache
  });
  console.log(JSON.stringify(result));
}
