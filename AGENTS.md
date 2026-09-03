# Qiji Newsletter Project Rules

## Canonical Paths

- The Git project root is `C:\Projects\qiji-newsletter`. Keep the repository and `.git` on the local disk, never on a cloud-synced drive.
- Word articles must be read only from `H:\我的雲端硬碟\氣機導引\電子報新版網頁\各期電子報`.
- Never use `G:`, the project tree, or another cached copy as a Word-source fallback. If `H:` is unavailable, stop and report it.

## Editing And Publishing

- Make and verify layout, parser, import, and content changes locally first.
- Reimport or rebuild locally when a change affects generated article output, then report the meaningful result.
- Do not commit, push, deploy, publish an issue, change DNS, or mutate a remote service unless the user explicitly asks for that action.
- Do not change the homepage unless the current request explicitly includes it.
- Preserve unrelated user changes. Never use destructive Git cleanup, hard reset, force push, or delete `.git`.

## Import And Review State

- Determine Word changes from stable article content: visible text, meaningful Word formatting/structure, and embedded image content. File timestamps, paths, cache versions, generated output differences, or metadata ordering alone are not content changes.
- A first import is reviewable. After an issue is published, unchanged articles remain approved and the issue stays out of old-draft review. Only articles whose stable content signature changed return to manual review.
- Keep publication baselines and review decisions per issue and per source article. Never reset all articles in an issue because one article changed.
- The newest imported issue becomes the current review issue; an older published issue appears in old-draft review only when a real article-content change is detected.
- Counts shown in review must be derived from the same article-level statuses used by the cards and publish gate.

## Word Fidelity

- Preserve all visible paragraph text, numbering, and list markers regardless of whether a paragraph is classified as body, heading, subheading, quotation, or list. Classification must never make content disappear.
- Respect explicit Word styles and list semantics before heuristics. Map Word `Title` / `標題` and `Heading 2` / `標題 2` to level 2; map `Subtitle` / `副標題`, `Heading 3` / `標題 3`, and `小標題` to level 3. Article bodies do not use level 1.
- Preserve automatic bulleted and numbered lists as lists rather than promoting them to headings solely because they are numbered.
- Convert paired `[古文引述開始]` / `[古文引述結束]` markers, including accepted bracket variants, into one quotation block and hide only the marker text.
- Parser-rule changes require a targeted fixture or regression check for the reported Word pattern plus a local rendered-page check.

## AI Metadata And Images

- Reuse existing valid metadata. Generate only missing metadata for new or genuinely changed articles; do not regenerate an entire archive by default.
- Codex must not directly run a paid AI API unless the user explicitly asks. Local Ollama/Qwen/KIMI-compatible generation is preferred for local work.
- The production review-sync workflow may use its configured KIMI secret only when an imported article lacks required metadata. An ordinary push must not regenerate metadata unnecessarily.
- Never print, commit, or expose API tokens, `.env` files, or credentials.
- Keep article image selection, attribution, and fallback behavior deterministic enough that a failed image lookup cannot erase an article or overwrite an unrelated article's image.

## Deployment

- Cloudflare Pages is the primary host for `newsletter.qiji.org.tw`; GitHub remains the source of truth and rollback history. Follow the repository workflow for any configured secondary deployment.
- Before a requested push, inspect staged and unstaged changes, include only intentional files, run relevant checks, and verify the resulting deployment and public URLs.
