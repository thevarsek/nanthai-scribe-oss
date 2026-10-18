---
title: Meetings on Mac
description: Record a call or an in-person meeting, get a transcript with speakers, a summary and action items, and play the audio back. All processed on the Mac.
group: meetings
order: 1
platform: mac
---

## Start a recording

> Warning: You must ask everyone for permission before you record or transcribe a conversation. Recording laws vary by country, and you are responsible for following them.

Choose **Record meeting** from the menu bar during a call, or click **Record** (<kbd>⇧⌘R</kbd>) in the Library toolbar.

A sheet says **Ask everyone for permission before you record. Recording laws vary by country.** It also offers **Tell speakers apart**, a one-time 13.7 MB model download that labels who said what. Tick **Don't show again** if you don't need the reminder, then click **Start recording**.

What you'll see: the menu bar icon gains a small coral dot, the menu item becomes **Stop recording · 12:04**, and the Library shows the timer with separate **Microphone** and **Call audio** levels.

## What is captured

- **Your microphone**, labelled **You**.
- **The other side**: the audio of the apps on the call, through macOS's system audio capture. The first time, macOS asks for the **System Audio Recording Only** permission.

In-person meetings work too: the Call audio row reads **None — in-person**, and the speaker model tells people apart from the microphone alone.

Dictation keeps working during a recording; the floating bar just stays hidden.

## While recording

**Pause** and **Resume** let you take a break; **Stop** finishes and starts processing. Capture is saved as it goes, so if Scribe quits unexpectedly it recovers the recording on the next launch.

## After you stop

Processing shows four steps: **Saving audio**, **Transcribing**, **Identifying speakers** (when the model is installed) and **Summarising**. Scribe transcribes both streams, labels turns as **You** and **Speaker 1**, **Speaker 2** and so on, and writes a summary of up to six bullets plus a checklist of action items with owners where they were said.

Summaries use your Refine engine: Gemma 4 summarises the whole transcript in one pass; Apple Intelligence works in chunks. Very short meetings show **Too short to summarise**.

Open the meeting in the Library window (**Open Scribe…**). Meetings sit below your notes in the sidebar, grouped by day.

- Click a speaker name to **rename** it; the change applies to all their turns.
- Add your own notes; they save automatically. Double-click a transcript turn to edit it.
- **Play** the audio, if it was kept, and tap any timestamp to jump there. See [Meeting audio playback](/docs/meeting-playback).
- **Copy** offers Summary, Transcript or Everything. **Export** as Markdown or plain text.
- **Update summary** regenerates the summary after you edit the transcript; **Retry transcription** reprocesses the audio, for instance after installing the speaker model.

## Settings › Meetings

- **Show reminder before recording**: the consent sheet.
- **Keep recordings' audio**: off by default. Scribe keeps the transcript and deletes the audio after processing unless this is on.
- **Speaker detection · 13.7 MB**: download or delete the speaker model.

## Privacy

Meeting audio is processed on your Mac and never sent anywhere. Transcripts, summaries and any kept audio are stored in Application Support alongside your notes. Delete a meeting to remove all of it; it waits 30 days in Recently Deleted.

## Common problems

**No call audio.** Check System Settings › Privacy & Security › Screen & System Audio Recording and make sure NanthAi Scribe is allowed. The Call audio row says **Not coming through** while nothing arrives.

**"The meeting language isn't installed."** Transcription uses your dictation languages. Add the language spoken in the meeting under Settings › Languages.

**Everyone is "Speaker 1".** Install the speaker model under Settings › Meetings, then choose **Retry transcription** in the meeting's menu.

**The summary is empty or wrong.** Edit the transcript, then **Update summary**. If Refine isn't available, see [Refine](/docs/refine#common-problems).
