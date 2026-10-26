---
title: How to clean up dictated text on a Mac
description: Use Refine to fix grammar and remove false starts from dictation. Choose a tone, edit selected text or insert fixed wording with snippets.
keyword: clean up dictation text
updated: 2026-10-24
topic: Dictation on Mac
related: [refine, style-by-app, snippets, models]
---

Plain dictation on the Mac removes fillers such as “um” and “uh” and tidies spacing and capitals. Turn on Refine to fix grammar and remove false starts in the chosen tone.

## What does Refine change?

Refine keeps the structure and language of the dictation while removing repetition. Proofread, available in the editor, makes narrower changes to spelling, grammar and punctuation.

Refine transforms spoken text without replying to its content. A request such as “can you send me the report by Friday” stays a request in the inserted text.

If the rewrite fails or takes more than 20 seconds, Scribe inserts the cleaned transcript instead and shows a short error.

## How do I turn Refine on?

On the Mac, hold the talk shortcut and press ⌘ at any point during the hold. A **Refine** chip appears in the floating bar, and when you let go the bar shows **Refining…** while the text is rewritten.

In Scribe for iPhone (coming soon), the keyboard has a **Refine** pill. It stays on until turned off. Keyboard Refine always uses Apple Intelligence; Gemma is available only in the foreground app.

## Which engine does the rewriting?

Refine uses Apple Intelligence on the device by default. The optional Gemma engine also runs locally; audio and text stay on the device.

**Gemma 4 E2B** is available under **Settings › Refine › Engine** for Macs without Apple Intelligence. Start the **4.36 GB** download with the button under the picker. [Optional models](/docs/models) covers storage and removal.

If Refine reports **Turn on Apple Intelligence in System Settings to use Refine**, Apple Intelligence is off or still downloading its model.

## Which tone fits the text?

- **Natural** is the default tone for tidying ordinary dictation.
- **Casual** reads like a message to someone you know, and contractions are fine.
- **Formal** reads like a message to a client, with complete sentences and no slang.
- **Code** turns spoken code into written code. "dash dash verbose" becomes `--verbose`, "user underscore id" becomes `user_id`, and "camel case user ID" becomes `userId`.

If you ask for a different tone while you speak, such as "more formal", your instruction wins.

Set the default under Settings › Refine › **Default tone** on the Mac. On iPhone, use the **Tone** chip next to the Refine pill.

## How do I set a tone for each app?

On the Mac, [Style by app](/docs/style-by-app) gives each app its own tone. Messaging apps such as Messages, WhatsApp, Slack and Discord start on Casual. Code editors and terminals such as Xcode, Terminal, VS Code and Cursor start on Code. Everything else uses your default tone.

Change any app's tone under Settings › Refine › **Style by app**, and click **+** to add an installed app that is not listed. When more than one rule could apply, the order is: an instruction you speak, then the rule you set for the app, then the built-in rule, then your default.

iOS does not tell a keyboard which app is in front, so iPhone uses one tone at a time, chosen with the Tone chip.

## Can I clean up text after I have written it?

On the Mac, select the text, hold the shortcut, press ⌘, and say what to change, such as "shorter", "make it a list" or "translate to French". The result replaces the selection. If you say nothing and let go, Scribe runs the default Refine on the selection.

The Library editor on both devices has presets: **Proofread**, **Shorter**, **Clearer**, **Friendlier**, **Professional**, **Bullets** and **Translate**. Undo restores the previous text. The [Refine](/docs/refine) page lists what each preset does.

## How do I stop retyping the same text?

Use a [snippet](/docs/snippets). A snippet is a short phrase paired with fixed text, such as your address or an email sign-off. Say the phrase on its own and the text is inserted exactly as you wrote it, with Refine skipped. Say it inside a sentence and the phrase is replaced in the final result while the rest of the sentence is refined.

Pick phrases you would not say by accident. Two or three words work well. Snippets are set up under Settings › Snippets on the Mac or iPhone, and the two devices keep separate lists.

## What if the result is wrong?

Refine can change the words around a snippet while keeping the snippet itself fixed. If the inserted fixed text is wrong, check its saved text in Settings. If Refine took too long, Scribe inserted the cleaned transcript, so try a shorter take. If Refine reports **Couldn't refine. Try again.** in the editor, the text is unchanged, so try again or pick a different preset.

## Try it

[Download Scribe for Mac](/download), then hold the talk shortcut, press ⌘ and dictate a short note. The [Refine](/docs/refine) page covers tones, engines and presets in detail.
