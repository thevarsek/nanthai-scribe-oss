---
title: Dictate in two languages without switching settings
description: Set up English and Italian in Scribe, check language downloads and keep translation separate. Mac supports three languages; iPhone supports two.
keyword: dictation multiple languages
updated: 2026-10-24
topic: Languages and vocabulary
related: [languages, models, dictate-mac, refine]
---

Scribe detects speech from the dictation languages selected in Settings, so English and Italian can share the same setup. The Mac allows up to three selected languages; Scribe for iPhone (coming soon) allows two.

## How do I add English and Italian?

On the Mac:

1. Open the menu bar menu and choose **Languages**, or open **Settings › Languages**.
2. Select English and Italian from the available languages and regional variants.
3. Let any speech-asset downloads finish.
4. Dictate a short sentence in English, then another in Italian.

Scribe listens for the selected languages and works out which one is being spoken. Switch between takes or within a sentence without changing a setting. This is language detection; translating the result is a separate Refine option.

The [Languages page](/docs/languages) lists the language families and regional variants verified on 18 October 2026. Scribe checks availability on the device itself, since Apple's offerings can change with OS updates.

## Does this pair need the Parakeet pack?

English and Italian are both on the documented Apple speech list. Selecting either may trigger a download of Apple's speech assets, handled by macOS. Once those assets are installed, recognition runs locally and streams words while speaking. The optional Parakeet pack is not needed for this pair where Apple's speech is available.

That distinction matters when preparing to dictate offline. Having installed Scribe does not mean every language's assets are already present. Select the required languages and finish their downloads before disconnecting.

## What if one language needs the pack?

For languages Apple's on-device speech does not cover, Scribe offers the **Parakeet language pack**. Polish, Czech and Greek are examples from its supported list. Settings shows **Download language pack** for languages that need it.

The pack is a **483 MB** download under **Settings › Languages › More languages**. It runs on the device and supports 25 European languages in total. Some overlap with Apple's list: Scribe keeps languages Apple already handles on Apple's path and uses the pack for the others. Adding the two lists together would overstate the language count.

The pack transcribes a whole take after release rather than streaming word by word. Its first load after a restart can take a while; Scribe warms it in the background when a pack language is selected. [Optional models](/docs/models) explains storage and removal.

## How is translation different?

By default, Refine writes in the language spoken. To speak Italian and produce English text, set **Output language** to English in the menu bar or **Settings › Refine**. Refine then translates while cleaning up the dictation.

A spoken instruction such as “translate this to Italian” also works. The selected dictation languages determine what Scribe listens for; the output language determines what Refine writes. Check the output setting if a correctly recognised sentence comes out in an unexpected language.

Translation uses Refine's engine: Apple Intelligence by default, or the optional Gemma 4 model. The [Refine page](/docs/refine#output-language) explains that setting and the messages shown when an engine is unavailable.

## What changes on iPhone?

Scribe for iPhone (coming soon) uses **Settings › Languages** too, with a maximum of two selected languages. The lower limit reflects keyboard memory: each language adds its own dictionary and suggestions.

The selected list also governs keyboard suggestions and autocorrect. Speech support and typed input are different: the iPhone letter keyboard has no Chinese, Japanese or Korean input method. Apple's keyboards remain available through the globe key for typing those scripts.

## How do I check the setup?

Start with one short take per language. On the Mac, click into a note, hold the talk shortcut and release after speaking. Compare the inserted words with the language spoken before adding Refine or a translation target. This keeps recognition and rewriting separate while checking the result.

## Try it

[Download Scribe for Mac](/download), choose the languages in Settings and test a sentence in each. [Dictate on Mac](/docs/dictate-mac) covers the shortcut and insertion controls.
