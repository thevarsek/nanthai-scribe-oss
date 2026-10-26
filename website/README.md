# NanthAi Scribe website

Marketing and docs site for scribe.nanthai.tech, built with Astro 5. Static Netlify output,
English copy, self-hosted Geist under SIL OFL. No analytics, cookies, product screenshots,
client framework or external runtime requests. Nothing in the build publishes the site.

## Develop and verify

Run commands in `website/`:

```sh
npm install
npm run dev            # local Astro server; stop it when finished
npm run check          # Astro and TypeScript diagnostics
npm run build          # 33 static HTML pages + sitemap
npm run check:layout   # built dist, one temporary local server, one Playwright browser
```

The layout script owns its local server and closes both server and browser in `finally`.
It checks every generated page at 1440, 1024, 768 and 390 px with the site menu open and
closed (and the docs panel open on small screens): text collisions, horizontal overflow,
AA contrast, local links and fragments, SEO metadata and sitemap, layout shift (CLS ≤ 0.01),
landmarks and keyboard focus, FAQ disclosures, the empty appcast, reduced motion (scene
final frames and every reveal target visible at once), normal motion (lazy scene imports,
offscreen pause, the full hero story, every reveal target in after scrolling), docs search
(index covers every article; title and heading hits; arrow keys, Enter and Escape) and
browser errors. Text clipped inside a scrolling container (the docs sidebar) is ignored by
the collision check. The Mac release URL is the one intentional missing download; the
script verifies its configured URL and button copy without requesting the binary. The
iPhone listing fragment is also an intentional placeholder; all other local targets must exist.
Until `site.launched` is true every download button (hero, final sections, Download page
and the header) renders as a disabled "Coming soon" with no href; the script asserts
whichever state the flag selects. Launch is a one-line change in `src/lib/site.ts`.

Screenshots go to `/tmp/web4-shots/` (override with `SHOTS_DIR`): Home at 1440 and 390,
the home iPhone section, Features at 1440 and 390, Privacy at 1440, Download at 390,
the Mac getting-started article at 1440 and 390, and the docs search open at 1440.
Chromium must be available to Playwright (`npx playwright install chromium` on a fresh
machine). Run browsers sequentially on this shared Mac; do not run another browser
alongside the check script. The script prints PASS lines for layout, accessibility,
links/SEO, motion, launch state, docs search, runtime and screenshots. Re-run it after `npm run build`
whenever rendered content changes and look at the PNGs. No generated files belong in commits.

## Structure

- `src/layouts/Base.astro`: landmarks, metadata, preloaded fonts, shared header/footer,
  the `html.js` flag and the reveal script.
- `src/layouts/Docs.astro`: search field, sidebar grouped by journey, article, on-page
  list with active heading, previous/next. The search index (titles + h2/h3 headings) is
  built at build time by `src/lib/docs.ts` and inlined as JSON; the client script matches
  against it with no requests.
- `src/lib/docs.ts`: group order and labels, sorted articles, search index (cached per build).
- `src/lib/rehype-callouts.mjs`: `> Tip:`, `> Note:`, `> Warning:` blockquotes become
  `<aside class="callout …">` with a title.
- `src/components/Scene.astro`: reusable illustrated scenes with reserved aspect ratios.
- `src/lib/scene-markup.mjs`: approved mockup drawings; no product images.
- `src/scripts/scene-driver.js`: visibility, reduced motion and scene scaling.
- `src/scripts/scenes/`: independent lazy timelines; the hero story lasts 22 seconds.
- `src/scripts/reveal.js`: one IntersectionObserver that adds `.in` to `[data-reveal]`
  elements as they enter view, then stops watching them.
- `src/styles/brand.css`: tokens. Page background #0A0E14, alternating bands #0E131B;
  navy #16212E and raised #1F2D3D are accent surfaces (cards, stages, keycaps, callouts,
  the current docs page). Coral #FF7A59 for primary actions, white #F2F4F7 text, sky
  #1EC8FF and amber #FFC235. Gradients only on Trio ribbons and listening rings.
- `src/styles/poster.css`: layout, type, sections, components and the reveal rules.
  `src/styles/docs.css`: docs layout, callouts, keycaps, search, pager.
- `src/content/docs/en/`: 24 Markdown guides. Frontmatter: title, description, `group`
  (get-started, dictate, refine, library, meetings, keyboard, dictionary, models, privacy,
  troubleshooting), numeric `order` within the group, and `platform` (`mac`, `iphone`,
  `both`). The sidebar, docs home, search index and pager build from it. Keycaps are
  inline `<kbd>`; callouts are blockquotes starting with `Tip:`, `Note:` or `Warning:`.
