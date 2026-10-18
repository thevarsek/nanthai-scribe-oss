---
title: Privacy and permissions
description: What each permission is for, what Scribe keeps on your device, what it never sends, and how to clear or take your data with you.
group: privacy
order: 1
platform: both
---

## The short version

Audio is processed on your device and never stored, except for meeting recordings you choose to keep. Nothing is uploaded. There are no accounts, no analytics and no telemetry. The only network requests are model downloads you start and, on the Mac, update checks you start or turn on. The full [privacy policy](/privacy) says the same in longer words.

## Permissions on Mac

| Permission | Why | Where |
|---|---|---|
| **Accessibility** | Notices your talk shortcut in any app and types the result into it. | System Settings › Privacy & Security › Accessibility |
| **Microphone** | Hears you. | Asked on your first dictation. |
| **System Audio Recording** | Captures the other side of a call for a meeting. Asked the first time you record. | Privacy & Security › Screen & System Audio Recording |
| **Contacts** | Only if you turn on *Use names from Contacts*. Read on the Mac, never copied. | Settings › Dictionary |

**Use screen context** (Settings › Refine) reads the window you dictate into so Refine can spell names and understand replies. The reading is bounded, stays on the Mac and is never stored. It is a setting, not a system permission.

## Permissions on iPhone

| Permission | Why |
|---|---|
| **Microphone** | Hears you, in the app and from the keyboard. |
| **Full Access** for the keyboard | Lets the keyboard and the app exchange text and settings through a shared container on the phone. The keyboard makes no network requests. |
| **Contacts** | Only if you turn on *Use names from Contacts*. |
| **Notifications** | Optional, for the Live Activity that shows a dictation or meeting in progress. |

## What is kept

- **Notes**: your dictations, in the Library, for as long as **Keep history** says (Off, 1 day, 30 days, Forever; default Forever). Edited, pinned and typed notes are kept until you delete them.
- **Meetings**: transcript and summary. Audio only if **Keep recordings' audio** is on, or the meeting came from [Transcribe a recording](/docs/transcribe-a-recording).
- **Dictionary, Snippets, Corrections and keyboard words**: your lists and what Scribe has learned.
- **Learned key positions** on the iPhone keyboard.
- **Models** you downloaded.

Deleted notes and meetings wait 30 days in [Recently Deleted](/docs/recently-deleted) before they are gone. Everything above lives in Application Support on the Mac or the app's container (shared with its keyboard) on iPhone. Device backups follow your iCloud or computer backup settings.

## Clear it

- **Clear history** (Mac: Settings › History & Privacy; iPhone: Settings › History) removes untouched dictations; **Delete all notes…** removes every note. Meetings are managed in the Library.
- **Reset typing learning** (Settings › Keyboard) clears learned key positions and keyboard words.
- Delete a model from where you downloaded it.
- Uninstall the app to remove everything else.

## Take it with you

**Export Library…** writes a `.scribebackup` file with notes, meetings, Dictionary, Snippets and Corrections; **Import Backup…** merges it on another device. See [Backup](/docs/backup).

## What never happens

No audio or text leaves the device. Scribe does not ask who you are, does not open an account, does not measure what you do, and the Mac app does not check for updates unless you ask it to. If this changes, we'll update the [privacy page](/privacy) and its date.
