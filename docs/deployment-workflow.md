# 氣機導引電子報：GitHub 部署、AI API 與正式校對流程

本文是正式上線前的操作文件。目標是讓網站不依賴單一電腦當伺服器，Word 仍作為文章內容來源，GitHub 負責版本控制與部署，Google Drive 負責多人投稿與修正。

## 一、整體資料流

1. 投稿者把 Word 檔放入 Google Drive 的期數資料夾，例如 `各期電子報/202606/`。
2. GitHub Actions 讀取 Google Drive，執行匯入腳本，產生文章資料與校驗報告。
3. 若設定 `OPENAI_API_KEY`，可在部署前產生 AI 建議金句與分類標籤。
4. 網站 build 後先進入 `/review/` 校對頁，校對者檢視正式版面預覽並留下修正意見。
5. 上架人員依待辦回 Word 修正，重新匯入、重新部署預覽。
6. 全部確認後，執行 GitHub Pages 正式部署。

## 二、GitHub Repository 設定

### 1. 第一次上傳

在本機安裝 Git 後，於專案根目錄執行：

```bash
git init
git add .
git commit -m "Initial qiji newsletter site"
git branch -M main
git remote add origin https://github.com/<org-or-user>/<repo>.git
git push -u origin main
```

目前這台電腦的 PowerShell 找不到 `git` 指令；需先安裝 Git for Windows，或在 GitHub Desktop 中加入這個資料夾。

### 2. GitHub Pages

到 GitHub repository：

1. `Settings > Pages`
2. `Build and deployment` 選 `GitHub Actions`
3. 到 `Actions` 手動執行 `Deploy to GitHub Pages`

第一次可先使用 GitHub 提供的網址測試；確認後再把 `newsletter.qiji.org.tw` 指到 GitHub Pages。

### 3. GitHub Variables

到 `Settings > Secrets and variables > Actions > Variables` 設定：

```text
GOOGLE_DRIVE_REMOTE=qiji-drive:各期電子報
OPENAI_MODEL=gpt-5.5
```

`OPENAI_MODEL` 可之後更換，不需要改程式。

### 4. GitHub Secrets

到 `Settings > Secrets and variables > Actions > Secrets` 設定：

```text
RCLONE_CONFIG
OPENAI_API_KEY
```

- `RCLONE_CONFIG`：給 GitHub Actions 讀 Google Drive 用。
- `OPENAI_API_KEY`：給 AI 產生金句與分類標籤用。

若暫時不設定 `OPENAI_API_KEY`，網站仍可部署；只是不會產生新的 AI metadata。

## 三、AI 金句與標籤規則

AI 建議會寫入：

```text
src/data/aiMetadata.json
```

人工校對覆蓋會寫入：

```text
src/data/editorialOverrides.json
```

網站套用優先順序：

1. `editorialOverrides.json`：人工指定金句或標籤，最高優先。
2. `aiMetadata.json`：AI 建議金句或標籤。
3. 原本系統規則：用分類與關鍵字自動補基本標籤。

因此，正式發布後若只是想換金句，不需要改 Word；在校對頁留下「指定金句」意見，由上架人員採用後，發布確認資料會套用到 `editorialOverrides.json`。

本機手動產生 AI metadata：

```bash
pnpm ai:metadata
```

常用環境變數：

```bash
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.5
AI_ISSUE_ID=latest
AI_LIMIT=0
AI_FORCE=0
```

`AI_LIMIT=0` 表示不限制篇數；測試時可設 `AI_LIMIT=1` 先跑一篇。

## 四、最新一期正式校對流程

1. 把最新一期 Word 放入 Google Drive 對應期數資料夾。
2. 在 GitHub Actions 執行 `Deploy to GitHub Pages`，先可設定 `run_ai=false` 測匯入。
3. 開啟部署後網址的 `/review/`。
4. 校對者逐篇看「文章資料、電腦預覽、手機預覽」，有問題就直接在校對頁留下修正意見。
5. 上架人員在「上架人員待辦」依意見回 Word 修正。
6. 修正 Word 後重新執行部署流程，確認頁面已更新。
7. 待辦清空後，看「最後閱讀預覽清單」，確認目錄順序與閱讀頁正常。
8. 確認無誤後，執行正式發布。

目前本機 prototype 仍會下載 `review-publish.json` 作為交接紀錄；上 GitHub 後的下一步，是把「產生發布確認」改成送出 GitHub Actions dispatch，不必人工下載檔案。

## 五、舊稿整理流程

舊稿與最新一期校對分開進行。

- 最新一期：以快速上架、快速校對、快速修正為主。
- 舊稿整理：保留 `/review/` 的「舊稿整理」分頁，逐批確認系統判讀結果。

舊稿若系統能判斷分類、標題、作者、日期，可直接在校對頁確認；若不確定，才回 Word 補成標準模板。

## 六、網域策略

短期建議：

```text
newsletter.qiji.org.tw
```

作為新版電子報子網域。既有 Wix 官網仍在原本網域，先加一個入口連到新版電子報。

未來官網整體重做時，可把主站也搬到 GitHub 管理，再決定是否：

- 保留電子報在 `newsletter.qiji.org.tw`
- 或整合成 `www.qiji.org.tw/newsletter/`

## 七、上線前測試清單

- GitHub Pages workflow 可成功 build。
- `/` 首頁正常。
- `/archive/` 搜尋正常，閱讀全文開新分頁。
- `/review/` 最新一期校對頁正常。
- `/articles/<slug>/` 閱讀頁正常。
- Google Drive 新增或更新 Word 後，重新部署會反映新內容。
- 沒有 `OPENAI_API_KEY` 時部署不會失敗。
- 有 `OPENAI_API_KEY` 時可產生 `reports/ai-metadata-report.json`。
