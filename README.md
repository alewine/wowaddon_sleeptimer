<p align="center"><img src="logo.png" width="180" alt="SleepTimer logo"></p>

# SleepTimer

Shows what is controlling your character and counts down until control returns.

Built for **World of Warcraft: The Burning Crusade Classic — Anniversary
Edition** (2.5.6, interface 20506).

![alert](https://raw.githubusercontent.com/alewine/wowaddon_sleeptimer/main/media/alert.png)

## What it does

When something takes control of you — polymorph, fear, stun, sleep, charm —
a single alert appears with the effect's icon, its name, and a countdown. The
backdrop pulses once per second, in time with the number, so you can track it
in peripheral vision while watching raid frames.

That is the whole addon. One frame, for you, for loss of control.

## Why it is small

The client exposes `C_LossOfControl`, which reports every active control
effect with its category, spell, icon and remaining time. SleepTimer reads
that directly instead of maintaining a spell ID table and scanning auras, so
there is nothing to update when a new source of crowd control appears.

## Overlapping effects

When more than one effect is active, the alert shows the one ending **last**.
A two-second stun landing on top of a six-second fear should not shorten your
countdown to two — the question the frame answers is "when do I get control
back". When the displayed effect expires it re-checks rather than hiding, in
case something longer is still running.

## Categories

Effects that genuinely take control away are on by default: stun, fear,
confuse, charm, possess, sleep, horror, banish, shackle.

Root, snare, daze, disarm, silence, pacify and school interrupt are
recognised but **off** — you are still driving through those. Turn any of
them on in the options window; silence and school interrupt are worth
considering if you heal.

## Options

`/st` opens the options window. Opening it unlocks the alert frame so you can
drag it; closing it locks the frame again.

| Command | Effect |
| --- | --- |
| `/st` | open or close the options window |
| `/st scale <0.5-3.0>` | overall size |
| `/st pulse` | toggle the one-second pulse |
| `/st test [seconds]` | start or stop a preview |
| `/st reset` | recentre the alert |

Test draws a random effect from your enabled categories, so the preview shows
what you will actually see rather than always the same spell.

## Installation

Install from CurseForge with your addon manager, or drop the `SleepTimer`
folder into:

```
World of Warcraft/_anniversary_/Interface/AddOns/
```

## License

MIT. See [LICENSE](LICENSE).
