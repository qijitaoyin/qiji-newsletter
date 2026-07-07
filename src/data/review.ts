import { generatedReviewItems } from "./generatedReview";

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
  slug: string;
  sourceId: string;
  title: string;
  category: string;
  author: string;
  date: string;
  excerpt: string;
  image: string;
  messages: ReviewMessage[];
};

export const reviewItems: ReviewItem[] = Array.isArray(generatedReviewItems)
  ? generatedReviewItems
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