- `src/lib/site.ts`: canonical origin, support mailbox, requirements, model facts and
  **release URL placeholders**: `downloads.mac` is `/download/NanthAi-Scribe.dmg`;
  `stores.iphone` is the future App Store listing. Replace these when releases are public.

Fonts in `public/fonts/` come from the approved mockups; the OFL licence is alongside them.

## Design rules (owner, round 3)

One idea per section: a headline, a short paragraph, one visual. No eyebrow labels,
section numbers, fact chips, mini-labels or watermark text. Copy is short and plain; the
tagline stays "Say it. Scribe it. Send it." The hero has no gradient ring; the story scene
carries its own small listening ring. Text and sections reveal on scroll with a short
translate/fade and a 90 ms stagger inside `[data-reveal="group"]`; the hero rises on load.
`prefers-reduced-motion` shows everything immediately with no transitions.

## Pages

Home, Download, How it works, Features, Privacy (including the full policy), Docs,
Support, 404. There is no changelog. The top navigation is How it works, Features, Docs
plus the download button; Privacy lives in the footer with the legal links.

Features is six callouts, each with its own scene (tones and Style by app, meetings,
swipe typing, auto-learning, the talk shortcut and pedal, transcribing a recording),
followed by a Mac/iPhone comparison grouped by journey. The comparison uses ✓, — and
short notes; its header sticks under the site bar and the rows stack per platform at
480 px. How it works keeps the step-by-step flow and links to Features for the keyboard
rather than repeating it. The home iPhone scene types on the letters first, then taps
Talk. Meetings copy always carries "Always ask before you record."; the privacy policy
and the meetings docs open with the consent warning. Docs by journey: Get started (Mac, iPhone, Updates on Mac);
Dictate (Mac, Talk shortcut, iPhone); Refine (Refine and tones, Style by app); Library
(Library and the editor, Recently Deleted, Transcribe a recording, Backup); Meetings (Mac,
iPhone, Audio playback); Keyboard (The iPhone keyboard, Swipe typing); Dictionary &
learning (Dictionary, Auto-learning and Corrections, Snippets); Models & languages
(Languages, Optional models); Privacy and permissions; Troubleshooting.

## Motion and accessibility

Each scene imports only its own timeline on entering view. Offscreen scenes and hidden
browser tabs stop their timers. Reduced motion uses a final frame rendered at build time
and loads no timeline modules. The hero is an illustrative story: Scribe inserts text; the
user chooses when to send in the destination app. The drawings have descriptive accessible
names and their internal text is decorative. Navigation uses semantic links, buttons with
expanded state, Escape support and visible amber focus rings. Docs search is a combobox
with a listbox; platform captions occupy their own line in the docs sidebar.

## Launch copy and hosting

Copy follows README.md, DESIGN.md, DESIGN-IOS-V2.md (through v2.13) and BACKLOG.md
(PAR-1 to PAR-3) at 18 October 2026. Both releases are **unreleased**. Mac ships as a
free, Developer ID signed, Apple-notarized DMG from this website; iPhone ships on the
App Store. Recently Deleted, Transcribe a recording, Backup/import, meeting audio playback,
keyboard Numbers and Reset typing learning are documented as features per the backlog.

Mac setup: download the DMG, drag Scribe to Applications, open it, grant Accessibility and
Microphone access, then pick the Talk shortcut. The app menu offers **Check for Updates…**.
Automatic update checks are off by default; Settings › General can turn them on. Besides
model downloads, this update check is the only network request the Mac app can make.

`public/appcast.xml` is a valid empty Sparkle RSS feed. The release script fills its signed
release items.

Apple speech locales are discovered by the app at runtime; the docs list the verified Apple
language families and regional variants, every Parakeet language, and all 34 autocorrect
and swipe lexicons. Apple availability remains device-dependent.

`netlify.toml`: repository base `website`, build `npm run build`, publish `dist`, Node 22.
Static output includes canonical/OG metadata, a local social image, robots.txt and sitemap.
The candidate canonical origin remains `https://scribe.nanthai.tech`; confirm when publishing.
The iPhone store link is the real App Store URL; flip `launched.iphone` in `src/lib/site.ts`
after approval to replace "Coming soon" with Apple's official badge (`public/badges/app-store.svg`,
unmodified, from Apple's marketing toolbox). No deploy, DNS or Netlify publishing commands are part of this work.

The Astro 5 toolchain reports npm audit advisories in Astro, sharp and esbuild. This site
publishes only prebuilt static files and uses none of the affected server features,
untrusted templates or image optimisation. Review the toolchain before public deployment.
