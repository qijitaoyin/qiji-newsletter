import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const readJson = (relativePath) =>
  JSON.parse(fs.readFileSync(path.join(root, relativePath), "utf8"));

const vocabulary = readJson("src/data/tagVocabulary.json");
const metadata = readJson("src/data/aiMetadata.json");
const compact = (value = "") =>
  String(value)
    .normalize("NFKC")
    .replace(/[\s　·・．.／/｜|,，、:：;；「」『』()（）［\]\[\-—–_]+/g, "")
    .trim()
    .toLowerCase();

const errors = [];
const excluded = new Set((vocabulary.excludedTags || []).map(compact));
const categories = new Set((vocabulary.categoryTags || []).map(compact));
const keywordLabels = (vocabulary.keywordTags || []).map((rule) => rule.label);
const keywordKeys = new Set(keywordLabels.map(compact));

for (const required of ["氣機導引", "東醫", "張良維"]) {
  if (!excluded.has(compact(required))) errors.push(`missing excluded tag: ${required}`);
}

for (const label of keywordLabels) {
  const key = compact(label);
  if (excluded.has(key)) errors.push(`excluded tag remains in keyword vocabulary: ${label}`);
  if (categories.has(key)) errors.push(`tag is both category and keyword: ${label}`);
}

const inspectTags = (owner, tags) => {
  if (!Array.isArray(tags)) return;
  if (tags.length > (vocabulary.maxKeywordTagsPerArticle ?? 5)) {
    errors.push(`${owner} has too many AI keyword tags: ${tags.length}`);
  }
  for (const tag of tags) {
    const key = compact(tag);
    if (excluded.has(key)) errors.push(`${owner} contains excluded tag: ${tag}`);
    if (categories.has(key)) errors.push(`${owner} contains category as AI keyword: ${tag}`);
    if (!keywordKeys.has(key)) errors.push(`${owner} contains unknown AI keyword: ${tag}`);
  }
};

for (const [slug, tags] of Object.entries(metadata.tags || {})) {
  inspectTags(`metadata.tags.${slug}`, tags);
}
for (const [slug, article] of Object.entries(metadata.articles || {})) {
  inspectTags(`metadata.articles.${slug}.tags`, article?.tags);
}

const builtIndexPath = path.join(root, "dist/data/article-index.json");
if (fs.existsSync(builtIndexPath)) {
  const builtIndex = JSON.parse(fs.readFileSync(builtIndexPath, "utf8"));
  for (const article of builtIndex.articles || []) {
    const tags = Array.isArray(article.tags) ? article.tags : [];
    if (tags.length > (vocabulary.maxTagsPerArticle ?? 6)) {
      errors.push(`${article.slug} has too many published tags: ${tags.length}`);
    }
    if (!tags.some((tag) => compact(tag) === compact(article.category))) {
      errors.push(`${article.slug} is missing its category tag: ${article.category}`);
    }
    for (const tag of tags) {
      const key = compact(tag);
      if (excluded.has(key)) errors.push(`${article.slug} contains excluded published tag: ${tag}`);
      if (key !== compact(article.category) && !keywordKeys.has(key)) {
        errors.push(`${article.slug} contains unknown published keyword: ${tag}`);
      }
    }
  }
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(
  `Tag rules OK: ${vocabulary.categoryTags?.length || 0} categories, ` +
    `${keywordLabels.length} keywords, ${excluded.size} excluded labels.`
);
