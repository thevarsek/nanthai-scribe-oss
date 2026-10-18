import { getCollection, render, type CollectionEntry } from "astro:content";
import { docGroups } from "../content.config";

export type Doc = CollectionEntry<"docs">;
export type Group = (typeof docGroups)[number];

/** Sidebar journeys in reading order. Labels are the only place these names appear. */
export const groupLabels: Record<Group, string> = {
  "get-started": "Get started",
  dictate: "Dictate",
  refine: "Refine",
  library: "Library",
  meetings: "Meetings",
  keyboard: "Keyboard",
  dictionary: "Dictionary & learning",
  models: "Models & languages",
  privacy: "Privacy",
  troubleshooting: "Troubleshooting",
};

export const slugOf = (doc: Doc) => doc.id.replace(/^en\//, "");
export const pathOf = (doc: Doc) => "/docs/" + slugOf(doc);
export const platformLabel = (platform: Doc["data"]["platform"]) =>
  platform === "mac" ? "Mac" : platform === "iphone" ? "iPhone" : "Mac and iPhone";

export interface GroupedDocs { id: Group; label: string; entries: Doc[] }
export interface SearchDoc { title: string; path: string; group: string; headings: { text: string; slug: string }[] }

let cache: Promise<{ entries: Doc[]; grouped: GroupedDocs[]; index: SearchDoc[] }> | undefined;

/** Every article in sidebar order, grouped, plus the search index. Built once per build. */
export function loadDocs() {
  cache ??= (async () => {
    const all = await getCollection("docs");
    const rank = (doc: Doc) => docGroups.indexOf(doc.data.group);
    const entries = all.sort((a, b) => rank(a) - rank(b) || a.data.order - b.data.order);
    const grouped = docGroups
      .map((id) => ({ id, label: groupLabels[id], entries: entries.filter((e) => e.data.group === id) }))
      .filter((g) => g.entries.length > 0);
    // Titles and h2/h3 headings only: enough to find an answer, small enough to inline on every page.
    const index: SearchDoc[] = [];
    for (const doc of entries) {
      const { headings } = await render(doc);
      index.push({
        title: doc.data.title,
        path: pathOf(doc),
        group: groupLabels[doc.data.group],
        headings: headings.filter((h) => h.depth === 2 || h.depth === 3).map((h) => ({ text: h.text, slug: h.slug })),
      });
    }
    return { entries, grouped, index };
  })();
  return cache;
}
