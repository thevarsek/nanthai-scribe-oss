---
title: Get started on Mac
description: Install Scribe from the DMG, grant two permissions, pick a talk shortcut and dictate into any app.
group: get-started
order: 1
platform: mac
---

## What you need

- A Mac with Apple silicon running **macOS 26**.
- About five minutes. No account, no subscription.

## Install

1. [Download the DMG](/download#mac). macOS opens it without any security warning.
2. Open the DMG and drag **NanthAi Scribe** onto the **Applications** folder next to it.
3. Open Scribe from Applications.

Scribe is a menu bar app. Look for the three-bar Trio mark at the top right of the screen; there is no Dock icon until you open the Library window.

## First launch

A short setup window walks you through the two permissions Scribe needs. Each step ticks itself when it is done.

1. **Allow Accessibility.** Scribe uses it to notice your talk shortcut and to type the result into the app you are in. Click **Open System Settings**, turn on NanthAi Scribe under Privacy & Security › Accessibility, and come back. The step ticks within a second or two; no relaunch is needed.
2. **Allow the microphone.** Click **Allow** and accept the system prompt.
3. **Try it.** Hold the key shown on screen and say something. Your words appear in the field.

> Tip: You can run the setup again at any time from **Settings › About › Show onboarding…**.

## Your first dictation

1. Click into any text field: Mail, Slack, a browser, a terminal.
2. Hold your talk shortcut. The default is the right <kbd>⌥ Option</kbd> key.
3. Say something. A small bar at the bottom of the screen shows your words as they arrive; the last few words are dimmed while Scribe is still deciding on them.
4. Let go. Scribe removes fillers like "um" and "uh", fixes spacing and capitalisation, and types the text at your cursor. Your clipboard is put back as it was.

While you hold the key you can add more:

| Do this | Result |
|---|---|
| Tap <kbd>Shift</kbd> | **Hands-free.** Let go of the shortcut and keep talking. <kbd>Return</kbd> finishes, <kbd>Esc</kbd> cancels. |
| Press <kbd>⌘</kbd> | **Refine.** What lands is clean writing in your chosen tone. See [Refine](/docs/refine). |
| Select text first, then press <kbd>⌘</kbd> | **Edit the selection.** Say what to change: "shorter", "make it a list". |

The menu bar menu shows your current shortcut and these chords as a reminder.

## Choose a different shortcut

Open **Settings › General › Talk shortcut** and click **Change…**, then press the key or combination you want. A single modifier (right <kbd>⌥</kbd>, right <kbd>⌘</kbd>, right <kbd>⌃</kbd> or <kbd>fn</kbd>), a combination with <kbd>⌃</kbd>, <kbd>⌥</kbd> or <kbd>⌘</kbd>, or a function key all work. Foot pedals and Stream Deck buttons work when set to send <kbd>F13</kbd>–<kbd>F20</kbd>. Details in [Talk shortcut](/docs/talk-shortcut).

## Settings worth a look

- **General › Open at login**, so the shortcut is ready after a restart.
- **General › Sounds**: a quiet tick when listening starts and a pop when text is inserted. On by default.
- **Languages**: pick up to three dictation languages; Scribe detects which one you are speaking. See [Languages](/docs/languages).
- **Refine › Use screen context**: reads the window you dictate into so names are spelled right. Stays on the Mac. Turn it off if you would rather Scribe never read the screen.
- **History & Privacy › Keep history**: Off, 1 day, 30 days or Forever. Dictation audio is never stored.

## Common problems

**Holding the key does nothing.** Accessibility is not granted yet, or you turned it off. Open System Settings › Privacy & Security › Accessibility and make sure NanthAi Scribe is on. The shortcut arms itself as soon as it is.

**The words go to the wrong place.** Scribe types into whatever had focus when you pressed the key. Click into the field first.

**macOS says the shortcut is already in use.** Pick another in Settings › General › Talk shortcut › Change….

More in [Troubleshooting](/docs/troubleshooting).
