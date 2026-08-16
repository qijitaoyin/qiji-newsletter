import { defineConfig } from "astro/config";

const ignoredWatchPath = (path = "") =>
  path.includes("node_modules") ||
  path.includes(".git") ||
  path.includes("dist");

export default defineConfig({
  site: process.env.PUBLIC_SITE_URL || "https://newsletter.qiji.org.tw",
  base: process.env.PUBLIC_BASE_PATH || "/",
  vite: {
    server: {
      watch: {
        ignored: ignoredWatchPath
      }
    }
  }
});
