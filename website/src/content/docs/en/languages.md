---
title: Languages
description: Dictate in several languages without switching anything. Apple's on-device speech covers the main ones; the optional Parakeet pack adds 25 European languages.
group: models
order: 1
platform: both
---

## Choose your languages

- **Mac**: the menu bar menu › Languages, or Settings › Languages. Up to **three**.
- **iPhone**: Settings › Languages. Up to **two**.

Scribe listens for all of them at once and works out which one you are speaking, so you can switch mid-day, or mid-sentence, without touching a setting.

Everything language-dependent follows this list: keyboard suggestions and autocorrect, long-press accents, the Refine output language, translation targets.

## Apple speech

By default Scribe uses Apple's on-device speech recognition. The first time you pick a language, macOS or iOS downloads Apple's speech assets for it; that is a system download handled by Apple. After that, recognition is entirely local and streams word by word while you talk.

Which languages Apple offers depends on your device and OS version. Scribe lists what is installed first. The language families and regional variants verified on 18 October 2026:

| Language | Regional variants |
|---|---|
| Cantonese | China mainland |
| Chinese | China mainland, Hong Kong, Taiwan |
| English | Australia, Canada, India, Ireland, New Zealand, Singapore, South Africa, United Kingdom, United States |
| French | Belgium, Canada, France, Switzerland |
| German | Austria, Germany, Switzerland |
| Italian | Italy, Switzerland |
| Japanese | Japan |
| Korean | South Korea |
| Portuguese | Brazil, Portugal |
| Spanish | Chile, Mexico, Spain, United States |

The app checks availability on your own device; assets and variants change with OS updates.

## The Parakeet language pack

Many European languages are not covered by Apple's on-device speech. For those, Scribe offers an optional **language pack**: NVIDIA's Parakeet TDT 0.6B v3 model, converted to Core ML and run on your device. It understands 25 languages:

Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish, Ukrainian.

- **Size**: 483 MB, downloaded once when you ask, under Settings › Languages › *More languages*.
- Languages Apple already handles stay on Apple's faster path; only the others go to the pack. Until it is installed, those languages show **Download language pack**.
- The pack transcribes the whole take when you let go rather than word by word, so the live preview is shorter in those languages.
- The first load after a restart takes a while, around 45 seconds on a recent Mac. Scribe warms it in the background when a pack language is selected.

> Note: Downloading is the only time the pack touches the network. See [Optional models](/docs/models) for sizes, licences and how to delete it.

## Output language and translation

Refine can write in a language other than the one you spoke. See [Refine › Output language](/docs/refine#output-language).

## Chinese, Japanese, Korean

Dictation depends on what Apple's speech offers on your device. The iPhone letter keyboard has no input method for these scripts; use Apple's keyboards for typing them, via the globe key.

## Typing languages

The iPhone keyboard's autocorrect, suggestions and swipe typing follow the same language list and cover 33 languages. The list is in [The iPhone keyboard](/docs/keyboard#suggestions-and-autocorrect).
