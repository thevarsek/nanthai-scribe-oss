---
title: How to dictate anywhere on a Mac
description: Turn on macOS Dictation or use Scribe to hold a key, speak and insert text. Includes setup, hands-free mode and editing by voice.
keyword: dictate on mac
updated: 2026-10-24
topic: Dictation on Mac
related: [dictate-mac, talk-shortcut, getting-started-mac, refine]
---

macOS includes Dictation for entering text by voice. Scribe is a separate Mac app that inserts a dictation when a held shortcut is released, with optional rewriting through Refine.

## How do I turn on macOS Dictation?

As of October 2026, [Apple's Dictation help page](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac) gives these steps:

1. Open **System Settings › Keyboard**, then turn on **Dictation**.
2. Click **Enable** if prompted.
3. Click into a text field. Press the Microphone key, use the Dictation shortcut, or choose **Edit › Start Dictation**.
4. Speak, then press Escape, the Microphone key or the shortcut to finish.

Apple's Microphone key starts Dictation with a press and release; holding it activates Siri when Siri is enabled. Dictation also stops after 30 seconds without speech. Availability varies by language and region. Apple's current help page covers macOS 27; wording may differ on macOS 26.

## How do I set up Scribe?

Scribe for Mac needs Apple silicon and macOS 26. Download the DMG, drag **NanthAi Scribe** into **Applications**, then open it. Scribe lives in the menu bar; opening the Library also gives it a Dock icon.

The setup window asks for Accessibility and microphone access. Accessibility lets Scribe notice the talk shortcut and insert text into other apps. Microphone access lets it hear speech. The setup ends with a field for a first dictation. [Get started on Mac](/docs/getting-started-mac) covers the installation screens.

## How does push-to-talk work?

Click where the text should go, hold the talk shortcut and speak. The default is the right Option key. A floating bar shows **Listening…**, then the recognised words. Release the key to finish. The bar shows **Finishing…** while the final words settle, then Scribe pastes the result at the cursor.

Plain dictation removes fillers such as “um” and “uh”, tidies spaces and capitalises the first letter. It also adds a leading space when the cursor is immediately after a word. There is no dictation length limit.

Scribe restores the previous clipboard after pasting. If another app writes to the clipboard in the meantime, Scribe leaves that newer content alone.

## Can I choose another shortcut?

Open **Settings › General › Talk shortcut › Change…**, then press the desired key or combination. Single modifiers, function keys and combinations with Control, Option or Command are supported. A foot pedal can send F13–F20 for the same hold-and-release behaviour.

If a combination triggers an action in another app, choose a different one. The [talk shortcut page](/docs/talk-shortcut) lists the presets and explains conflicts with macOS shortcuts.

## Can I dictate without holding a key?

Tap **Shift** while holding the shortcut, then release it. Scribe keeps listening in hands-free mode. Press **Return**, or the shortcut again, to insert the text; **Esc** cancels the take. The floating bar shows these controls while listening.

## Can I tidy or edit the text by voice?

Press **⌘** during a hold to turn on Refine. It fixes grammar and removes repetition in the chosen tone. Refine uses Apple Intelligence by default, or the optional Gemma 4 download. If rewriting fails or takes longer than 20 seconds, Scribe inserts the cleaned transcript instead.

To change existing text, select it first, hold the shortcut, press **⌘** and say an instruction such as “shorter”. Releasing applies the edit. If the edit fails, the selection stays unchanged. See [Refine](/docs/refine) for engines and tones.

## What if text lands in the wrong place?

Scribe targets the field focused when the shortcut was pressed. Click into the intended field and choose **Paste Last Dictation** from the menu bar to insert it again. Secure password fields block synthetic paste, so they remain empty.

## Try it

[Download Scribe for Mac](/download) and dictate into a blank note. [Dictate on Mac](/docs/dictate-mac) covers the floating bar and recovery controls.
