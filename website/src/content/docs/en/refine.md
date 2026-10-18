---
title: Refine and tones
description: Turn spoken thoughts into clean text in four tones, translate as you go, and edit selected text with presets or your own instruction.
group: refine
order: 1
platform: both
---

## What Refine does

Plain dictation gives you what you said, minus fillers. Refine gives you what you meant: it fixes grammar, removes repetition and false starts, keeps your structure and your language, and writes it the way you would have typed it.

Two rules never change:

- **Refine transforms, it doesn't reply.** Dictate "can you send me the report by Friday" and you get that sentence, cleaned up, not an answer about reports.
- **Nothing is lost.** If the rewrite fails or takes more than 20 seconds, Scribe inserts the cleaned transcript instead and shows a short error.

## Turn it on

| Where | How |
|---|---|
| Mac | Hold the talk shortcut and press <kbd>⌘</kbd> at any point. A **Refine** chip appears in the floating bar. |
| iPhone keyboard | Tap the **Refine** pill so it turns amber. It stays on until you turn it off. |
| iPhone app | The same pill, inside the Dictate card. |

## Tones

| Tone | What you get |
|---|---|
| **Natural** | Your own voice, tidied. The default. |
| **Casual** | Like a message to someone you know. Contractions are fine. |
| **Formal** | Like a message to a client. Complete sentences, no slang. |
| **Code** | Spoken code becomes written code: "dash dash verbose" becomes `--verbose`, "user underscore id" becomes `user_id`, "camel case user ID" becomes `userId`. Straight quotes, and no full stop after a lone command or path. |

If you ask for a different tone while speaking ("more formal"), that wins.

- **Mac**: Settings › Refine › **Default tone**, plus a tone per app in [Style by app](/docs/style-by-app).
- **iPhone**: the **Tone** chip next to the Refine pill, or Settings › Refine › **Tone**. Both places share one setting.

## Output language

By default Refine writes in the language you spoke. Set an **Output language** (Mac: menu bar or Settings › Refine; iPhone: Settings › Refine) and Refine translates into it as it cleans up. Spoken instructions like "translate this to Italian" work regardless.

## Edit selected text

Select text first, then:

- **Mac**: hold the shortcut, press <kbd>⌘</kbd>, and say what to change: "shorter", "make it a list", "more formal", "translate to French". The result replaces the selection. Say nothing and let go to run the default Refine.
- **iPhone keyboard**: tap **Refine** to open the preset row, or tap **Say how** to speak your own instruction.

The presets, on the iPhone keyboard and in the Library editor on both devices:

| Preset | What it does |
|---|---|
| **Refine** | The default clean-up in your tone. |
| **Proofread** | Fixes only spelling, grammar and punctuation. |
| **Shorter** | Noticeably shorter, keeping the key points, names and numbers. |
| **Clearer** | Simpler wording, logical order, short sentences. |
| **Friendlier** | Warmer and friendlier. |
| **Professional** | Professional and polished. |
| **Bullets** | A concise bulleted list, one point per line. |
| **Translate** | Into your output language if set; otherwise into English, or, if the text is already English, into the first other language you have chosen. |

The row stays open after a result, with the new text selected, so you can chain changes. **Undo** restores the previous text. Tap **×** to close the row.

## Screen context (Mac)

With **Use screen context** on, Scribe reads the window you are dictating into: nearby text, names and terms. Names help Refine spell them correctly; a short summary helps it understand what you are replying to. The reading is bounded, happens on the Mac, is never stored and never leaves the machine. Turn it off in Settings › Refine.

## Engines

Refine uses **Apple Intelligence** on the device by default: fast and faithful. Macs and iPhones without Apple Intelligence can download **Gemma 4** instead under Settings › Refine › Engine; see [Optional models](/docs/models). From the iPhone keyboard, Refine always uses Apple Intelligence, because apps can't use the graphics chip in the background.

## Long text

Above roughly 2,500 characters, Refine works in chunks split at sentence and paragraph boundaries and joins the results. If one chunk fails, the cleaned transcript is used for that part.

## Common problems

**"Turn on Apple Intelligence in System Settings to use Refine."** Apple Intelligence is off, or still downloading its model. Turn it on in System Settings (Mac) or Settings (iPhone) › Apple Intelligence & Siri, and wait for the download to finish.

**"This device doesn't support Apple Intelligence."** Download Gemma 4 under Settings › Refine › Engine. On iPhone the keyboard cannot use Gemma; refine in the app's editor instead.

**"The rewrite took too long."** The cleaned transcript was inserted. Try again with a shorter take, or check that no other heavy app is using the machine.

**"Couldn't refine. Try again."** (editor) The text is unchanged. Try again, or pick a different preset.
