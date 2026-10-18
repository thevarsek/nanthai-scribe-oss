---
title: Dictate on Mac
description: Hold-to-talk, hands-free, the floating bar, editing a selection by voice, and what happens to your clipboard.
group: dictate
order: 1
platform: mac
---

## Hold, talk, let go

1. Click where you want the text.
2. Hold your [talk shortcut](/docs/talk-shortcut).
3. Speak. A floating bar at the bottom of the screen shows **Listening…**, then your words as they arrive.
4. Let go. The bar shows **Finishing…** for a moment while the last words settle, then the text is typed at your cursor.

Scribe removes fillers ("um", "uh", "erm", "hmm"), tidies spaces, capitalises the first letter and adds a space before the text when the cursor is right after a word. There is no limit on how long a dictation can be.

## Hands-free

Tap <kbd>Shift</kbd> while holding the shortcut, then let go. Scribe keeps listening; the bar shows **Return to finish · Esc to cancel**. Press <kbd>Return</kbd> (or the shortcut again) to insert, <kbd>Esc</kbd> to throw the take away. Both keys are swallowed so they don't reach the app.

## Refine as you go

Press <kbd>⌘</kbd> at any point during the hold. A **Refine** chip appears in the bar and, when you let go, the bar shows **Refining…** while Apple Intelligence (or Gemma 4) rewrites your words into clean text in your chosen tone. See [Refine](/docs/refine) and [Style by app](/docs/style-by-app).

If the rewrite fails or takes longer than 20 seconds, the cleaned transcript is inserted instead and the bar shows a short error. You never lose a dictation.

## Edit a selection by voice

1. Select some text in any app.
2. Hold the shortcut and press <kbd>⌘</kbd>. The bar shows **Say what to change**.
3. Say an instruction: "shorter", "make it a list", "more formal", "translate to French", "fix the typos".
4. Let go. The bar shows **Editing…**, then the result replaces the selection.

If the edit cannot be made, your selection is left unchanged and the bar says **Couldn't edit. Your text is unchanged.**

> Tip: Hold the shortcut with <kbd>⌘</kbd> and say nothing to run the default Refine on the selection.

## The floating bar

The bar never takes focus, so your cursor stays where it was. It shows the live words, a chip for the active mode (Hands-free, Refine, Edit selection, or the output language), progress states, and errors for a few seconds. While a meeting is being recorded the bar stays hidden, but dictation keeps working.

## Your clipboard

Scribe inserts text by putting it on the clipboard and pasting, then restores whatever was on your clipboard before. If something else writes to the clipboard in the meantime, Scribe leaves it alone.

## Paste the last dictation again

Choose **Paste Last Dictation** from the menu bar menu to insert your most recent dictation again, for instance after you clicked into the wrong field. The last ten dictations are also listed under **Recent**; click one to copy it.

## Common problems

**Nothing happens when I hold the key.** Check Accessibility in System Settings › Privacy & Security, then check which shortcut is set in Settings › General.

**The text appears in the wrong app.** Scribe types into whatever had focus when you pressed the key. Click into the field first.

**Password fields stay empty.** Secure fields block synthetic paste by design.

**The bar shows "The microphone couldn't be started."** Another app may be holding the microphone exclusively, or access was denied: System Settings › Privacy & Security › Microphone.
