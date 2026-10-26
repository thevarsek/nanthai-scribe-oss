import { getCollection, type CollectionEntry } from "astro:content";

export type Guide = CollectionEntry<"guides">;
export const slugOf = (guide: Guide) => guide.id.replace(/^en\//, "");
export const pathOf = (guide: Guide) => "/guides/" + slugOf(guide);

/** Keep index and related links in the same stable reading order. */
export async function loadGuides() {
  return (await getCollection("guides")).sort((a, b) => a.data.title.localeCompare(b.data.title, "en"));
}

/** Topic order follows the main tasks readers come to the guides for. */
export const topics = ["Dictation on Mac", "iPhone", "Meetings and notes", "Languages and vocabulary", "Comparisons"] as const;

export function groupGuides(guides: Guide[]) {
  return [...topics, "Other guides"].map(topic => ({
    topic,
    entries: guides.filter(guide => (guide.data.topic ?? "Other guides") === topic),
  })).filter(group => group.entries.length > 0);
}

/** Prefer the current topic, filling shorter groups from the stable index order. */
export function moreGuides(guides: Guide[], current: Guide) {
  const others = guides.filter(guide => guide.id !== current.id);
  return [
    ...others.filter(guide => guide.data.topic === current.data.topic),
    ...others.filter(guide => guide.data.topic !== current.data.topic),
  ].slice(0, 3);
}
