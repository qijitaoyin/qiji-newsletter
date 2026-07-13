import { generatedArticles, generatedIssues } from "./generatedArticles";
import editorialOverrides from "./editorialOverrides.json";
import aiMetadata from "./aiMetadata.json";
import publishState from "./publishState.json";
import tagVocabulary from "./tagVocabulary.json";
import { pathFor } from "../utils/paths";

const typedAiMetadata = aiMetadata as {
  quotes?: Record<string, string>;
  tags?: Record<string, string[]>;
  summaries?: Record<string, string>;
  themes?: Record<string, string[]>;
  similar?: Record<string, string[]>;
  articles?: Record<
    string,
    {
      quote?: string;
      tags?: string[];
      summary?: string;
      themes?: string[];
      similarCandidates?: string[];
    }
  >;
};

const typedPublishState = publishState as {
  publicLatestIssueId?: string;
  reviewIssueId?: string;
};

type TagVocabulary = {
  maxTagsPerArticle?: number;
  categoryTags?: string[];
  keywordTags?: { label: string; aliases: string[] }[];
};

const controlledTagVocabulary = tagVocabulary as TagVocabulary;
const maxControlledTagsPerArticle = controlledTagVocabulary.maxTagsPerArticle ?? 5;

const compactTagLabel = (value = "") =>
  value
    .normalize("NFKC")
    .replace(/[\s　·・．.／/｜|,，、:：;；「」『』()（）［\]\[\-—–_]+/g, "")
    .trim()
    .toLowerCase();

const categoryCounts = new Map<string, number>();
generatedArticles.forEach((article) => {
  const key = compactTagLabel(article.category);
  if (!key) return;
  categoryCounts.set(key, (categoryCounts.get(key) ?? 0) + 1);
});

const controlledTagLabels = new Map<string, string>();
(controlledTagVocabulary.categoryTags ?? []).forEach((label) => {
  controlledTagLabels.set(compactTagLabel(label), label);
});
(controlledTagVocabulary.keywordTags ?? []).forEach((rule) => {
  controlledTagLabels.set(compactTagLabel(rule.label), rule.label);
});

const manualTagValues = Object.values((editorialOverrides as { tags?: Record<string, string[]> }).tags ?? {})
  .flat()
  .filter(Boolean);
manualTagValues.forEach((label) => {
  controlledTagLabels.set(compactTagLabel(label), label);
});

export type ArticleSection = {
  heading?: string;
  paragraphs: string[];
};

export type ArticleContentBlock =
  | {
      type: "heading" | "paragraph";
      text: string;
    }
  | {
      type: "image";
      src: string;
      caption?: string;
    };

export type ArticleImage = {
  src: string;
  caption?: string;
};

export type Article = {
  slug: string;
  sourceId: string;
  sourceUrl: string;
  issueId: string;
  title: string;
  subtitle?: string;
  category: string;
  author: string;
  date: string;
  issue: string;
  readTime: string;
  homeAnchor: string;
  excerpt: string;
  lede?: string;
  image: string;
  imageCaption: string;
  sections: ArticleSection[];
  contentBlocks?: ArticleContentBlock[];
  images?: ArticleImage[];
  tags: string[];
  aiQuote?: string;
  aiSummary?: string;
  aiThemes?: string[];
  aiSimilarSlugs?: string[];
  order: number;
};

export type IssueArchive = {
  id: string;
  label: string;
  issueNumber: string;
  date: string;
  href: string;
  articleCount: number;
  image: string;
  title: string;
};

export const publicLatestIssueId = typedPublishState.publicLatestIssueId || "202605";
const newestGeneratedIssueId = generatedIssues[0]?.id ?? publicLatestIssueId;
export const reviewIssueId =
  typedPublishState.reviewIssueId ||
  (newestGeneratedIssueId.localeCompare(publicLatestIssueId) > 0
    ? newestGeneratedIssueId
    : publicLatestIssueId);

const isPublishedIssue = (issueId: string) =>
  issueId.localeCompare(publicLatestIssueId) <= 0;

export type ArticleTag = {
  label: string;
  slug: string;
  description: string;
};

const articleOrder = (article: Article) =>
  article.category === "編輯小語" ? -1 : article.order;

