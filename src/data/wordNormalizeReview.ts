import { generatedWordNormalizeItems } from "./generatedWordNormalizeReview";
import publishState from "./publishState.json";

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

const typedPublishState = publishState as {
  publicLatestIssueId?: string;
  publishedIssues?: Record<string, unknown>;
};
const publishedIssueIds = new Set(
  [
    typedPublishState.publicLatestIssueId,
    ...Object.keys(typedPublishState.publishedIssues ?? {})
  ].filter((issueId): issueId is string => Boolean(issueId))
);

const allWordNormalizeItems: WordNormalizeItem[] = Array.isArray(generatedWordNormalizeItems)
  ? generatedWordNormalizeItems
  : [generatedWordNormalizeItems].filter(Boolean);

// Word normalization is only an import-time aid. Once an issue has been
// published, this historical report must not reopen it in old-draft review.
// Genuine later Word changes are tracked by the stable article signatures in
// generatedReview instead.
export const wordNormalizeItems = allWordNormalizeItems.filter(
  (item) => !publishedIssueIds.has(item.issueId)
);

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
