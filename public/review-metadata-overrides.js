(function (global) {
  const metadataFields = [
    ["quote", "metadataQuote", "aiQuote"],
    ["summary", "metadataSummary", "aiSummary"],
    ["category", "metadataCategory", "category"],
    ["tags", "metadataTags", "tags"]
  ];

  const issueIdFromArticle = (article = {}) => {
    const explicit = String(article.issueId || "").trim();
    if (/^20\d{4}$/.test(explicit)) return explicit;
    return String(article.slug || "").match(/^((?:20)\d{4})-/)?.[1] || "";
  };

  const shouldApply = (report, key) => {
    const decision = report?.metadataDecisions?.[key] || "";
    if (decision) return decision === "accepted";
    return report?.status === "metadata";
  };

  const apply = (article = {}, reports = []) => {
    const next = { ...article };
    reports
      .filter((report) => report?.articleSlug === article.slug)
      .forEach((report) => {
        metadataFields.forEach(([key, reportKey, articleKey]) => {
          if (!shouldApply(report, key)) return;
          const value = report[reportKey];
          if (Array.isArray(value)) {
            if (value.length) next[articleKey] = [...value];
          } else if (value) {
            next[articleKey] = value;
          }
        });
      });
    return next;
  };

  const loadSharedReports = async ({ fetchImpl, endpoint, issueId, now = Date.now }) => {
    if (!/^20\d{4}$/.test(String(issueId || ""))) return [];
    const separator = endpoint.includes("?") ? "&" : "?";
    const response = await fetchImpl(
      `${endpoint}${separator}issueId=${encodeURIComponent(issueId)}&t=${now()}`,
      { cache: "no-store", headers: { accept: "application/json" } }
    );
    if (!response.ok) throw new Error(`Review reports ${response.status}`);
    const payload = await response.json();
    return Array.isArray(payload?.reports) ? payload.reports : [];
  };

  global.QijiReviewMetadataOverrides = Object.freeze({ apply, issueIdFromArticle, loadSharedReports });
})(globalThis);