const sourceIdOrder = (sourceId: string) =>
  sourceId
    .split("-")
    .map((part) => Number.parseInt(part, 10))
    .filter((part) => Number.isFinite(part));

const compareSourceId = (a: string, b: string) => {
  const left = sourceIdOrder(a);
  const right = sourceIdOrder(b);
  const length = Math.max(left.length, right.length);

  for (let i = 0; i < length; i++) {
    const diff = (left[i] ?? -1) - (right[i] ?? -1);
    if (diff !== 0) return diff;
  }

  return a.localeCompare(b);
};

const compareArticlesInIssue = (a: Article, b: Article) =>
  compareSourceId(a.sourceId, b.sourceId) || articleOrder(a) - articleOrder(b);

const categoryLabels = [
  "編輯小語",
  "同頻共振",
  "靈魂修煉",
  "身體感知",
  "覺性修煉",
  "如是我聞",
  "道德經",
  "體證道德經",
  "導引按蹻",
  "練功筆記",
  "導引香道",
  "圖靈集",
  "心田集",
  "觀行錄",
  "股海人生",
  "導引采風錄",
  "身體書寫",
  "山腳下的蘆葦",
  "AI時代",
  "專欄文章"
];

const normalizeLabel = (value = "") =>
  value.replace(/[【】「」《》〈〉（）()［］\[\]\s／\/・．.。、，,：:－—\-]/g, "");

const isCategoryMarker = (value: string, category: string) => {
  const normalized = normalizeLabel(value);
  if (!normalized || normalized.length > 24) return false;
  const normalizedCategory = normalizeLabel(category);
  return (
    normalized === normalizedCategory ||
    normalized.includes(normalizedCategory) ||
    categoryLabels.some((label) => normalized === normalizeLabel(label))
  );
};

const isCategoryLikeTitle = (title: string, category: string) =>
  isCategoryMarker(title, category) || categoryLabels.some((label) => normalizeLabel(title) === normalizeLabel(label));

const looksLikeAuthor = (value = "") => {
  const text = value.trim();
  return (
    /^(文稿彙整|文稿整理|文稿|撰文|作者|整理|編輯|編輯部|口述|攝影|譯|全覺能|阿充|鄭雅靜|蔡進懋|莫仁維|韓憶萍|張良維)/.test(text) ||
    /^[^，。！？；]{1,12}[／/：:][^，。！？；]{1,24}$/.test(text)
  );
};

const looksLikePersonName = (value = "") =>
  /^[\p{Script=Han}]{2,4}$/u.test(value.trim());

const isBylineLikeTitle = (title: string, category: string) => {
  const normalized = normalizeLabel(title);
  return (
    isCategoryLikeTitle(title, category) ||
    normalized === normalizeLabel("編輯部") ||
    looksLikeAuthor(title)
  );
};

const looksLikeTitle = (value: string, category: string) => {
  const text = value.trim();
  return (
    text.length >= 1 &&
    text.length <= 64 &&
    !isCategoryMarker(text, category) &&
    !looksLikeAuthor(text) &&
    !/[。；]$/.test(text)
  );
};

const titleFromText = (value: string, category: string) => {
  const text = value.trim().replace(/\s+/g, " ");
  if (
    text.length < 8 ||
    isCategoryMarker(text, category) ||
    looksLikeAuthor(text) ||
    looksLikePersonName(text)
  ) {
    return "";
  }

  return text
    .slice(0, 64)
    .replace(/[，,。；;：:、\s]+$/u, "")
    .trim();
};

const flatArticleText = (article: Article) =>
  article.sections.flatMap((section) => [section.heading, ...section.paragraphs]).filter(Boolean) as string[];

const cleanInferredHeaderSections = (
  sections: ArticleSection[],
  valuesToRemove: string[],
  category: string
) => {
  const removalKeys = new Set(valuesToRemove.filter(Boolean).map(normalizeLabel));

  return sections
    .map((section) => {
      const headingKey = normalizeLabel(section.heading ?? "");
      const heading =
        headingKey && !removalKeys.has(headingKey) && !isCategoryMarker(section.heading ?? "", category)
          ? section.heading
          : undefined;
      const paragraphs = section.paragraphs.filter((paragraph) => {
        const key = normalizeLabel(paragraph);
        return key && !removalKeys.has(key) && !isCategoryMarker(paragraph, category);
      });

      return { heading, paragraphs };
    })
    .filter((section) => section.heading || section.paragraphs.length > 0);
};

