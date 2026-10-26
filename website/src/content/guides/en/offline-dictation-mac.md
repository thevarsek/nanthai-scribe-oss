---
title: Private, offline dictation on a Mac
description: Prepare Scribe for offline dictation, check which models are installed and see what stays on the Mac, including history and meeting audio.
keyword: offline dictation mac
updated: 2026-10-24
topic: Dictation on Mac
related: [privacy-and-permissions, models, languages, refine]
---

Scribe recognises speech and rewrites text on the Mac, with no audio or text uploaded. Before dictating offline, select the required languages and let their speech assets, plus any optional models needed, finish downloading.

## What needs downloading first?

Scribe uses Apple's on-device speech recognition by default. Selecting a language for the first time can trigger a system download of Apple's speech assets. Once installed, those assets provide local recognition with words streaming while speaking.

For languages Apple does not handle on-device, Scribe offers the optional **Parakeet language pack**. The **483 MB** pack supports 25 European languages and runs on the device. Languages Apple already handles stay on Apple's path. The pack transcribes after release rather than word by word.

Choose languages under **Settings › Languages**. The Mac supports up to three selected languages. The [Languages page](/docs/languages) lists the supported families and explains how Scribe checks availability on the device.

## Where does rewriting run?

Refine uses Apple Intelligence locally by default. **Gemma 4 E2B** is an optional **4.36 GB** download for devices without Apple Intelligence. It is selected under **Settings › Refine › Engine** and also runs on the Mac.

An installed speech language and an available Refine engine serve different purposes. Check both if rewriting is part of the planned offline use. If Apple Intelligence is off or its model is still downloading, Refine reports that it needs to be turned on in System Settings. [Refine](/docs/refine) lists the engine messages and alternatives.

## What network requests does Scribe make?

Optional models download from Hugging Face only when their download button is pressed. Scribe checks their size and checksum, and transfers can resume. **Meeting speakers**, the third optional model, is a **13.7 MB** download for separating speakers in meeting transcripts.

Apple manages its own speech-asset downloads. On the Mac, update checks happen when requested or when automatic checking has been enabled. Scribe has no analytics or telemetry. [Optional models](/docs/models) lists the downloads and where to delete them.

These downloads and checks are separate from audio processing. “On-device dictation” describes where recognition happens; installing a new model still needs a connection.

## What text and audio are kept?

Scribe does not store dictation audio. Dictated text can remain in the Library according to **Keep history**: Off, 1 day, 30 days or Forever. The default is Forever. Edited, pinned and typed notes are kept until deleted, so the history setting is not a blanket expiry for every note.

Meeting capture is saved while recording so Scribe can recover it after an unexpected quit. For completed meetings, **Keep recordings' audio** controls retention: by default the audio is deleted once the transcript exists. Turn the setting on before recording to retain audio for playback. Imported files are copied into Scribe's storage; the original stays untouched.

Deleted notes and meetings remain in Recently Deleted for 30 days. Notes, models and meeting data live in Application Support on the Mac. Device backups follow the computer or iCloud backup settings. Local processing does not prevent a backup service from copying stored files.

## Does Scribe read the screen?

With **Use screen context** enabled, Scribe reads limited text from the window receiving the dictation. Names and surrounding text help Refine spell terms and understand replies. This reading stays on the Mac and is never stored. The setting is under **Settings › Refine**.

Accessibility access lets Scribe notice the talk shortcut and insert text into apps. Microphone access supplies the speech. System Audio Recording is used for the other side of a meeting call. [Privacy and permissions](/docs/privacy-and-permissions) explains each permission and the stored data.

## How can I check offline use?

Finish the chosen downloads, disconnect the Mac from the network and dictate a short note. If using Refine, test it as well. Compare the inserted text with what was spoken. Testing recognition and rewriting separately helps identify which asset or engine needs attention.

For any dictation app, read its processing and retention statements directly. Look for separate answers about speech recognition, rewriting and saved history.

## Try it

[Download Scribe for Mac](/download), prepare the required languages and test a short offline dictation. Check [Privacy and permissions](/docs/privacy-and-permissions) before choosing history and screen-context settings.
