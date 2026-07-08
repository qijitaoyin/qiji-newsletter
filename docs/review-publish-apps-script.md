# Review Publish With Google Apps Script

This is the one-click publish bridge for the review page.

The review page is hosted on GitHub Pages, so it cannot safely store a GitHub
token or write back to the repository by itself. Google Apps Script acts as the
small trusted middle layer:

1. Reviewer clicks `送出正式發布` on `/review/`.
2. The review page sends the publish payload to Google Apps Script.
3. Apps Script commits `review-publish.json` to GitHub.
4. Apps Script triggers the `Deploy to GitHub Pages` workflow.
5. The workflow applies `review-publish.json`, builds the site, and deploys.

## 1. Create A GitHub Token

Create a fine-grained personal access token in GitHub.

Repository access:

- `qijitaoyin/qiji-newsletter`

Permissions:

- Contents: read and write
- Actions: read and write

Keep this token private. Do not put it in site code.

## 2. Create The Apps Script

1. Open Google Apps Script.
2. Create a new project, for example `Qiji Newsletter Publish Webhook`.
3. Paste the contents of:

   `docs/google-apps-script-publish-webhook.js`

4. Open `Project Settings > Script Properties`.
5. Add:

```text
GITHUB_TOKEN=<your GitHub token>
GITHUB_OWNER=qijitaoyin
GITHUB_REPO=qiji-newsletter
GITHUB_BRANCH=main
GITHUB_WORKFLOW=deploy-github-pages.yml
RUN_AI=false
AI_ISSUE_ID=latest
AI_LIMIT=0
```

## 3. Deploy As Web App

1. Click `Deploy > New deployment`.
2. Select type: `Web app`.
3. Execute as: `Me`.
4. Who has access: choose the narrowest option that works for your reviewers.
5. Deploy and copy the Web App URL.

## 4. Add The Web App URL To GitHub

In GitHub:

`Settings > Secrets and variables > Actions > Variables`

Add:

```text
REVIEW_PUBLISH_WEBHOOK_URL=<Apps Script Web App URL>
```

Then run `Deploy to GitHub Pages` once. The next published `/review/` page will
enable the `送出正式發布` button.

## Reviewer Flow

1. Open `/review/`.
2. Review the latest issue.
3. Add comments and mark them fixed/done.
4. Confirm the final reading preview.
5. Click `送出正式發布`.
6. Wait for GitHub Actions deployment to finish.

Fallback: the page still has download/copy buttons for the publish JSON. Use
those only if the Apps Script bridge is unavailable.
