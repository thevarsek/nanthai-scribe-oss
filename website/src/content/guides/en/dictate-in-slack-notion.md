---
title: Dictate in Slack, Notion and other apps on Mac
description: Hold a key to dictate at the cursor in Slack, Notion or any Mac app, with the tone chosen per app and fixes for text in the wrong place.
keyword: dictate in slack
updated: 2026-10-24
topic: Dictation on Mac
related: [dictate-mac, style-by-app, troubleshooting]
---

On a Mac, Scribe works in any app that has a text field. Click into the field in Slack, Notion or another app, hold the talk shortcut and speak. When you let go, the text is typed at the cursor. You do not need to set anything up per app for this to work.

## How does dictation reach the cursor?

Scribe types into whichever field had focus when you pressed the shortcut. It puts the text on the clipboard, pastes it, and then puts back whatever was on your clipboard before. If something else copies to the clipboard while you are speaking, Scribe leaves that newer content alone.

The floating bar at the bottom of the screen never takes focus, so the cursor stays where it was. The bar shows **Listening…** while you speak and **Finishing…** while the last words settle.

## Which tone does Scribe use in each app?

When you use Refine, Scribe picks a tone from the app in front. [Style by app](/docs/style-by-app) lists the rules:

- **Casual** is built in for messaging apps, including **Slack**, Messages, WhatsApp, Telegram, Signal and Discord.
- **Code** is built in for editors and terminals such as Xcode, Terminal and VS Code.
- Apps without a rule use your default tone. Check the app list to see which rules are set on your Mac.

You can change any app's tone under **Settings › Refine › Style by app**. Click **+** to add an installed app that is not listed. A tone you speak during the dictation, such as "more formal", still wins over the app rule.

Refine is optional. Without it, Scribe only removes fillers such as "um" and "uh", tidies spacing and capitalises the first letter.

## How do I turn Refine on for one message?

Hold the talk shortcut, press <kbd>⌘</kbd> at any point during the hold, and speak. A **Refine** chip appears in the floating bar. When you let go, the bar shows **Refining…** while the words are rewritten.

For a message that needs a different tone, say so as you speak. Refine rewrites what you said and does not reply to it, so a question stays a question.

## What if the text lands in the wrong place?

Scribe targets the field that had focus when you pressed the shortcut. Click into the right field, then choose **Paste Last Dictation** from the Scribe menu in the menu bar. It inserts your most recent dictation again.

The last ten dictations are listed under **Recent** in the same menu. Click one to copy it, then paste it where you need it.

If nothing happens when you hold the key, check **Accessibility** under **System Settings › Privacy & Security**. Scribe needs it to notice the shortcut and paste the text.

## Can I write a longer message without holding the key?

Tap <kbd>Shift</kbd> while holding the talk shortcut, then release it. The floating bar shows **Return to finish · Esc to cancel**. Speak the rest of the message and press <kbd>Return</kbd>, or the talk shortcut again, to insert it. <kbd>Esc</kbd> cancels the take. Return and Esc are swallowed, so they do not reach the app during hands-free dictation.

For a long document, try a paragraph at a time and check where each one lands. That also gives you a chance to review names and numbers before moving to the next paragraph.

## How do I revise text already in the app?

Select the passage, hold the talk shortcut and press <kbd>⌘</kbd>. Say an instruction such as “shorter” or “make it a list”, then release the shortcut. The result replaces the selected text. If the edit cannot be made, the selection stays unchanged.

App rules apply to Refine dictation. They do not affect presets in Scribe’s own Library editor. If you use a website in a browser, the docs describe choosing a tone for the app in front, rather than a separate rule for each website.

## Why does a password field stay empty?

Secure password fields block the paste that Scribe uses, so they stay empty. The same restriction applies when you use Scribe in a browser. Use ordinary message and document fields for dictation.

## Try it

[Download Scribe for Mac](/download), then dictate a short message into Slack or a blank Notion page. [Dictate on Mac](/docs/dictate-mac) covers the floating bar, hands-free mode and the common problems, and [Troubleshooting](/docs/troubleshooting) lists the rest.
