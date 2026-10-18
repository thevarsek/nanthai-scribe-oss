---
title: Dictate on iPhone
description: The Talk button, the handoff to the app, keeping the mic ready, and dictating from the Action Button, Control Center or Back Tap.
group: dictate
order: 3
platform: iphone
---

## Talk from the keyboard

1. Switch to the Scribe keyboard with the globe key and tap **Talk**.
2. If the mic is not ready yet, Scribe opens for a moment, shows **Listening**, and an amber hint points at the back control. Swipe back to your app.
3. Speak. Your words appear in the keyboard's live area as you say them. A timer shows the length of the take.
4. Tap **Done**. The text is inserted at the cursor. Tap **Cancel** instead to discard the take.

With the **Refine** pill on, the Talk button reads **Refining…** for a moment and the inserted text is clean writing in the tone shown on the **Tone** chip. See [Refine](/docs/refine).

## Why Scribe opens

iOS keyboards cannot use the microphone, so the app has to hold it. The first Talk after the mic has gone idle opens the app to start listening; after that the mic stays ready and Talk is instant.

**Keep mic ready for** (Settings › Keyboard) sets how long: Off, 1, 5 or 15 minutes, five by default. While the mic is ready, iOS shows its mic indicator and a Live Activity on the Lock Screen shows the remaining time and an **End** button. Sound is only turned into text after you tap Talk.

> Tip: Turn on **Lower other audio while I talk** in Settings › Keyboard if music keeps playing over your dictation.

## Edit a selection by voice

Select some text, and the Talk button becomes **Say how**. Tap it, say what to change ("shorter", "make it a list", "translate to Spanish"), and the result replaces the selection. The hint reads *Say what to change*. If the selection is lost while Scribe opens, the keyboard says **Select the text again to change it.**

For a one-tap change, tap **Refine** with text selected and choose a preset: Refine, Proofread, Shorter, Clearer, Friendlier, Professional, Bullets or Translate. **Undo** restores the previous text.

## Insert last and Retry

After a dictation, an **Insert last** chip re-inserts the most recent text for up to an hour, even if history is off. It is useful when you dictated into the wrong field or the app discarded the text. If delivery failed, the chip reads **Retry**.

## Dictate without the keyboard

**Dictate with Scribe** is a Shortcuts action that starts a take from anywhere:

- **Action Button**: Settings › Action Button › Shortcut › Dictate with Scribe.
- **Back Tap**: Settings › Accessibility › Touch › Back Tap › Double Tap › Dictate with Scribe.
- **Control Center**: Add a Control › Scribe › Dictate.
- **Siri**: "Dictate with Scribe".

A Live Activity shows **Listening** with a **Stop** button. Run the action again, or tap Stop, to finish:

- If the Scribe keyboard is up in a text field, the text goes there.
- Otherwise the Live Activity shows **Done · Tap to copy**. Tap it: Scribe comes forward, copies the text and says **Copied. Paste anywhere.**

Every take is also saved in the [Library](/docs/library).

## In the app

The **Dictate** tab has the same Talk button, Refine pill and Tone chip, for quick notes that go straight to the Library. Inside a note, the mic chip dictates at the cursor.

## Common problems

**Talk says "Allow Full Access so the keyboard can talk to Scribe."** Turn on Full Access: Settings › General › Keyboard › Keyboards › NanthAi Scribe.

**Talk says "Open Scribe to start a session, then return here."** The app could not be reached in the background. Open Scribe once, then try again.

**A phone call or Siri stopped the dictation.** iOS takes the microphone. Scribe finishes with what it heard; tap Talk again.

**The dictated text went to the Library but not the app.** The keyboard was not up when the take ended. Use **Insert last** the next time the keyboard appears, or copy from the Library.
