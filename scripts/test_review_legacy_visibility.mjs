import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const publishState = JSON.parse(
  fs.readFileSync(path.join(repositoryRoot, "src/data/publishState.json"), "utf8")
);
const reviewHtmlPath = path.join(repositoryRoot, "dist/review/index.html");
const generatedReviewPath = path.join(repositoryRoot, "src/data/generatedReview.ts");

if (!fs.existsSync(reviewHtmlPath)) {
  throw new Error("Build output is missing. Run pnpm build before this test.");
}

const reviewHtml = fs.readFileSync(reviewHtmlPath, "utf8");
const generatedReviewSource = fs.readFileSync(generatedReviewPath, "utf8");
const generatedReviewMatch = generatedReviewSource.match(
  /export const generatedReviewItems = ([\s\S]*?) satisfies ReviewItem\[\];/
);
if (!generatedReviewMatch) {
  throw new Error("Cannot parse generated review data.");
}
const generatedReviewItems = JSON.parse(generatedReviewMatch[1]);
const publishedIssueIds = new Set([
  publishState.publicLatestIssueId,
  ...Object.keys(publishState.publishedIssues ?? {})
].filter(Boolean));

for (const issueId of publishedIssueIds) {
  if (reviewHtml.includes(`id="word-${issueId}"`)) {
    throw new Error(`Published issue ${issueId} reappeared in Word old-draft review.`);
  }
  const hasRealPublishedChange = generatedReviewItems.some(
    (item) =>
      item.issueId === issueId &&
      item.status !== "approved" &&
      item.messages?.some((message) => message.type === "published-content-changed")
  );
  const hasFormalOldDraftSection = reviewHtml.includes(`id="issue-${issueId}"`);
  const isCurrentReviewIssue = issueId === publishState.reviewIssueId;
  if (isCurrentReviewIssue) {
    if (hasFormalOldDraftSection) {
      throw new Error(`Current review issue ${issueId} should stay in latest-issue review.`);
    }
    if (hasRealPublishedChange) {
      const changedItems = generatedReviewItems.filter(
        (item) =>
          item.issueId === issueId &&
          item.status !== "approved" &&
          item.messages?.some((message) => message.type === "published-content-changed")
      );
      for (const item of changedItems) {
        if (!item.slug || !reviewHtml.includes(`value="${item.slug}"`)) {
          throw new Error(`Changed current article ${item.slug || item.id} is missing from latest-issue review.`);
        }
      }
    }
    continue;
  }
  if (hasFormalOldDraftSection !== hasRealPublishedChange) {
    throw new Error(
      `Published issue ${issueId} old-draft visibility does not match its stable-content status.`
    );
  }
}

for (const issueId of ["202605", "202607"]) {
  if (publishedIssueIds.has(issueId) && reviewHtml.includes(`id="word-${issueId}"`)) {
    throw new Error(`Regression: published issue ${issueId} is still listed as a Word old draft.`);
  }
}

console.log(
  `PASS: ${publishedIssueIds.size} published issues follow stable-content old-draft visibility.`
);
