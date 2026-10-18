---
title: Optional models
description: "Three downloads you can add to Scribe: what each does, how big it is, where it lives, and how to remove it."
group: models
order: 2
platform: both
---

## Nothing downloads on its own

Scribe works out of the box with Apple's speech recognition and Apple Intelligence. Three optional models extend it. Each downloads only when you press its button, from Hugging Face, with a resumable transfer and size and checksum checks. Each can be deleted again from the same place.

| Model | Size | What it adds | Where |
|---|---|---|---|
| **Parakeet language pack** | 483 MB | Speech recognition for 25 European languages | Settings › Languages |
| **Gemma 4 E2B** | 4.36 GB | Refine on devices without Apple Intelligence; long meeting summaries | Settings › Refine › Engine |
| **Meeting speakers** | 13.7 MB | Tells speakers apart in meeting transcripts | Settings › Meetings, or the sheet before a recording |

Models live in Application Support on the Mac and in the app's container on iPhone. Deleting one frees the space immediately; you can download it again later.

## Parakeet language pack

NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0), converted to Core ML by FluidInference and run through FluidAudio. Used only for languages Apple does not handle on-device. Details in [Languages](/docs/languages#the-parakeet-language-pack).

## Gemma 4

Google Gemma 4 E2B, instruction-tuned, quantised to 4 bits (Apache 2.0), run with MLX on Apple silicon. Choose it under Settings › Refine › Engine; the download starts from a button under the picker.

Apple Intelligence is faster and more faithful for short dictations, so it stays the default. Gemma is for Macs and iPhones without Apple Intelligence, and for summarising a whole meeting transcript in one pass. On iPhone, Gemma runs only while the app is in the foreground; the keyboard always uses Apple Intelligence.

> Warning: 4.36 GB is a large download and needs that much free space plus room to work. On iPhone, download it on Wi-Fi with the phone plugged in.

## Meeting speakers

A small speaker-diarization model (pyannote segmentation plus WeSpeaker embeddings, via FluidAudio). With it installed, a meeting transcript separates **You** from **Speaker 1**, **Speaker 2** and so on, which you can rename. Without it, the transcript is one continuous text.

## Credits

Speech recognition: Apple. Optional language pack: NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0). Optional rewrite model: Google Gemma 4 (Apache 2.0). Speaker model: FluidAudio speaker diarization (pyannote segmentation and WeSpeaker). The same credits appear in Settings › About.
