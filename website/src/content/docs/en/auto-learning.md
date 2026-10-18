---
title: Auto-learning and Corrections
description: Scribe notices when you fix a word it inserted, asks once whether to remember it, then backs off. Review everything in Corrections.
group: dictionary
order: 2
platform: both
---

## Fix it, then remember it

When you correct a spelling in text Scribe just inserted, Scribe compares what it heard with what you typed. If the change looks like a spelling fix or a name, rather than a rewritten sentence, it asks:

> **Always spell “Okafore” as “Okafor”?** · Add · Not now

On the Mac the question appears in the floating bar; on iPhone, in the keyboard's suggestion bar and in the Library editor. **Add** saves the pair to your [Dictionary](/docs/dictionary): the intended spelling, with the misheard version under *Heard as*.

## It asks once, then backs off

- After one **Not now**, Scribe stays quiet until it has seen the same correction three more times, then asks once more.
- A second **Not now** marks the pair **Ignored** and it is never suggested again.
- Scribe never asks more than once every ten minutes, whatever you are doing.

Nothing is added without your say-so.

## Review Corrections

Open **Settings › Dictionary › Corrections**. Each row shows **heard → meant**, how often it was seen, and whether it is **Suggested** or **Ignored**.

- **Add** saves the pair to your Dictionary.
- **Ignore** leaves it out and stops the suggestion.
- **Forget** removes an ignored pair and resets its count, so it can be suggested again.

Entries that came from Corrections carry a **Learned** caption in the Dictionary and can be removed like any other.

## Keyboard words

The iPhone keyboard learns too. If autocorrect changes a word and you put your spelling back twice, the keyboard stops correcting that word. Review the list under **Settings › Dictionary › Keyboard words**, remove a word, or add one yourself. **Reset typing learning** in Settings › Keyboard clears this list along with the learned key positions.

## Private by design

Correction history, counts and the Dictionary live on the device. On iPhone they are shared with the keyboard through its App Group container, never uploaded. Mac and iPhone keep separate lists; a [backup](/docs/backup) includes Corrections.
