import { generatedWordNormalizeItems } from "./generatedWordNormalizeReview";

export type WordNormalizeStatus = "error" | "normalize" | "normalized" | "review" | "skipped";

export type WordNormalizeItem = {
  file: string;
  issueId: string;
  status: WordNormalizeStatus | string;
  reason?: string;
  rule?: string;
  category?: string;
  title?: string;
  author?: string;
  date?: string;
  preview?: string;
  firstLines?: string[];
};

export const wordNormalizeItems: WordNormalizeItem[] = Array.isArray(generatedWordNormalizeItems)
  ? generatedWordNormalizeItems
  : [generatedWordNormalizeItems].filter(Boolean);

export const wordNormalizeSummary = {
  total: wordNormalizeItems.length,
  error: wordNormalizeItems.filter((item) => item.status === "error").length,
  review: wordNormalizeItems.filter((item) => item.status === "review").length,
  ready: wordNormalizeItems.filter((item) => item.status === "normalize" || item.status === "normalized").length,
  skipped: wordNormalizeItems.filter((item) => item.status === "skipped").length
};

export const wordNormalizeIssueIds = Array.from(
  new Set(wordNormalizeItems.map((item) => item.issueId).filter(Boolean))
).sort((a, b) => b.localeCompare(a));
