# NanthAi Scribe — Design

Owner: lead (Claude). Implementers build these screens exactly as specified, using the
components in `Sources/ScribeUI`. Do not add colours, fonts, gradients, shadows,
illustrations, emoji or copy that isn't here. When something isn't specified, use the
plain native control with default styling and leave a `// DESIGN:` comment for review.

## Principles
- **Quiet tool, loud moment.** The app is invisible until you talk; the HUD/keyboard is
  where brand lives. Settings are native and plain.
- **Native first.** macOS: `Form` with `.formStyle(.grouped)`, standard toolbar, SF
  Symbols. iOS: `List`/`Form` inset grouped, `NavigationStack`. No custom chrome.
- **Copy names the thing.** Short, literal, sentence case. No exclamation marks, no
  "Supercharge", no "magic", no "AI-powered".
- **Privacy is stated, not marketed.** One plain line where it matters: "Runs on this
  Mac. Audio never leaves your device."

## Tokens (`ScribeUI/Brand.swift`)
| Token | Value | Use |
|---|---|---|
| `white` | #F2F4F7 | Trio left bar |
| `sky` | #1EC8FF | Trio ribbon bottom |
| `ink` | #0A0E14 | Mac HUD surface; matches the website ground |
| `navy` | #16212E | Keyboard surface, app icon ground |
| `navyRaised` | #1F2D3D | Raised elements on navy (chips, keys) |
| `cyan` | #26C6DA | Gradient start |
| `amber` | #FFC235 | Gradient middle |
| `coral` | #FF5A4A | Gradient end; app tint/accent on light surfaces |
| `gradient` | cyan → amber (0.55) → coral, leading → trailing | Waveform, mic ring, active chip stroke. Never as a fill behind text. |
| `textOnNavy` | white 90% | Primary text on navy |
| `secondaryOnNavy` | white 55% | Hints on navy |
| `error` | #FF8A80 | Error text on navy |

App-wide tint (`.tint`) is `coral`. Typography is the system font only: HUD 13 pt
medium; hints 11 pt regular; chips 11 pt semibold. Corner radii: HUD 28 continuous,
chips capsule, keyboard keys 10 continuous.

## Components (`ScribeUI`) — built by the lead
- `WaveBars(level:active:)` — 7 capsule bars, 3 pt wide, gradient fill.
- `ModeChip(_ mode:)` — capsule, `navyRaised` fill, 1 pt gradient stroke, SF Symbol +
  label, 11 pt semibold `textOnNavy`. Modes: `.handsFree` (lock.fill, "Hands-free"),
  `.polish` (wand.and.stars, "Refine"), `.editSelection` (text.cursor, "Edit selection"),
  `.translate(String)` (globe, "→ English").
- `ShimmerText(_:)` — text with a slow gradient sweep, for "Refining…".
- `MicButton(state:)` — circle, navy fill, 3 pt gradient ring; idle mic.fill; listening
  ring pulses with level; busy shows a rotating gradient arc.

## Mac — HUD (M1)
Bottom-centre floating bar (existing). Layout: `WaveBars` left, text right, and a chip
row **above the text** when any mode is active.

| State | Chip row | Text | Hint line (11 pt, secondaryOnNavy) |
|---|---|---|---|
| Listening (hold) | — | live text / "Listening…" | — |
| Hands-free | `handsFree` | live text | "Return to finish · Esc to cancel" |
| Refine (+ hands-free) | `polish` (+ `handsFree`) | live text | hands-free hint if relevant |
| Edit selection | `editSelection` | live text of the instruction, or "Say what to change" | "Release to apply" (or hands-free hint) |
| Output language set | add `translate("English")` | | |
| Refining / Editing | same chips | `ShimmerText("Refining…")` / `"Editing…"` | — |
| Error | — | error message, `error` colour, 4 s | — |

Bars are flat (inactive) during Refining/Editing. No other animation.

## Mac — menu bar menu
```
Hold Right ⌥ to dictate                       (disabled text)
⌘ while holding: Refine · Shift: hands-free   (disabled text, small)
────────────────
Recent                                     ▸
Languages: IT, EN-GB                       ▸
Output language: Same as spoken            ▸
────────────────
Settings…                                 ⌘,
Quit NanthAi Scribe                       ⌘Q
```
"Dictation key" and "Sounds" move into Settings (M2).