const excerptFromSections = (sections: ArticleSection[]) =>
  sections
    .flatMap((section) => section.paragraphs)
    .find((paragraph) => paragraph.trim().length >= 24)
    ?.trim() ?? "";

const withNormalizedTitleAndAuthor = (article: Article): Article => {
  const texts = flatArticleText(article).map((text) => text.trim()).filter(Boolean);
  const manualTitle = editorialOverrides.titles?.[article.slug]?.trim();
  const authorAppearsInBody = texts.some((text) => normalizeLabel(text) === normalizeLabel(article.author));
  const shouldSwapAuthorTitle =
    Boolean(article.author) &&
    authorAppearsInBody &&
    looksLikeTitle(article.author, article.category) &&
    !looksLikeAuthor(article.author) &&
    !isBylineLikeTitle(article.title, article.category) &&
    (looksLikeAuthor(article.title) || looksLikePersonName(article.title));
  const needsTitleNormalization =
    Boolean(manualTitle) || isBylineLikeTitle(article.title, article.category) || shouldSwapAuthorTitle;
  const needsAuthorNormalization = !article.author;

  if (!needsTitleNormalization && !needsAuthorNormalization) {
    return article;
  }

  const titleIndex = texts.findIndex((text) => looksLikeTitle(text, article.category));
  const fallbackTitle = texts.map((text) => titleFromText(text, article.category)).find(Boolean) ?? "";
  const authorBodyIndex = texts.findIndex((text) => normalizeLabel(text) === normalizeLabel(article.author));
  const authorAsTitle = looksLikeTitle(article.author, article.category) ? article.author.trim() : "";
  const inferredTitle =
    !needsTitleNormalization
      ? article.title
      : manualTitle
      ? manualTitle
      : shouldSwapAuthorTitle
      ? article.author.trim()
      : titleIndex >= 0
      ? texts[titleIndex]
      : fallbackTitle
      ? fallbackTitle
      : authorAsTitle
        ? authorAsTitle
        : article.title;

  const authorAnchorIndex = shouldSwapAuthorTitle ? authorBodyIndex : titleIndex;
  const nearbyAuthorCandidates =
    authorAnchorIndex >= 0
      ? texts
          .slice(authorAnchorIndex + 1, authorAnchorIndex + 8)
          .filter((text) => normalizeLabel(text) !== normalizeLabel(article.title))
      : needsAuthorNormalization
      ? texts.slice(0, 8)
      : [];
  const headingAuthorCandidates = shouldSwapAuthorTitle
    ? article.sections.map((section) => section.heading ?? "")
    : [];
  const authorCandidates = [
    ...headingAuthorCandidates,
    ...nearbyAuthorCandidates,
    shouldSwapAuthorTitle ? article.title : "",
    article.author && article.author !== authorAsTitle ? article.author : ""
  ].filter(Boolean);
  const defaultAuthor = normalizeLabel(article.category) === normalizeLabel("編輯小語") ? "編輯部" : "";
  const inferredAuthor =
    authorCandidates.find((candidate) => {
        const text = candidate.trim();
        return (
          text !== inferredTitle &&
          text.length <= 48 &&
          !isCategoryMarker(text, article.category) &&
          (looksLikeAuthor(text) || looksLikePersonName(text))
        );
      }) ?? (article.category === "編輯小語" ? "編輯部" : "");
  const sections = cleanInferredHeaderSections(
    article.sections,
    [article.title, article.author, inferredTitle, inferredAuthor, "編輯部"],
    article.category
  );

  return {
    ...article,
    title: inferredTitle,
    author: inferredAuthor,
    excerpt: excerptFromSections(sections) || article.excerpt,
    sections
  };
};

type AutoTagRule = {
  label: string;
  pattern: RegExp;
};

