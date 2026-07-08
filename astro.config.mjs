import { defineConfig } from "astro/config";

export default defineConfig({
  site: process.env.PUBLIC_SITE_URL || "https://newsletter.qiji.org.tw",
  base: process.env.PUBLIC_BASE_PATH || "/"
});
