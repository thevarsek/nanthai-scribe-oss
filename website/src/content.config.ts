import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

// Docs are Markdown under src/content/docs/<locale>/. The slug drops the locale folder for
// the default locale, so src/content/docs/en/dictionary.md becomes /docs/dictionary.
// `group` places the article in the sidebar journey; `order` sorts it within the group.
export const docGroups = [
  "get-started", "dictate", "refine", "library", "meetings",
  "keyboard", "dictionary", "models", "privacy", "troubleshooting",
] as const;

const docs = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/docs" }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    group: z.enum(docGroups),
    order: z.number(),
    platform: z.enum(["mac", "iphone", "both"]).default("both"),
  }),
});

export const collections = { docs };