const autoTagRules: AutoTagRule[] = [
  { label: "同頻共振", pattern: /同頻|共振|頻率|造浪|衝浪|集體|連結/ },
  { label: "靈魂修煉", pattern: /靈魂|靈性|生命|內在|主導|覺能|成佛/ },
  { label: "身體感知", pattern: /身體|氣流|感覺|覺知|覺察|放鬆|骨盆|脊椎|丹田|周天|氣機/ },
  { label: "覺性修煉", pattern: /覺性|覺察|觀照|識神|識性|無極|修煉|修練|修行/ },
  { label: "道德經", pattern: /道德經|老子|道可道|德經/ },
  { label: "體證道德經", pattern: /體證|道德經|老子/ },
  { label: "導引按蹻", pattern: /按蹻|治療|調整|調理|筋膜|骨盆|身體結構/ },
  { label: "練功筆記", pattern: /練功|功法|無極|站樁|打坐|丹田/ },
  { label: "導引香道", pattern: /香道|沉香|識香|五感|香氣|品香|藏香/ },
  { label: "圖靈集", pattern: /AI|人工智慧|圖靈|演算法|模型|NPC|ChatGPT/i },
  { label: "AI時代", pattern: /AI|人工智慧|圖靈|演算法|模型|NPC|ChatGPT/i },
  { label: "心田集", pattern: /心田|心性|初心|心念|心境|內心/ },
  { label: "觀行錄", pattern: /觀行|觀照|行住坐臥/ },
  { label: "股海人生", pattern: /股海|市場|資產|投資|股票|貨幣|週期|財富/ },
  { label: "導引采風錄", pattern: /采風|會館|南台灣的全覺能基地|活動紀錄/ },
  { label: "身體書寫", pattern: /身體書寫|身體經驗|身體感|感官/ },
  { label: "山腳下的蘆葦", pattern: /山腳下的蘆葦|森林|蘆葦|旅行書寫/ }
];

const maxAutoTagsPerArticle = 4;

const articleSearchText = (article: Article) =>
  [
    article.title,
    article.subtitle,
    article.category,
    article.excerpt,
    article.lede,
    ...article.sections.flatMap((section) => [section.heading, ...section.paragraphs]),
    ...(article.contentBlocks ?? []).map((block) =>
      block.type === "image" ? block.caption ?? "" : block.text
    )
  ]
    .filter(Boolean)
    .join("\n");

const articleKeywordText = (article: Article) => compactTagLabel(articleSearchText(article));

const keywordMatchesText = (
  text: string,
  rule: { label: string; aliases: string[] }
) => {
  const aliases = [rule.label, ...(rule.aliases ?? [])].map(compactTagLabel).filter(Boolean);
  return aliases.some((alias) => text.includes(alias));
};

const keywordArticleCounts = new Map<string, number>();
(controlledTagVocabulary.keywordTags ?? []).forEach((rule) => {
  const count = generatedArticles.filter((article) =>
    keywordMatchesText(articleKeywordText(article), rule)
  ).length;
  keywordArticleCounts.set(rule.label, count);
});

const canonicalControlledTag = (value = "") => {
  const key = compactTagLabel(value);
  return controlledTagLabels.get(key) ?? "";
};

const pushUniqueTag = (tags: string[], value = "", allowUnknown = false) => {
  if (tags.length >= maxControlledTagsPerArticle) return;
  const canonical = canonicalControlledTag(value);
  const label = canonical || (allowUnknown ? value.trim() : "");
  if (!label) return;
  const key = compactTagLabel(label);
  if (!key || tags.some((tag) => compactTagLabel(tag) === key)) return;
  tags.push(label);
};

const aiArticleMetadata = typedAiMetadata.articles ?? {};

const metadataFor = (article: Article) => aiArticleMetadata[article.slug] ?? {};

