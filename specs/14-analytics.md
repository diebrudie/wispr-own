# Spec 14 — Analytics screen

Built 2026-07-30. Backlog origin: `specs/12-future-features.md` §C.

## Why

Everything shown here was already in `transcripts` — timestamps, durations,
languages, target apps — and none of it was ever surfaced beyond three numbers
on Home. No new data is collected for this screen.

## What each panel answers

| Panel | Question | Form |
|---|---|---|
| Four tiles | How much have I dictated, and what did it save me? | Numbers, not charts |
| Words per day | Am I actually using this? | Bars on a date axis, last 30 days |
| When you dictate | What time of day do I speak? | Bars by hour |
| Where it lands | Which apps does this go into? | Ranked bars, named and numbered |
| Languages | What's the split? | Ranked bars |

**Time saved** compares words dictated against typing them at
`HistoryStore.typingWordsPerMinute` (40 wpm, average sustained speed). The
comparison is only as good as that constant, so it's named in code and printed
under the tile rather than presented as fact.

## Visual decisions

- **Tiles, not charts, for single values.** A one-bar bar chart says less than
  the number does.
- **One hue, no categorical palette.** Every panel is a single series — how much
  per bucket — so nothing needs colour to carry identity. That also means no
  legend anywhere: each panel's title names its series.
- **`Theme.chartMark` is a new token, separate from `Theme.accent`.** The dark
  accent is deliberately light (L 0.765) so *text* clears WCAG-AA on the dark
  surface; as a bar fill that is out of the 0.48–0.67 band for dark marks and
  glares. The dark mark step is `#8B6FE8` (L 0.60). Both steps were run through
  the data-viz validator — lightness band, chroma floor, contrast — rather than
  eyeballed, and the dark step was **chosen** for its surface, not flipped.
- Thin marks (60% of the slot), 4px rounded data-ends on the baseline, recessive
  gridlines in `Theme.border`.
- Hovering either chart selects a bar and shows its exact value; the other bars
  dim. Without it the only readable numbers would be the axis ticks.

## Verification

**`WisprOwn --snapshot <path.png> [dark]`** renders the screen off-screen against
the real history. That flag exists because the two bugs on this screen were both
invisible to the compiler and to the colour validator:

1. **The hour chart drew no bars at all.** `width: .ratio(0.6)` has no step size
   to take a ratio of on a numeric axis, so Charts silently drew nothing — the
   y-axis still scaled to the data, which made it look like a styling problem
   rather than missing marks. Fixed with `.fixed(9)`.
2. **The screen title was invisible**, resolving its colour against the system
   appearance instead of the rendered one. Fixed with an explicit
   `.foregroundStyle(.primary)`.

Both were caught by looking at the rendered PNG. `screencapture` needs Screen
Recording permission, hence rendering rather than screenshotting; the split of
`AnalyticsContent` (data in, layout out) from `AnalyticsView` (app-state
plumbing) is what makes it renderable headlessly.

## Known gaps

- The 30-day window is fixed — no range picker.
- `analytics()` is a full table scan, run when the screen appears. Fine for a
  personal log; it would need real SQL aggregates at a much larger scale.
- No CSV export.
