# FoxSay Design Language

FoxSay should read as a polished, professional macOS utility — the kind of app a
high-end Mac developer tools company would ship. The design language comes from
the app icon: a coral speech bubble with white waveform bars on a dark slate
ground. One accent color, quiet neutrals, native macOS feel.

## Palette

| Token | Value | Use |
|---|---|---|
| Accent (light) | `#E4443C` | AccentColor asset; all interactive tint |
| Accent (dark) | `#F26654` | AccentColor asset dark variant |
| Coral gradient | `#FF7A5C → #E4443C` | `LinearGradient.brandCoral`, hero/brand moments only |
| Slate | `#3C475C` / `#141924` | Overlay HUD and brand panels only |
| Status | system green / orange / red | Small dots and short labels only — never large fills |

Rules:

- **One accent.** Everything interactive (selection, toggles, filled buttons,
  filter pills, links) uses the accent, which comes free from the AccentColor
  asset. Never introduce blue, purple, teal, pink, or rainbow gradients.
- **Neutral surfaces.** Regular window/card surfaces use system semantic colors
  so light and dark mode both work. Slate is reserved for the floating overlay
  HUD and other explicitly-branded dark moments.
- **Status is small.** Green/amber/red appear as 7px dots (`StatusDot`) or short
  caption text, never as icon-badge fills or tinted cards. A warning banner may
  use `Color.statusWarning.opacity(0.1)` background at most.

## Surfaces & layout

- Cards: use `.cardSurface()` (10pt continuous corners, 4% primary fill, 7%
  hairline stroke, 16pt padding). No `.textBackgroundColor` fills, no mixed
  corner radii (8/10/12 → always 10).
- Pane layout: 24pt outer margin, 20pt between sections, 10pt between rows.
- Every pane header: title (`.title2` semibold) + one-line secondary
  description. No version strings in pane headers.

## Type & iconography

- System font only. Values/numbers may use `.rounded` design.
- Chips/badges: `ChipLabel` — neutral by default, tinted only for the single
  badge that matters ("Recommended", "Active").
- SF Symbols render monochrome in `.secondary`, or accent when active. No
  multicolor icon-badge tiles (colored rounded-rect backgrounds behind icons
  should be `Color.primary.opacity(0.06)` neutral, or a subtle accent tint when
  the item is active).

## Motion

- Standard transitions: `.easeOut(duration: 0.18)`; springs
  `.spring(response: 0.35, dampingFraction: 0.85)` for panels/overlays.
- No `repeatForever` pulse rings. The only permitted looping animation is the
  recording dot's gentle opacity pulse and honest progress indicators
  (`ProgressView`, not spinning SF Symbols).
- Waveform visualizations are driven by `TimelineView(.animation)` with
  exponential attack/decay smoothing of the live level — no per-frame
  `withAnimation`, no random jitter injected for "visual interest".

## The overlay HUD

The floating recording overlay is the most-seen piece of the app and should
echo the icon: slate background (`brandSlateDeep`), rounded waveform bars in
white/coral, 14pt corners, 1px white 8% border, soft shadow. Monochrome bars —
no green→red level colors, no pink→cyan spectrum ramps.
