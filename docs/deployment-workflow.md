# 氣機導引電子報：部署、自動匯入、AI 與校對流程

## 目前架構

- 網站程式與部署流程放在 GitHub repository：`qijitaoyin/qiji-newsletter`
- 正式電子報網域預計使用：`newsletter.qiji.org.tw`
- 文章來源預計使用 Google Drive：`qijitaoyin@gmail.com` 帳戶中的共用資料夾
- 校對頁：`/review/`
- 發布方式：校對頁送出發布確認後，Apps Script 會寫入 GitHub 並觸發 GitHub Actions 重新部署

## DNS 設定

在 `qiji.org.tw` 的 DNS 管理後台新增：

```text
Type: CNAME
Name: newsletter
Value: qijitaoyin.github.io
TTL: Auto 或 3600
```

設定後 GitHub Pages 會使用 `public/CNAME` 裡的 `newsletter.qiji.org.tw`。

若 DNS 後台要求填完整主機名稱，`Name` 可填：

```text
newsletter.qiji.org.tw
```

## Google Drive 自動匯入

GitHub Actions 使用 `rclone` 從 Google Drive 同步文章資料。

需要在 GitHub repository 設定：

### Variables

```text
GOOGLE_DRIVE_REMOTE=qiji-drive:各期電子報
OPENAI_MODEL=gpt-5.5
REVIEW_PUBLISH_WEBHOOK_URL=<Apps Script Web App URL>
```

### Secrets

```text
RCLONE_CONFIG=<rclone config 內容>
OPENAI_API_KEY=<OpenAI API key>
```

`RCLONE_CONFIG` 必須由已授權 `qijitaoyin@gmail.com` Google Drive 的 rclone 設定產生。這是讓 GitHub Actions 能讀取 Google Drive 的關鍵。

## AI 金句與標籤

AI 腳本：

```bash
pnpm ai:metadata
```

輸出位置：

```text
src/data/aiMetadata.json
reports/ai-metadata-report.json
```

規則：

- 沒有 `OPENAI_API_KEY` 時會自動跳過，不影響部署
- 有 `OPENAI_API_KEY` 且 workflow input `run_ai=true` 時才會呼叫 API
- 金句控制在 50 字以內
- 人工指定金句或標籤仍以校對頁送出的發布確認資料優先

## 正式校對與發布流程

1. 將最新一期 Word 放入 Google Drive 的 `各期電子報/YYYYMM/`
2. 執行 GitHub Actions `Deploy to GitHub Pages`
3. 系統同步 Google Drive、產生文章資料、建立校對頁
4. 校對小組在 `/review/` 檢視桌機與手機預覽
5. 若有問題，回 Word 修改後重新執行部署
6. 全部確認後，在 `/review/` 送出正式發布
7. Apps Script 寫入 `review-publish.json` 並觸發 GitHub Actions
8. GitHub Pages 完成正式網站更新

## 本機測試

```bash
pnpm install
pnpm generate
pnpm ai:metadata
pnpm build
```

若只測一篇 AI：

```bash
AI_LIMIT=1 pnpm ai:metadata
```

Windows PowerShell：

```powershell
$env:AI_LIMIT="1"
pnpm ai:metadata
```
