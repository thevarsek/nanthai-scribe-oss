---
title: Transcribe a meeting on Mac without uploading audio
description: Record or import meeting audio in Scribe on Mac. Speaker labels need an optional model; summaries use an available Refine engine.
keyword: transcribe meeting mac offline
updated: 2026-10-24
topic: Meetings and notes
related: [meetings, meeting-playback, transcribe-a-recording, refine]
---

Scribe records or imports meeting audio and transcribes it on the Mac without uploading it. Separating speakers requires the optional Meeting speakers model; summaries use an available Refine engine.

## Can Scribe record both sides of a call?

It captures the microphone and the audio of the apps on the call through macOS system audio. With the speaker model installed, the transcript can separate **You** from other speakers. The first time you record, macOS asks for the **System Audio Recording Only** permission.

In-person meetings work too. The Call audio row reads **None — in-person**. With the speaker model installed, Scribe can tell speakers apart using the microphone alone.

## How do I start a recording?

Choose **Record meeting** from the menu bar during a call, or click **Record** (⇧⌘R) in the Library toolbar. Then click **Start recording**.

While recording, the menu bar icon shows a small coral dot and the menu item shows the elapsed time. The Library shows separate levels for **Microphone** and **Call audio**. **Pause** and **Resume** let you take a break, and **Stop** ends the recording and starts processing. Scribe saves the audio as it goes, so if the app quits unexpectedly it recovers the recording on the next launch.

Dictation keeps working during a recording. The floating bar stays hidden.

## What does the recording reminder say?

The recording sheet says **Ask everyone for permission before you record. Recording laws vary by country.** The reminder can be switched off with **Don't show again**, or under **Settings › Meetings**.

## How do speaker labels work?

Speaker labels need the optional **Meeting speakers** model, a 13.7 MB download. Scribe offers it on the recording sheet as **Tell speakers apart**, and you can also download it under Settings › Meetings. It downloads only when you press its button.

With the model installed, turns are labelled **You**, **Speaker 1**, **Speaker 2** and so on. Click a speaker's name to rename them; the change applies to all of their turns. Without the model, the transcript is one continuous text.

If everyone shows as **Speaker 1**, install the model, then choose **Retry transcription** from the meeting's menu.

## What do I get after I stop?

Processing shows four steps: **Saving audio**, **Transcribing**, **Identifying speakers** (when the model is installed) and **Summarising**.

With a Refine engine available, the summary has up to six bullets and a checklist of action items, with owners where they were named. Gemma 4 summarises the transcript in one pass; Apple Intelligence works in chunks. A very short meeting shows **Too short to summarise**.

If neither engine is available, do not expect a generated summary. Check the engine under **Settings › Refine** and the availability messages on the [Refine page](/docs/refine#common-problems). Transcription and speaker detection have their own requirements.

Edit the transcript if something is wrong, then choose **Update summary** to regenerate the summary. You can also add your own notes, which save automatically. [Meetings on Mac](/docs/meetings) covers the rest of the Library view.

## Can I play the audio back?

Only if Scribe kept it. Audio is deleted after processing by default, and the transcript is what you keep. To keep audio, turn on **Keep recordings' audio** in Settings › Meetings before you record.

With audio kept, a player bar sits above the transcript, with play and pause, a scrubber, and a speed button that cycles 1×, 1.5× and 2×. Tap any timestamp to jump to that point. Turning the setting off stops keeping audio for future meetings and leaves existing recordings alone. See [Meeting audio playback](/docs/meeting-playback).

## Can I transcribe a recording I already have?

Yes. Scribe accepts m4a, mp3, wav, aac, caf and aiff files. Either open the Library, click the arrow next to **Record**, choose **Transcribe a Recording…** and pick the file, or drag the file from the Finder onto the Library window.

Scribe copies the file into its meeting storage and leaves your original untouched. The meeting's title is the file name without its extension, and its date is the file's creation date. You can change both. The same processing steps run, and the copy is kept only if **Keep recordings' audio** is on. Details are in [Transcribe a recording](/docs/transcribe-a-recording).

## Where does the meeting go?

Transcripts, summaries and any kept audio are stored on the Mac with your notes. Deleting a meeting removes all of it, but it waits 30 days in Recently Deleted first.

Copy a meeting's summary, transcript or both, or export it as Markdown or plain text.

## What if the language isn't installed?

Transcription uses your dictation languages. If you see **The meeting language isn't installed**, add the language spoken in the meeting under Settings › Languages. The optional language pack is available there for languages Apple does not handle on-device.

Scribe for iPhone (coming soon) records the microphone only. Use the Mac to capture both the microphone and app audio for an online call.

## Try it

[Download Scribe for Mac](/download) and record a short test meeting. [Meetings on Mac](/docs/meetings) walks through capture and processing.
