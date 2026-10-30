# Design direction: Salle obscure

Chosen on 2026-10-29 from two mockups ("Salle obscure" and "Vague").

## Identity

Nami is where you watch anime in the evening, so the interface behaves like a dark cinema:
the room is black and quiet, and the anime artwork is the only thing that brings color.

## Dials

Dial: ENERGY 1 / RHYTHM 2 / MOTION 2

- ENERGY 1: the chrome stays out of the way; covers and banners carry the emotion.
- RHYTHM 2: consistent screens with one strong break per screen (the full-bleed banner).
- MOTION 2: everything that changes eases instead of jumping: hovers brighten (no grey boxes, no
  ripple on desktop), the chosen tab's bar grows, the hover card fades and grows in, pages fade when
  tabs change or content arrives, and the home banner cross-fades with a very slow push into the
  picture. Timings live in `Motion` (140 ms hover, 240 ms changes, 600 ms the banner); with reduced
  motion every duration is zero.

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
If an anime has no color, the accent falls back to the text color. The sources sheet stays out
of it: it is a plain neutral list, because anime colors can clash on a screen you stay on.

Seeder levels in the sources sheet are told apart by a signal icon and a word, in the secondary
text color. They were colored once; a list with green, yellow and red read as noisier than it was.

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
- Widths (touch screens): bottom bar under 900 px, side rail above; reading width capped at 760 px.

## Desktop (Windows)

The desktop layout follows the input device, not the width: Windows (and Linux, macOS) always get
it, from the 720 × 480 minimum window up. Phones and tablets keep the touch layout.

- Window: no system title bar. Artwork runs to the top edge, under a 32 px transparent strip that
  holds the window buttons and drags the window; plain pages start below it.
- Rail: 60 px on the left, icons only (40 × 40, the name in a tooltip), the "n" wordmark on top and
  the AniList avatar at the bottom. The selected item has a filled icon and a soft background. No
  divider: the rail fades from 94 % to 60 % ground so banners show faintly behind it. Page content
  starts 36 px after the rail.
- Mouse sizes: buttons 34 px high, body 13-14, captions 11-12, section titles 15 bold, page titles
  28-38, the home banner title 40. Mouse targets at least 32 px.
- Covers: one card everywhere. Hovering (or focusing) a cover for 400 ms opens a card beside it with
  the banner, facts, summary, Watch and My list. No shadow: the card surface `#1B1B1E` and a 1 px line
  set it apart.
- Sources slide in as a 440 px panel on the right over a 55 % ground scrim; Escape, ✕ or a click beside
  it closes it.
- Tabs are text with a count; the chosen one is bold with a 2 px bar 10 px under the text, on a 1 px
  line. Filters are flat tags (text at 7 %, the chosen one off-white with black text). No outlined
  Material chips, on desktop or on phones.
- Settings: sections on the left, one section at a time on the right (rows on lines, no cards).
- Keyboard: Ctrl+K or "/" opens Search; Escape clears it. The player shortcuts are listed in Settings.
- The app font has no star or arrow glyphs: use icons or words, never "★" or "←".

## Screens

- Home: a banner that cycles through up to five anime (the one to resume, new episodes, then
  trending), then rows: Continue, Today, Planned in your list, Because you watch…, the season,
  Trending, Top rated. Empty sections are hidden. The banner moves every 8 s, holds still under the
  pointer or the focus, and never moves by itself with reduced motion.
- Anime page: banner fading into black, serif title, progress line in the anime's color,
  one off-white "Regarder l'épisode N" button, episode list with the next episode outlined.
- Player: black, controls appear on tap and hide after 4 s.
