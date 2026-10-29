# Design direction: Salle obscure

Chosen on 2026-10-29 from two mockups ("Salle obscure" and "Vague").

## Identity

Nami is where you watch anime in the evening, so the interface behaves like a dark cinema:
the room is black and quiet, and the anime artwork is the only thing that brings color.

## Dials

Dial: ENERGY 1 / RHYTHM 2 / MOTION 1

- ENERGY 1: the chrome stays out of the way; covers and banners carry the emotion.
- RHYTHM 2: consistent screens with one strong break per screen (the full-bleed banner).
- MOTION 1: state changes and hover/press feedback only; no decorative animation.

## Palette

| Token | Value | Use |
|---|---|---|
| Ground | `#0A0A0B` | every screen background |
| Text | `#EDEAE4` | titles and body (warm off-white, softer than pure white at night) |
| Text secondary | `#B8B3AA` | metadata, captions (contrast about 9:1 on ground) |
| Text muted | `#8F8B83` | inactive tabs only (about 5.6:1) |
| Line | `#EDEAE4` at 8-15 % | separators, progress track |
| Accent | the anime's own `coverImage.color` from AniList | progress fill, "next episode" marker |

There is no fixed brand accent: each anime page is tinted by its own color, which is the
identity motif. Primary buttons are off-white on black (`#EDEAE4` / `#0A0A0B`).
If an anime has no color, the accent falls back to the text color. The sources sheet uses it
too: the recommended card's border and its Play button.

The only fixed colors are the three seeder levels in the sources sheet, because they carry
meaning (how fast playback starts). Each comes with a signal icon and a word, so the color
is never the only cue:

| Level | Seeders | Color | Contrast on the sheet (`#131315`) |
|---|---|---|---|
| Well seeded | 50+ | `#6FD39B` | 10.1:1 |
| Fairly seeded | 5-49 | `#F2C14E` | 11.1:1 |
| Slow start | under 5 | `#FF8A80` | 8.1:1 |

## Typography

- One family, **Hanken Grotesk** (400/500/600/700): plain and readable at small sizes, tabular
  enough for episode numbers and times. Titles and headings use it in bold (700).
- Sizes: hero title 32, page title 28, app bar 22, section 20, body 14-15, captions 12-13.

## Shape and depth

- Radius: 4 for covers and thumbnails, 6 for buttons. Nothing is pill-shaped.
- No shadows and no glow: depth comes from the gradient that fades banners into the ground.
- Icons: thin stroke (1.8), only where they carry meaning (play, back, search, tabs).

## Accessibility rules

Measured with the WCAG 2.x formula; keep them when adding screens.

- Text over artwork sits on `TextScrim`: at least 80 % ground behind it. Secondary text needs
  76 % over a white pixel to reach 4.5:1, so a lighter fade fails on bright banners.
- Control borders use `Nami.border` (text at 45 %, 3.9:1). Lighter borders fail the 3:1
  minimum for component boundaries.
- Dimmed content dims the picture, never the text: text at 55 % opacity drops to 3.5:1.
- The anime accent goes through `Nami.accentOf`, which lightens dark colors to 4.5:1.
- Keyboard focus is shown by `FocusOutline` (a 2 px off-white ring, 16:1). Material's own focus
  overlay is 1.5:1 on black. Wrap every new focusable row, card and button in it.
- Layouts grow with the text size (tested at 200 %): no fixed heights around text, cover widths
  follow the text scale, rows wrap instead of clipping.
- Widths: bottom bar under 900 px, side rail above; reading width capped at 760 px.

## Screens

- Home: a full-bleed "À reprendre" banner for the anime you are watching (or the top trending one
  when logged out), then horizontal rows. One focal point: the resume button.
- Anime page: banner fading into black, serif title, progress line in the anime's color,
  one off-white "Regarder l'épisode N" button, episode list with the next episode outlined.
- Player: black, controls appear on tap and hide after 4 s.
