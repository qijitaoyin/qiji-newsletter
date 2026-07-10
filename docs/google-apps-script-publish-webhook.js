/**
 * Qiji Newsletter review publish webhook.
 *
 * Deploy this file as a Google Apps Script Web App. The review page sends
 * review-publish.json or reimport requests here; this script commits publish
 * confirmations to GitHub when needed and triggers the GitHub Pages deployment
 * workflow.
 *
 * Required Script Properties:
 * - GITHUB_TOKEN: fine-grained token with Contents read/write and Actions write
 * - GITHUB_OWNER: qijitaoyin
 * - GITHUB_REPO: qiji-newsletter
 *
 * Optional Script Properties:
 * - GITHUB_BRANCH: main
 * - GITHUB_WORKFLOW: deploy-github-pages.yml
 * - RUN_AI: true
 * - AI_ISSUE_ID: latest
 * - AI_LIMIT: 0
 */

function doPost(e) {
  try {
    const payloadText = getPayloadText_(e);
    const payload = JSON.parse(payloadText);
    validatePayload_(payload);

    const props = PropertiesService.getScriptProperties();
    const owner = requiredProp_(props, "GITHUB_OWNER");
    const repo = requiredProp_(props, "GITHUB_REPO");
    const token = requiredProp_(props, "GITHUB_TOKEN");
    const branch = props.getProperty("GITHUB_BRANCH") || "main";
    const workflow = props.getProperty("GITHUB_WORKFLOW") || "deploy-github-pages.yml";

    if (payload.action === "reimport") {
      dispatchWorkflow_({
        owner,
        repo,
        token,
        workflow,
        branch,
        inputs: {
          run_ai: "false",
          ai_issue_id: payload.issueId || props.getProperty("AI_ISSUE_ID") || "latest",
          ai_limit: "0",
          sync_drive: "true",
          review_publish_json: ""
        }
      });

      return jsonResponse_({
        ok: true,
        message: "Reimport request was sent to GitHub Actions.",
        actionsUrl: `https://github.com/${owner}/${repo}/actions/workflows/${workflow}`
      });
    }

    validatePublishPayload_(payload);

    putGitHubFile_({
      owner,
      repo,
      token,
      branch,
      filePath: "review-publish.json",
      content: JSON.stringify(payload, null, 2) + "\n",
      message: "Update review publish confirmation"
    });

    dispatchWorkflow_({
      owner,
      repo,
      token,
      workflow,
      branch,
      inputs: {
        run_ai: props.getProperty("RUN_AI") || "true",
        ai_issue_id: props.getProperty("AI_ISSUE_ID") || "latest",
        ai_limit: props.getProperty("AI_LIMIT") || "0",
        sync_drive: "true",
        review_publish_json: ""
      }
    });

    return jsonResponse_({
      ok: true,
      message: "Review publish confirmation was sent to GitHub.",
      actionsUrl: `https://github.com/${owner}/${repo}/actions/workflows/${workflow}`
    });
  } catch (error) {
    return jsonResponse_(
      {
        ok: false,
        error: String(error && error.message ? error.message : error)
      },
      500
    );
  }
}

function doGet() {
  return jsonResponse_({
    ok: true,
    message: "Qiji Newsletter publish webhook is running."
  });
}

function setScriptProperties(config) {
  if (!config || typeof config !== "object") {
    throw new Error("setScriptProperties requires a config object.");
  }
  PropertiesService.getScriptProperties().setProperties(config, true);
  return {
    ok: true,
    savedKeys: Object.keys(config)
  };
}

function getPayloadText_(e) {
  if (e && e.postData && e.postData.contents) {
    return e.postData.contents;
  }
  if (e && e.parameter && e.parameter.payload) {
    return e.parameter.payload;
  }
  throw new Error("Missing POST payload.");
}

function validatePayload_(payload) {
  if (!payload || typeof payload !== "object") {
    throw new Error("Payload must be a JSON object.");
  }
}

function validatePublishPayload_(payload) {
  if (!payload.metadataOverrides || typeof payload.metadataOverrides !== "object") {
    throw new Error("Payload is missing metadataOverrides.");
  }
  if (!payload.reports || !Array.isArray(payload.reports)) {
    throw new Error("Payload is missing reports array.");
  }
}

function requiredProp_(props, name) {
  const value = props.getProperty(name);
  if (!value) throw new Error(`Missing Script Property: ${name}`);
  return value;
}

function putGitHubFile_({ owner, repo, token, branch, filePath, content, message }) {
  const url = `https://api.github.com/repos/${owner}/${repo}/contents/${encodeURIComponent(filePath)}`;
  const existing = githubFetch_(url + `?ref=${encodeURIComponent(branch)}`, token, {
    method: "get",
    muteHttpExceptions: true
  });

  let sha = "";
  if (existing.status === 200) {
    sha = JSON.parse(existing.text).sha || "";
  } else if (existing.status !== 404) {
    throw new Error(`Cannot read existing ${filePath}: ${existing.status} ${existing.text}`);
  }

  const body = {
    message,
    branch,
    content: Utilities.base64Encode(content, Utilities.Charset.UTF_8)
  };
  if (sha) body.sha = sha;

  const saved = githubFetch_(url, token, {
    method: "put",
    contentType: "application/json",
    payload: JSON.stringify(body),
    muteHttpExceptions: true
  });

  if (saved.status < 200 || saved.status >= 300) {
    throw new Error(`Cannot write ${filePath}: ${saved.status} ${saved.text}`);
  }
}

function dispatchWorkflow_({ owner, repo, token, workflow, branch, inputs }) {
  const url = `https://api.github.com/repos/${owner}/${repo}/actions/workflows/${encodeURIComponent(workflow)}/dispatches`;
  const response = githubFetch_(url, token, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify({
      ref: branch,
      inputs
    }),
    muteHttpExceptions: true
  });

  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Cannot dispatch workflow: ${response.status} ${response.text}`);
  }
}

function githubFetch_(url, token, options) {
  const response = UrlFetchApp.fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.headers || {})
    }
  });
  return {
    status: response.getResponseCode(),
    text: response.getContentText()
  };
}

function jsonResponse_(data) {
  return ContentService.createTextOutput(JSON.stringify(data, null, 2)).setMimeType(
    ContentService.MimeType.JSON
  );
}