## Mac — Settings window (M2)
Single window, 520 pt wide (600 pt from M8), `TabView` with toolbar-style tabs (SF Symbols):

**General** (gearshape)
- Dictation key: Picker (Right ⌥ Option · Right ⌘ Command · fn)
- Shortcuts reference: a `LabeledContent` list — "Hold key: dictate", "+ Shift: hands-free",
  "+ ⌘: Refine", "Select text, then + ⌘: edit selection"
- Sounds: Toggle
- Open at login: Toggle

**Languages** (globe)
- Section "Dictation languages" footer: "Pick up to 3. Scribe detects which one you're
  speaking." — list of languages with checkmarks (installed Apple languages first).
- Section "More languages" footer: "Adds 19 more European languages. Runs on this Mac.
  Speech model by NVIDIA." — row: "Language pack · 483 MB" (size from `ModelCatalog`) with Download / progress /
  Delete.

**Refine** (wand.and.stars)
- Engine: Picker — "Apple Intelligence (built-in)" · "Gemma 4 (4.36 GB download)" (size from `ModelCatalog`; just "Gemma 4" once installed); when
  Gemma isn't downloaded, a Download button + progress under the picker.
- Output language: Picker — "Same as spoken" + chosen languages.
- Use screen context: Toggle, footer "Reads the window you're dictating into to spell
  names right and understand what you're replying to. Stays on this Mac."

**Privacy** (hand.raised)
- Keep history: Picker — Off · 1 day · 30 days · Forever
- Clear history: destructive button with confirmation
- Text: "Audio is processed on this Mac and never stored or sent anywhere."

**About** (info.circle)
- App icon 64 pt, "NanthAi Scribe", version.
- Credits: "Speech recognition: Apple. Optional language pack: NVIDIA Parakeet TDT 0.6B
  v3 (CC BY 4.0). Optional rewrite model: Google Gemma 4 (Apache 2.0)."

## Mac — Onboarding (M2)
Shown on first launch, 480×420 window, navy background, centred column, step dots at top.
1. Icon 96 pt · "Dictate anywhere on your Mac" · "Hold a key, talk, release. Your words
   appear wherever you're typing." · [Continue]
2. "Allow Accessibility" · "Lets Scribe notice the dictation key and type for you." ·
   [Open System Settings] · live ✓ when granted, then auto-advance.
3. "Allow the microphone" · [Allow] · ✓.
4. "Try it" · large key-cap visual reading "Right ⌥" · "Hold it and say something." ·
   a text field that receives the test dictation · [Done].
Buttons: `.borderedProminent` with coral tint. Text white/secondaryOnNavy.

iOS v2 is specified in [DESIGN-IOS-V2.md](DESIGN-IOS-V2.md), which supersedes the
iOS layouts below. It adds `TrioMark`, `RefineGlyph`, a flat Talk capsule and a
clock-driven busy ring. The Mac keeps its existing components and layout.

## iOS — App (M6)
`TabView` with 3 tabs, standard iOS chrome, coral tint, system backgrounds (light/dark).

**Dictate** (waveform)
- Top: session status row — green dot "Ready for the keyboard · 4:12 left" / "Not running".
- Centre: `MicButton` 96 pt on a navy rounded card (radius 28) with live text under it
  (navy card, white text). Tap to start/stop. Below: segmented control "Dictate | Refine".
- After a result: the text in a card with [Copy] [Share]. Bottom: "Recent" list (last 20).