const withAutoTags = (article: Article): Article => {
  const text = articleSearchText(article);
  const manualTags = editorialOverrides.tags?.[article.slug];
  const ai = metadataFor(article);
  const aiTags = ai.tags?.length ? ai.tags : typedAiMetadata.tags?.[article.slug];
  const tags: string[] = [];
  const categoryKey = compactTagLabel(article.category);
  if ((categoryCounts.get(categoryKey) ?? 0) > 1) {
    pushUniqueTag(tags, article.category, true);
  }

  (manualTags ?? []).forEach((tag) => pushUniqueTag(tags, tag, true));
  article.tags.forEach((tag) => pushUniqueTag(tags, tag));
  (aiTags ?? []).forEach((tag) => pushUniqueTag(tags, tag));

  const compactText = compactTagLabel(text);
  for (const rule of controlledTagVocabulary.keywordTags ?? []) {
    if (tags.length >= maxControlledTagsPerArticle) break;
    if ((keywordArticleCounts.get(rule.label) ?? 0) < 5) continue;
    if (keywordMatchesText(compactText, rule)) {
      pushUniqueTag(tags, rule.label);
    }
  }

  return {
    ...article,
    tags,
    aiQuote: editorialOverrides.quotes?.[article.slug] ?? ai.quote ?? typedAiMetadata.quotes?.[article.slug],
    aiSummary: ai.summary ?? typedAiMetadata.summaries?.[article.slug],
    aiThemes: ai.themes ?? typedAiMetadata.themes?.[article.slug] ?? [],
    aiSimilarSlugs: ai.similarCandidates ?? typedAiMetadata.similar?.[article.slug] ?? []
  };
};

const withBasePaths = (article: Article): Article => ({
  ...article,
  homeAnchor: pathFor(article.homeAnchor),
  image: pathFor(article.image),
  images: article.images?.map((image) => ({
    ...image,
    src: pathFor(image.src)
  })),
  contentBlocks: article.contentBlocks?.map((block) =>
    block.type === "image"
      ? {
          ...block,
          src: pathFor(block.src)
        }
      : block
  )
});

export const articles: Article[] = generatedArticles
  .map(withNormalizedTitleAndAuthor)
  .map(withAutoTags)
  .map(withBasePaths)
  .sort((a, b) => b.issueId.localeCompare(a.issueId) || compareArticlesInIssue(a, b));

export const issueArchives: IssueArchive[] = generatedIssues.map((issue) => ({
  ...issue,
  href: pathFor(issue.href),
  image: pathFor(issue.image)
}));

export const publishedArticles = articles.filter((article) => isPublishedIssue(article.issueId));

export const publishedIssueArchives = issueArchives.filter((issue) =>
  isPublishedIssue(issue.id)
);

export const reviewIssueArchive =
  issueArchives.find((issue) => issue.id === reviewIssueId) ?? issueArchives[0];

export const reviewIssueArticles = articles.filter(
  (article) => article.issueId === reviewIssueArchive?.id
);

export const latestIssueArchive =
  publishedIssueArchives.find((issue) => issue.id === publicLatestIssueId) ??
  publishedIssueArchives[0] ??
  issueArchives[0];

export const latestIssueArticles = publishedArticles.filter(
  (article) => article.issueId === latestIssueArchive?.id
);

export const latestIssue = {
  title: latestIssueArticles[0]?.title ?? "氣機導引電子報",
  issueNumber: latestIssueArchive?.issueNumber ?? "",
  date: latestIssueArchive?.date ?? "",
  issueLabel: latestIssueArchive
    ? `${latestIssueArchive.issueNumber} / ${latestIssueArchive.date} 電子報`
    : "氣機導引電子報",
  summary: latestIssueArchive
    ? `${latestIssueArchive.date} 電子報收錄 ${latestIssueArchive.articleCount} 篇文章。`
    : "氣機導引電子報歷史文章。",
  href: latestIssueArchive?.href ?? pathFor("/archive/"),
  image: latestIssueArchive?.image ?? pathFor("/assets/qiji-logo.png")
};

