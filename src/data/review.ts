import { generatedReviewItems } from "./generatedReview";
import { reviewArticles } from "./articles";
import tagVocabulary from "./tagVocabulary.json";

export type ReviewStatus = "error" | "needs-review" | "approved";

export type ReviewMessage = {
  severity: "error" | "warning" | string;
  type: string;
  message: string;
};

export type ReviewItem = {
  id: string;
  status: ReviewStatus;
  issueId: string;
  file: string;
  sourceModified: string;
  sourceSignature?: string;
  slug: string;
  sourceId: string;
  title: string;
  category: string;
  author: string;
  date: string;
  excerpt: string;
  image: string;
  tags?: string[];
  aiQuote?: string;
  aiSummary?: string;
  messages: ReviewMessage[];
};

const reviewArticleBySlug = new Map(reviewArticles.map((article) => [article.slug, article]));
const keywordLabels = new Set((tagVocabulary.keywordTags ?? []).map((tag) => tag.label));

const addRequiredMetadataGate = (item: ReviewItem): ReviewItem => {
  const requiresGate =
    item.status !== "approved" ||
    item.messages?.some((message) => message.type === "published-content-changed");
  if (!requiresGate) return item;
  const missing: string[] = [];
  if (!item.aiQuote?.trim()) missing.push("金句");
  if (!item.aiSummary?.trim()) missing.push("摘要");
  if (!item.category?.trim()) missing.push("文章分類");
  if (!(item.tags ?? []).some((tag) => keywordLabels.has(tag))) missing.push("關鍵字");
  if (!item.image?.trim() || item.image.includes("qiji-logo.png")) missing.push("文章配圖");
  if (!missing.length) return item;

  return {
    ...item,
    status: "error",
    messages: [
      ...(item.messages ?? []).filter((message) => message.type !== "required-metadata-missing"),
      {
        severity: "error",
        type: "required-metadata-missing",
        message: `缺少上架必要資料：${missing.join("、")}。請先更新草稿完成資料後再發布。`
      }
    ]
  };
};

export const reviewItems: ReviewItem[] = Array.isArray(generatedReviewItems)
  ? generatedReviewItems.map((item) => {
      const article = reviewArticleBySlug.get(item.slug);
      const merged = article
        ? {
            ...item,
            category: article.category || item.category,
            author: article.author || item.author,
            date: article.date || item.date,
            image: article.image || item.image,
            tags: article.tags ?? item.tags,
            aiQuote: article.aiQuote ?? item.aiQuote,
            aiSummary: article.aiSummary ?? item.aiSummary
          }
        : item;
      return addRequiredMetadataGate(merged);
    })
  : [generatedReviewItems].filter(Boolean);

export const reviewSummary = {
  total: reviewItems.length,
  error: reviewItems.filter((item) => item.status === "error").length,
  needsReview: reviewItems.filter((item) => item.status === "needs-review").length,
  approved: reviewItems.filter((item) => item.status === "approved").length
};

export const reviewIssueIds = Array.from(
  new Set(reviewItems.map((item) => item.issueId).filter(Boolean))
).sort((a, b) => b.localeCompare(a));
