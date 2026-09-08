const json = (value, init = {}) =>
  new Response(JSON.stringify(value), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...(init.headers || {})
    }
  });

const issueIdFromReport = (report) => {
  const explicit = String(report?.issueId || "").trim();
  if (/^20\d{4}$/.test(explicit)) return explicit;
  const slugMatch = String(report?.articleSlug || "").match(/^((?:20)\d{4})-/);
  return slugMatch?.[1] || "";
};

const parseStoredReport = (row) => {
  try {
    return JSON.parse(row.payload);
  } catch {
    return null;
  }
};

const validMutationRequest = (request) => {
  const contentType = request.headers.get("content-type") || "";
  return request.headers.get("x-qiji-review") === "1" && contentType.includes("application/json");
};

const readBody = async (request) => {
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (declaredLength > 1_500_000) throw new Error("PAYLOAD_TOO_LARGE");
  const text = await request.text();
  if (text.length > 1_500_000) throw new Error("PAYLOAD_TOO_LARGE");
  return JSON.parse(text || "{}");
};

export const onRequestGet = async ({ request, env }) => {
  if (!env.REVIEW_DB) return json({ error: "REVIEW_DB is not configured" }, { status: 503 });
  const issueId = new URL(request.url).searchParams.get("issueId") || "";
  if (!/^20\d{4}$/.test(issueId)) return json({ error: "Invalid issueId" }, { status: 400 });

  const result = await env.REVIEW_DB.prepare(
    "SELECT payload FROM review_reports WHERE issue_id = ?1 ORDER BY created_at ASC"
  ).bind(issueId).all();
  const reports = (result.results || []).map(parseStoredReport).filter(Boolean);
  return json({ reports });
};

export const onRequestPost = async ({ request, env }) => {
  if (!env.REVIEW_DB) return json({ error: "REVIEW_DB is not configured" }, { status: 503 });
  if (!validMutationRequest(request)) return json({ error: "Invalid request" }, { status: 400 });

  try {
    const body = await readBody(request);
    const input = body.report || body;
    const issueId = issueIdFromReport(input);
    const articleSlug = String(input?.articleSlug || "").trim();
    if (!issueId || !articleSlug) return json({ error: "Invalid report" }, { status: 400 });

    const now = new Date().toISOString();
    const report = {
      ...input,
      id: String(input.id || crypto.randomUUID()),
      issueId,
      createdAt: String(input.createdAt || now),
      updatedAt: now
    };
    const payload = JSON.stringify(report);
    await env.REVIEW_DB.prepare(
      `INSERT INTO review_reports (id, issue_id, article_slug, payload, created_at, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(id) DO UPDATE SET
         issue_id = excluded.issue_id,
         article_slug = excluded.article_slug,
         payload = excluded.payload,
         updated_at = excluded.updated_at`
    ).bind(report.id, issueId, articleSlug, payload, report.createdAt, now).run();
    return json({ report }, { status: 201 });
  } catch (error) {
    if (error?.message === "PAYLOAD_TOO_LARGE") return json({ error: "Report is too large" }, { status: 413 });
    if (error instanceof SyntaxError) return json({ error: "Invalid JSON" }, { status: 400 });
    console.error("Unable to create review report", error);
    return json({ error: "Unable to store report" }, { status: 500 });
  }
};

export const onRequestPatch = async ({ request, env }) => {
  if (!env.REVIEW_DB) return json({ error: "REVIEW_DB is not configured" }, { status: 503 });
  if (!validMutationRequest(request)) return json({ error: "Invalid request" }, { status: 400 });

  try {
    const body = await readBody(request);
    const report = body.report || body;
    const id = String(report?.id || "").trim();
    const issueId = issueIdFromReport(report);
    const articleSlug = String(report?.articleSlug || "").trim();
    if (!id || !issueId || !articleSlug) return json({ error: "Invalid report" }, { status: 400 });

    const exists = await env.REVIEW_DB.prepare("SELECT id FROM review_reports WHERE id = ?1").bind(id).first();
    if (!exists) return json({ error: "Report not found" }, { status: 404 });
    const updated = { ...report, issueId, updatedAt: new Date().toISOString() };
    await env.REVIEW_DB.prepare(
      "UPDATE review_reports SET issue_id = ?2, article_slug = ?3, payload = ?4, updated_at = ?5 WHERE id = ?1"
    ).bind(id, issueId, articleSlug, JSON.stringify(updated), updated.updatedAt).run();
    return json({ report: updated });
  } catch (error) {
    if (error?.message === "PAYLOAD_TOO_LARGE") return json({ error: "Report is too large" }, { status: 413 });
    if (error instanceof SyntaxError) return json({ error: "Invalid JSON" }, { status: 400 });
    console.error("Unable to update review report", error);
    return json({ error: "Unable to update report" }, { status: 500 });
  }
};

export const onRequestDelete = async ({ request, env }) => {
  if (!env.REVIEW_DB) return json({ error: "REVIEW_DB is not configured" }, { status: 503 });
  if (!validMutationRequest(request)) return json({ error: "Invalid request" }, { status: 400 });

  try {
    const body = await readBody(request);
    const id = String(body.id || "").trim();
    const issueId = String(body.issueId || "").trim();
    if (id) {
      await env.REVIEW_DB.prepare("DELETE FROM review_reports WHERE id = ?1").bind(id).run();
      return json({ ok: true });
    }
    if (/^20\d{4}$/.test(issueId) && body.all === true) {
      await env.REVIEW_DB.prepare("DELETE FROM review_reports WHERE issue_id = ?1").bind(issueId).run();
      return json({ ok: true });
    }
    return json({ error: "Invalid delete request" }, { status: 400 });
  } catch (error) {
    if (error instanceof SyntaxError) return json({ error: "Invalid JSON" }, { status: 400 });
    console.error("Unable to delete review report", error);
    return json({ error: "Unable to delete report" }, { status: 500 });
  }
};
