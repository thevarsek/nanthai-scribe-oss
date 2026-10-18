---
title: Troubleshooting
description: Quick fixes when the key does nothing, the keyboard will not start, Refine fails, or a language is missing.
group: troubleshooting
order: 1
platform: both
---

## Mac

**Holding the key does nothing.** Scribe needs **Accessibility** to see the shortcut and paste the result. Open System Settings › Privacy & Security › Accessibility and make sure NanthAi Scribe is on. The key arms itself as soon as the permission is granted; no relaunch needed. If you changed the shortcut, check Settings › General to see which one is selected.

**The text goes to the wrong place, or nowhere.** Scribe types into the field that had focus when you pressed the key. Click into the field first. Password fields block synthetic paste by design.

**My clipboard changed.** Scribe inserts text through the clipboard and restores what was there straight afterwards. If an app is slow to accept the paste, you may briefly see the dictated text there.

**Refine shows an error.** The rewrite timed out or no engine was available; your cleaned transcript was inserted instead. Apple Intelligence must be on in System Settings. On a Mac without it, download Gemma 4 under Settings › Refine. See [Refine › Common problems](/docs/refine#common-problems).

**No other side in a meeting recording.** macOS asks for *System Audio Recording Only* the first time; check Privacy & Security › Screen & System Audio Recording. In-person meetings have no call audio by design.

**The app says an update is available but nothing happens.** See [Updates on Mac](/docs/updates).

## iPhone

**The keyboard is not in the list.** Settings › General › Keyboard › Keyboards › Add New Keyboard… › NanthAi Scribe. Then tap it and turn on **Allow Full Access**.

**Talk says "Tap to start Scribe", or opens the app every time.** Without Full Access the keyboard cannot reach the app; turn it on. Opening the app once per session is normal: the first Talk after the mic has gone idle starts Scribe for a moment, then you are back and it is listening. Raise **Keep mic ready for** in Settings › Keyboard if five minutes is too short.

**Dictation stops when a call or Siri comes in.** iOS takes the microphone. Scribe finishes the take with what it has and delivers it; tap Talk again afterwards.

**A shortcut dictation did not type anything.** If the Scribe keyboard was not up in a text field when you stopped, the text was saved to the Library and is offered as *Insert last* the next time the keyboard appears. Tap **Done · Tap to copy** in the Live Activity to copy it.

**Refine from the keyboard says it could not refine.** The selection is left untouched. Make sure Apple Intelligence is on; the keyboard uses it directly. Try again, or open the note in the app.

**Letters are missing when I type fast.** Tell us the iPhone model at support@nanthai.tech; this should not happen.

**A meeting stopped on its own.** Recordings stop at four hours, when the battery reaches 5%, or when free space drops under 100 MB. What was recorded is kept and processed.

## Both

**A language shows "Download language pack".** Apple's on-device speech does not cover it. Download the 483 MB pack under Settings › Languages; see [Languages](/docs/languages).

**A name is always misspelled.** Add it to the [Dictionary](/docs/dictionary) with the spellings Scribe produces under *Heard as*.

**I deleted something by mistake.** Scroll to [Recently Deleted](/docs/recently-deleted) at the bottom of the Library and tap Restore. Items stay there for 30 days.

**Does any audio or text leave my device?** No. See [Privacy and permissions](/docs/privacy-and-permissions).

**Can I use Scribe offline?** Yes, once the languages and any optional models you use are downloaded.

**Do notes sync between my iPhone and Mac?** Not today. Each device keeps its own Library; [Backup](/docs/backup) moves notes across.

Still stuck? Write to [support@nanthai.tech](mailto:support@nanthai.tech) or see [Support](/support).
