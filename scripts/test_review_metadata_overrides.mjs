import assert from "node:assert/strict";

await import(`../public/review-metadata-overrides.js?test=${Date.now()}`);

const metadata = globalThis.QijiReviewMetadataOverrides;
assert.ok(metadata, "review metadata helper should be available");

const oldArticle = {
  slug: "202609-2609-1",
  issueId: "202609",
  aiQuote: "須待繁花落盡時，真功夫可以無限複製在每個人身上。",
  aiSummary: "舊 AI 摘要",
  body: "舊 Word 內文"
};
const reports = [
  {
    articleSlug: oldArticle.slug,
    metadataQuote: "再高明的心法做法，如果不能成為自己，也只是繁花一現，秀而不實，終是一場空",
    metadataSummary: "未採納的新摘要",
    metadataDecisions: { quote: "accepted", summary: "rejected" }
  }
];

const merged = metadata.apply(oldArticle, reports);
assert.equal(
  merged.aiQuote,
  "再高明的心法做法，如果不能成為自己，也只是繁花一現，秀而不實，終是一場空",
  "accepted quote must override stale AI metadata"
);
assert.equal(merged.aiSummary, "舊 AI 摘要", "rejected metadata must not replace AI metadata");
assert.equal(
  oldArticle.aiQuote,
  "須待繁花落盡時，真功夫可以無限複製在每個人身上。",
  "merging must not mutate the source article"
);
assert.equal(metadata.issueIdFromArticle({ slug: "202609-2609-1" }), "202609");

const requestedUrls = [];
const sharedReports = await metadata.loadSharedReports({
  fetchImpl: async (url, options) => {
    requestedUrls.push({ url, options });
    return { ok: true, json: async () => ({ reports }) };
  },
  endpoint: "/api/review-reports",
  issueId: metadata.issueIdFromArticle(oldArticle),
  now: () => 123
});

assert.deepEqual(sharedReports, reports, "shared reports should be returned unchanged");
assert.equal(requestedUrls[0].url, "/api/review-reports?issueId=202609&t=123");
assert.equal(requestedUrls[0].options.cache, "no-store");

const afterRefresh = metadata.apply({ ...oldArticle, body: "新版 Word 內文" }, sharedReports);
assert.equal(afterRefresh.body, "新版 Word 內文", "Word refresh must remain visible");
assert.equal(
  afterRefresh.aiQuote,
  "再高明的心法做法，如果不能成為自己，也只是繁花一現，秀而不實，終是一場空",
  "Word refresh must preserve the accepted quote"
);

console.log("Review metadata override tests passed.");
