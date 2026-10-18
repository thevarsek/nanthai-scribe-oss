// @ts-check
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import rehypeCallouts from "./src/lib/rehype-callouts.mjs";

// Static output only: no server, no adapters, no client frameworks.
// Navigation is shared; each illustrated scene loads its timeline on scroll.
export default defineConfig({
  site: "https://scribe.nanthai.tech",
  output: "static",
  trailingSlash: "never",
  build: { format: "file" },
  integrations: [sitemap({ filter: (page) => !page.endsWith("/404") })],
  markdown: { rehypePlugins: [rehypeCallouts] },
  i18n: {
    // English only today; add "it" here and a src/content/docs/it/ folder to localise.
    defaultLocale: "en",
    locales: ["en"],
    routing: { prefixDefaultLocale: false },
  },
  prefetch: false,
  devToolbar: { enabled: false },
});
