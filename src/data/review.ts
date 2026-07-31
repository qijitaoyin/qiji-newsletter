import { generatedReviewItems } from "./generatedReview";
import { reviewArticles } from "./articles";

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

export const reviewItems: ReviewItem[] = Array.isArray(generatedReviewItems)
  ? generatedReviewItems.map((item) => {
      const article = reviewArticleBySlug.get(item.slug);
      return article
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