**Keyboard** (keyboard)
- Setup checklist (each row ✓ when done): "Add NanthAi Scribe keyboard" (deep link to
  Settings), "Allow Full Access" (explain: "Needed so the keyboard can talk to the app.
  Nothing you type is collected."), "Try it" (text field).
- How it works: 3 numbered rows: "Tap the mic on the keyboard" · "Scribe opens briefly to
  start listening — swipe back" · "Talk, then tap ✓".

**Settings** (gearshape) — mirrors Mac: Languages, Language pack, Refine engine + Gemma
download, Output language, Session length (1/5/15 min), History, About + credits.

## iOS — Keyboard (M6)
Height 216 pt (iPhone portrait). Background `navy`. Not a QWERTY keyboard.
```
┌──────────────────────────────────────────────┐
│ [Refine ◦]                       [🌐] [⌫]   │  top row: ModeChip toggle left;
│                                              │  next-keyboard + delete keys right
│            live text / hint (2 lines)        │  13 pt textOnNavy, centred
│                                              │
│      [ ⏎ ]        (  MicButton 72 pt  )   [ ␣ ] │  bottom row
└──────────────────────────────────────────────┘
```
- Keys: `navyRaised` fill, radius 10, SF Symbols in white 90%, 44 pt min hit target.
- Refine chip: off = plain `navyRaised` capsule "Refine"; on = `ModeChip(.polish)`.
- When the host field has selected text the mic area hint reads "Say what to change" and
  the chip row shows `ModeChip(.editSelection)`.
- States of the hint text: idle "Tap to dictate"; no session "Tap to start Scribe";
  starting "Opening Scribe… swipe back when it's listening"; listening = live text with
  `MicButton(.listening)` (tap again to finish); processing "Refining…" (ShimmerText);
  error message in `error` colour.
- Globe key only when `needsInputModeSwitchKey`.

## Mac — Meetings (M7)
A real window (the app gains a Dock icon only while it's open; `NSApp.setActivationPolicy`).

**Start/stop**
- Menu bar menu, new top section: "Record meeting" (record.circle) / "Stop recording ·
  12:04" while recording. Menu bar glyph shows a small coral dot at top-right while
  recording (draw into `MenuBarIcon`).
- On first start per session, a sheet: "Recording this meeting" · "Ask everyone for
  permission before you record. Recording laws vary by country." · [Start recording] [Cancel],
  with a "Don't show again" checkbox.
- Before capture, prepare and verify the meeting language's exact Apple module configuration,
  with the existing asset progress; reservation recovery releases only disabled languages.
  After the reservation request, an equivalent installed locale permits analysis even when module status is stale.
- While recording, the HUD is NOT shown (dictation keeps working as normal).

**Window** — `NavigationSplitView`, 900×600 default, standard toolbar.
- Sidebar: meetings grouped by day (Today / Yesterday / date). Row: title (default
  "Meeting at 14:30", editable), duration, speaker count. Recording meeting pinned on
  top with a coral "● Recording" label.
- Detail, top to bottom:
  - Title (editable, `.title2` semibold), metadata line (date · duration · app if known).
  - **Summary** section (generated after stop): 3–6 bullet points, then "Action items"
    as a checklist (`Toggle` style checkbox) with owners when spoken. While generating:
    `ProgressView` + "Summarising…". [Regenerate] small borderless button.
  - **Transcript**: list of turns. Each turn: speaker name (semibold, colour from a fixed
    6-colour set derived from the brand: cyan, amber, coral, and their 60% tints — "You"
    is always coral), timestamp (secondary, monospaced digits), text. Speaker names are
    buttons → rename popover (applies to all their turns).
- Toolbar: [Copy transcript] [Export ▾ (Markdown, Plain text)] [Delete] (confirmation).
- Empty state: `ContentUnavailableView("No meetings yet", systemImage: "waveform",
  description: "Choose Record meeting from the menu bar during a call.")`.
- Settings › Meetings (new tab, record.circle): "Show reminder before recording"
  toggle; "Keep recordings' audio" toggle (default off — keep transcripts only).

## Mac — Meetings v2 (M17b)
Builds on M17a (crash-safe capture, health state, processing steps). Everything stays in the
Library window; no new colours: sky = OK/active, amber = warning, coral = recording.

**Starting**
- Library toolbar gains **Record** (`record.circle`, labelled, ⌘⇧R) next to New Note; while
  recording it becomes **Stop** (`stop.circle`, coral symbol). The menu bar items stay; add
  "Pause recording" / "Resume recording" under Stop.
- Consent sheet: when the speaker model isn't installed, add one toggle under the text:
  "Tell speakers apart" with secondary caption "Downloads 13.7 MB once." Default off. Turning
  it on starts the download (user-initiated) when recording starts; failure never blocks it.

**While recording** (detail pane of the pinned recording row)
- Centered column, 360 pt wide: elapsed time `.system(size: 44, weight: .semibold)`
  monospaced digits; below it "Recording" in coral 13 pt (or "Paused" secondary).
- Two source rows, 13 pt: `mic` "Microphone" and `speaker.wave.2` "Call audio", each trailing
  a 3-bar level glyph (sky bars, 3×10 pt, 2 pt gap, driven by RMS at ≤10 Hz) when audio
  flows; `exclamationmark.triangle.fill` amber + short reason when it doesn't
  ("Reconnecting…", "Not coming through"). Call audio silent is normal for in-person
  meetings: show "None — in-person" secondary instead of a warning until it has ever flowed.
- Buttons: [Pause] bordered, [Stop] `.borderedProminent` tinted coral. 12 pt gap.
- No live transcript (DESIGN: later).

**Processing** (replaces the single "Summarising…")
- Same centered column: four rows "Saving audio", "Transcribing", "Identifying speakers",
  "Summarising" (skip "Identifying speakers" when no model). Leading glyph per row:
  pending `circle` tertiary, active small `ProgressView`, done `checkmark.circle.fill` sky,
  failed `exclamationmark.triangle.fill` amber with the error as a secondary line.
- Recovered meetings show, above the title: "Recovered after Scribe quit unexpectedly."
  secondary 12 pt with `arrow.counterclockwise`.

**Detail v2**
- Toolbar: **Copy ▾** (labelled, `doc.on.doc`) menu: Summary · Transcript · Everything
  (Markdown). Then Export ▾, Delete as before.
- New **Notes** section between Summary and Transcript: header "Notes" like the others, a
  plain multi-line editor, placeholder "Your notes", autosaved (debounced 0.5 s), included in
  Copy Everything and exports. Empty notes take one line.
- Transcript turn text is editable in place: double-click (or Return on a focused turn)
  swaps the text for a plain multi-line field; Esc cancels, click-away/⌘Return saves.
  Edited turns show `pencil` 10 pt tertiary after the timestamp.
- Short meetings with no summary bullets show "Too short to summarise." secondary instead
  of an error.

## Mac — Settings › Dictionary (M8)
New tab between **Languages** and **Refine**: title "Dictionary", symbol
`character.book.closed`. Settings window width goes from 520 to **600 pt** so nine tabs fit
(height unchanged).

Pane (grouped `Form`, same pattern as Snippets):
- Section header "Dictionary", footer: "Scribe listens for these words and always spells them
  this way. Stays on this Mac."
- One row per entry, in the order added:
  - Line 1: `HStack` — `TextField("Word or name", text:)` (flex) · delete button
    (`minus.circle`, icon only, `.destructive`), exactly like a snippet row.
  - Line 2: `TextField("Heard as (optional, comma-separated)", text:)`, `.font(.callout)`.
    Shows the variants joined by ", ". On commit (Return or focus loss), split on commas,
    trim, drop empties and duplicates (case-insensitive), and drop a variant equal to the term.
- Last row: `Button("Add word", systemImage: "plus")` appends an empty entry.
- Empty state (no entries): one `Text` row, `.foregroundStyle(.secondary)`: "Add names, brands
  and terms Scribe gets wrong."
- Entries with an empty term are kept while editing but ignored by dictation, and removed
  when the Settings window closes.
- No icons, badges or colours per row. `source == .learned` looks identical to `.user` in M8.

## Mac — Library window and Refine editor (M16)
Same concepts as iOS v2.6 (DESIGN-IOS-V2.md): the shared `Note` model, Library, Editor, presets.
- **Window "Scribe"** (`Window`, default 900×600, min 720×460), opened from the menu bar:
  **Open Scribe…** (⌘O while the menu is open) above **Recent**; clicking a Recent item still
  copies it. Shown in the Dock while open (activation policy regular), back to accessory on close.
- `NavigationSplitView`: sidebar **Library** (search field on top; sections Today / Yesterday /
  Earlier; row = first line 13 pt + time 11 pt secondary) and, below a divider, **Meetings**
  (the M7 list moves here; the separate Meetings window goes away). Toolbar: **New Note** (⌘N),
  **Paste as New Note** (⇧⌘V).
- Detail = Editor: `TextEditor` 15 pt, 24 pt padding, max line width 680 pt centred. Bottom bar:
  the preset chips (same set/order as iOS, `ScribeUI` chip style), applying to the selection or
  the whole text, one undo step each (⌘Z). Busy + failure behaviour as iOS. Toolbar trailing:
  **Copy** (⇧⌘C), menu with Save as Copy (⌥⌘S), Revert to Original, Delete. Edits autosave.
- Menu bar menu keeps Recent (last 10, click = copy).

## Mac — Library polish (M16.1, owner feedback 2026-10-17)
- **Rows:** `.swipeActions` like iOS: trailing **Delete** (destructive); leading **Pin/Unpin**
  (`pin` / `pin.slash`, amber tint). The same actions plus **Copy** in a right-click context menu.
  Pinned notes sit in a **Pinned** sub-header section above Today, and are always kept.
- **Toolbar** (the two doc icons were confusing):
  - Leading: **New Note** = `square.and.pencil` with a menu arrow (`Menu` + `primaryAction`);
    its menu has "New Note ⌘N" and "Paste as New Note ⇧⌘V".
  - Trailing: the **Copy** button with a text label ("Copy", `.labelStyle(.titleAndIcon)`,
    `doc.on.doc`), then the ellipsis menu. Search stays in the toolbar.
- **Window title** = the selected note's title (first line, up to 40 characters); "Scribe" with
  nothing selected. **Sidebar header:** a static `TrioMark` 18 pt + "Scribe" 13 pt semibold above
  the Library section, 12 pt padding.
- **Refine highlight (Mac and iOS editors):** after a preset finishes, the replaced range gets a
  background of `Brand.amber` at 28% opacity. It fades out over 0.6 s, starting 1.2 s after the
  result lands; it is removed at once on the next edit or selection change, and never saved.
  Reduce Motion: no fade, removed after 1.8 s.
- **Refine icon everywhere** (owner choice 2026-10-17): SF Symbol `pencil.and.scribble`.
  `RefineGlyph` now renders it; the Mac Settings tab uses it directly (fixed by the lead).
- **Live-word reveal performance:** the owner sees stutter in the Mac HUD (MacBook Air). Profile it
  (signposts on frame time while text streams). Rules: animate only words that arrived in the
  last 0.3 s (older runs render plain). Blur only on Apple silicon with ≥ 60 fps measured,
  otherwise opacity + rise only. Never re-layout the whole paragraph per frame. Target: no frame
  over 16 ms during streaming at 10 Hz updates. The same component serves iOS: verify there too.

## Style by app (M10, lead spec 2026-10-18; owner: add Code, Mail = Natural)
- **Tones:** Natural · Casual · Formal · **Code**. Code is for editors and terminals: identifiers,
  paths, commands and symbols stay verbatim; no smart quotes; no full stop after a lone command.
- **Resolution** (`AppStyleResolver`, ScribeCore, pure + tested): spoken note ("more formal") >
  user's per-app choice > bundled rule > **Default tone**. Mac keys on the frontmost bundle ID at
  the moment dictation starts. Library editor presets are unaffected.
- **Bundled rules** (bundle IDs; only apps installed on this Mac are listed):
  - Code: Xcode, Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor, Zed, Nova, Sublime Text,
    JetBrains IDEs (`com.jetbrains.*`).
  - Casual: Messages, WhatsApp, Telegram, Signal, Discord, Slack.
  - Formal: none bundled (Outlook, Mail, Teams stay on the default; the owner wants Mail Natural).
- **Settings › Refine (Mac):** the existing "Tone" picker becomes **Default tone** (4 options).
  New `Section("Style by app")` under it:
  - One row per app: 16 pt app icon + name (13 pt), trailing menu `Picker` with
    "Default (Natural)" · Natural · Casual · Formal · Code. "Default (…)" shows the live default.
  - Rows: installed bundled apps first, then apps the user added, both sorted by name.
  - Below the list: `+` / `−` buttons (`.buttonStyle(.borderless)`, like System Settings).
    `+` opens an `NSOpenPanel` on /Applications (`.application` content type). `−` removes a
    user-added row, or resets a bundled row to its bundled tone.
  - Footer: "Scribe picks a tone for the app you're dictating into. Saying “more formal” still
    wins."
- **HUD:** no new UI. The HUD's existing app line is unchanged; no tone badge (keep it quiet).

## Mac — Direct download and Talk shortcut (M19, lead spec 2026-10-18)
Owner decision: after the sandbox spike (Tools/M19-SANDBOX.md: cross-app Accessibility is not
allowed in the App Sandbox), the Mac app ships as a **notarized DMG** from the website, Developer
ID signed, not sandboxed. The iPhone app ships on the App Store.

**Engineering rules**
- Talk shortcut: keep the session event tap (Accessibility), extended from a fixed modifier to a
  user-chosen shortcut: a lone modifier (Right ⌥, Right ⌘, Right ⌃, fn), any combo with ⌃/⌥/⌘,
  or F1–F20 alone (pedals and stream decks send F13–F20). The tap swallows the chosen combo; a
  lone fn is observed, never swallowed (as today). Chords pressed after talking started keep
  their meaning (⇧ hands-free, ⌘ Refine / edit selection); Return/Esc during hands-free as today.
- `make dmg`: builds Release, signs (Developer ID, hardened runtime), creates a DMG with the app
  and an Applications alias on a navy (#16212E) background with the TrioMark, signs the DMG,
  notarizes with `notarytool` using a keychain profile the owner creates (`NOTARY_PROFILE`), and
  staples. Never stores credentials in the repo.
- Updates: Sparkle 2 (EdDSA-signed appcast hosted with the website). Network rule: **no automatic
  checks by default**. The app menu gets "Check for Updates…" (user-initiated). Settings › General
  gets the toggle "Check for updates automatically" (off by default), footer "Asks
  scribe.nanthai.tech once a day. Sends nothing else."
- Privacy manifests (`PrivacyInfo.xcprivacy`) for the iOS app and the keyboard (App Store
  requirement), and for the Mac app for parity.

**Settings › General**
- "Dictation key" picker → **Talk shortcut** row:
  - The current shortcut drawn as key caps (`ScribeUI` key-cap style, 13 pt).
  - A **Change…** button.
  - A menu ▾ with presets: Right ⌥ (default) · Right ⌘ · fn · ⌃⌥Space · F13.
- Change… opens a popover:
  - "Press a key or combination" with Esc to cancel. Live key caps as keys go down.
  - Accepted: a lone modifier from the list above; any combo with ⌃, ⌥ or ⌘; F1–F20 alone.
  - Rejected: a plain letter or digit, with the inline text "Add ⌃, ⌥ or ⌘".
  - Conflicts: if the combo is a common system shortcut (⌘Space, ⌘Tab, ⌃Space…), show "That
    shortcut is used by macOS."
- Footer: "Foot pedals and stream-deck buttons work too: set them to send F13–F20, then press
  the button here."
- The shortcuts reference list keeps its rows, with "Hold key" replaced by the live shortcut name.

**Onboarding**
- Unchanged (Accessibility step), except step 4 shows the live talk shortcut.

## Auto-learning (M9, lead spec 2026-10-18; Mac and iOS)
Scribe notices when you fix a word it got wrong and offers to remember it. The speech engine stays
SpeechTranscriber with Dictionary replacement (M9.0 result); the M9.1 A/B on real voice is later.

**Detection** (`CorrectionDetector`, ScribeCore, pure + tested)
- Input: the text Scribe inserted and what that span looks like now. Output: zero or one
  candidate pair (heard → meant).
- Align with `NoteDiff` words. A candidate is one replaced run of 1–3 words where:
  - the new run is 1–3 words;
  - it is a spelling fix, not a rewrite: case-insensitive similarity ≥ 0.5 (normalised edit
    distance on letters, or a matching metaphone-style key for Latin scripts), OR the new run is
    capitalised (a name) and the old one isn't;
  - more than one run changed? Take none (the user rewrote, not corrected).
- Ignore: punctuation- or whitespace-only changes, deletions, insertions, numbers, and pairs
  already in the Dictionary.

**When to ask** (owner 2026-10-18: don't nag). Every candidate is recorded in a local
`CorrectionLog` (pair, times seen, last seen, state). It is never logged and never leaves the
device.
- Seen the 1st time: ask.
- After "Not now": don't ask again until the same pair has been seen 3 more times. A second
  "Not now" sets the state to **Ignored**: never asked again, but still listed (see Review).
- At most one prompt per 10 minutes across all pairs. Otherwise the pair is recorded silently.
- Pairs found while the user can't be asked (the keyboard is gone, the HUD is hidden) are
  recorded as **Suggested** and wait in Review.

**Mac**
- After inserting, if Accessibility gives the focused element's value, watch that element for
  60 s (`AXObserver` value-changed, else 1 s polling) and find the inserted span by its
  unchanged prefix and suffix. Lose the span → stop watching.
- When a candidate is stable for 2 s, the HUD shows a compact prompt for 8 s. It doesn't take
  focus; the buttons are clickable in the non-activating panel:
  `Always spell “Nantai” as “NanthAi”?`  [Add] [Not now]
  - Text 13 pt, `textOnNavy`; [Add] coral-tinted borderless and [Not now] secondary.
  - One prompt per dictation.
- [Add] creates (or extends) a Dictionary entry: term = meant, heard-as += heard,
  `source: .learned`. A brief "Added to Dictionary" confirmation, then the HUD hides.

**iPhone**
- **Library editor:** when the user edits a dictation note and a candidate appears, a chip
  appears at the leading edge of the preset bar: `Add “NanthAi” to Dictionary` (`plus` glyph,
  amber fill like the Pin action, navy text). Tap → add. It disappears on the next edit or
  after 10 s.
- **Keyboard:** for 60 s after a Talk insert, the keyboard compares the inserted span with its
  local text mirror. On a candidate, the suggestion strip's centre slot shows
  `Always “NanthAi”?` (semibold) and tap adds it. The add goes through the app group; the app
  merges it on its next launch or foreground. Any other key restores the normal strip.

**Contacts** (opt-in, default off)
- Settings › Dictionary gains the toggle **Use names from Contacts**, footer "Helps Scribe spell
  the people you know. Names never leave this device."
- Reads given, family and nickname fields only (`CNContactStore`, requested when the toggle
  turns on).
- Names are never shown in the Dictionary list and never added to the prompt wholesale. A pure
  `NameMatcher` picks at most 10 names that are phonetically close to words in the current
  transcript. Those go to Refine's term list and Dictionary replacement for that dictation only.

**Keyboard words** (typing autocorrect, iPhone)
- Today, a word the user keeps after undoing an autocorrect is only remembered for the session.
  Now it is saved to the app group: after two keeps, the keyboard stops correcting that word
  for good. It is also passed to `UITextChecker.learnWord`, so suggestions accept it.

**Review: Settings › Dictionary** (Mac pane and iOS screen, same structure)
- **Dictionary** (as today): every entry, typed or learned. Learned ones carry a small
  secondary caption "Learned". Swipe or `minus.circle` removes an entry. "Add word" adds one
  manually, with heard-as variants.
- New section **Corrections**: "Scribe noticed you fixing these." Rows show
  `heard → meant` with the caption "Seen 3× · Suggested" (or Ignored), and two actions:
  - **Add** (to the Dictionary)
  - **Ignore**, or **Forget** for Ignored rows, which removes the row and resets its count
  Newest first. Empty: "Nothing yet. When you fix a word Scribe got wrong, it shows up here."
- New section **Keyboard words** (iPhone only; the Mac has no keyboard). Rows show each word
  the keyboard won't correct, with swipe to remove and an "Add word" row for manual entries.
  Footer: "Words the keyboard keeps as you type them."
- Footer under Dictionary: "Scribe offers to add words you correct, and lists them under
  Corrections."