const tagDescriptions: Record<string, string> = {
  編輯小語: "本期編輯部導讀與主題開場。",
  同頻共振: "課程、練功與身心共振的現場記錄。",
  靈魂修煉: "從生活經驗回看自我修煉的文章。",
  身體感知: "身體覺察、導引練習與身心經驗。",
  覺性修煉: "覺察、觀照與修行疑義的討論。",
  如是我聞: "課堂問答、疑義解析與修煉觀點。",
  道德經: "老子與道德經章句的體證閱讀。",
  體證道德經: "從身心實修進入道德經的體會。",
  導引按蹻: "導引按蹻、治療與身體調整。",
  練功筆記: "功法練習、無極與身體經驗記錄。",
  導引香道: "香道、五感與生活美學。",
  圖靈集: "AI 時代與修煉觀點的交會。",
  心田集: "心性、生命與內在風景書寫。",
  觀行錄: "觀照日常、行住坐臥中的修煉。",
  股海人生: "市場、資產與人生修煉。",
  導引采風錄: "氣機導引活動與社群采風。",
  身體書寫: "以身體為入口的經驗書寫。",
  山腳下的蘆葦: "生活、自然與靈魂修煉隨筆。",
  AI時代: "人工智慧時代與修煉、生命觀點的交會。",
  專欄文章: "各期電子報專欄文章。"
};

const makeSlug = (label: string) =>
  label
    .normalize("NFKD")
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}]+/gu, "-")
    .replace(/^-|-$/g, "") || encodeURIComponent(label);

const fixedTagSlugs: Record<string, string> = {
  編輯小語: "editor-note",
  同頻共振: "resonance",
  靈魂修煉: "soul-practice",
  身體感知: "body-awareness",
  覺性修煉: "awareness-practice",
  如是我聞: "rushi-wowen",
  道德經: "daodejing",
  體證道德經: "daodejing-practice",
  導引按蹻: "daoyin-anqiao",
  練功筆記: "practice-notes",
  導引香道: "daoyin-incense",
  圖靈集: "turing-column",
  心田集: "heart-field",
  觀行錄: "observation-practice",
  股海人生: "market-life",
  導引采風錄: "daoyin-news",
  身體書寫: "body-writing",
  山腳下的蘆葦: "reeds-under-mountain",
  AI時代: "ai-era",
  專欄文章: "column"
};

export const articleTags: ArticleTag[] = Array.from(
  new Set(publishedArticles.flatMap((article) => article.tags))
).reduce((tags, label) => {
  const slug = fixedTagSlugs[label] ?? makeSlug(label);
  if (!tags.some((tag) => tag.slug === slug)) {
    tags.push({
      label,
      slug,
      description: tagDescriptions[label] ?? `${label} 文章索引。`
    });
  }
  return tags;
}, [] as ArticleTag[]);

export const articleCategorySlugs = Object.fromEntries(
  articleTags.map((tag) => [tag.label, tag.slug])
);

export const getArticleBySlug = (slug: string) =>
  articles.find((article) => article.slug === slug);

export const getArticlesByTag = (label: string) =>
  publishedArticles.filter((article) => article.tags.includes(label));

export const getArticlesByIssue = (issueId: string) =>
  publishedArticles
    .filter((article) => article.issueId === issueId)
    .sort(compareArticlesInIssue);

export const getAllArticlesByIssue = (issueId: string) =>
  articles
    .filter((article) => article.issueId === issueId)
    .sort(compareArticlesInIssue);

export const getIssueById = (issueId: string) =>
  publishedIssueArchives.find((issue) => issue.id === issueId);

export const getRelatedArticles = (currentSlug: string) => {
  const current = getArticleBySlug(currentSlug);
  if (!current) {
    return publishedArticles.filter((article) => article.slug !== currentSlug).slice(0, 3);
  }

  const candidates = isPublishedIssue(current.issueId) ? publishedArticles : articles;

  const aiRelated = (current.aiSimilarSlugs ?? [])
    .map((slug) => getArticleBySlug(slug))
    .filter(
      (article): article is Article =>
        Boolean(article) &&
        article.slug !== currentSlug &&
        (!isPublishedIssue(current.issueId) || isPublishedIssue(article.issueId))
    );

  const related = candidates
    .filter((article) => article.slug !== currentSlug)
    .map((article) => ({
      article,
      score:
        article.tags.filter((tag) => current.tags.includes(tag)).length +
        (article.issueId === current.issueId ? 2 : 0)
    }))
    .sort((a, b) => b.score - a.score);

  const fallback = related.map((item) => item.article);
  return [...aiRelated, ...fallback.filter((article) => !aiRelated.some((item) => item.slug === article.slug))]
    .slice(0, 3);
};
