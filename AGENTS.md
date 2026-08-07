# Project Workflow Rules

## Local Preview Before Publishing

- Make layout, content parsing, and UI changes locally first.
- Show or verify the result in the local preview site before any GitHub action.
- Do not commit, push, or deploy unless the user explicitly asks for it with words such as `commit`, `push`, `deploy`, `正式發布`, or `上傳到 GitHub`.
- If a change affects article import output, rebuild or reimport locally first and report what changed.
- GitHub Pages deployment is a separate publishing step, not part of ordinary editing.

## AI Usage

- Do not run paid AI metadata generation unless the user explicitly asks for it.
- Default import or deploy runs should use AI generation disabled.

## Homepage Scope

- Do not change the homepage layout unless the user explicitly asks to edit the homepage in the current request.

## Article Source Path

- Word article imports must read from the qijitaoyin Google Drive path only:
  `H:\我的雲端硬碟\氣機導引\電子報新版網頁\各期電子報`
- Do not infer the article source from the current project folder, Codex working directory, `G:`, or any local fallback copy.
- If the `H:` source path is unavailable, stop and report that Google Drive/qijitaoyin is not mounted or synced. Do not silently fall back to `各期電子報` inside the project folder.
- When checking whether a new issue such as `202608` exists, inspect the `H:` source path first.
