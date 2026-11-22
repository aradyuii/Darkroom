# Themes

Two themes, chosen in one place: Settings → Appearance. The choice is remembered
between launches.

**Soft Light** is the main theme and the one a fresh install opens in: a black
field lit by the chosen palette, white capsules for anything you can press, and
saturated gradient cards for the figures. **Darkroom** is the alternative: the
app's original interface, with frosted panels, a capsule dock and a lit bench
behind everything.

Both are drawn by the app's own screens. There is no theme renderer between them
and the UI: `Theme` and `SoftGlassTheme` resolve every token, and each screen
reads those tokens when it builds its body. The app's data, maths and engine are
untouched — both themes read the same `LibraryStore`, `JournalStore` and
`SessionSetupView`.

One palette, both themes:

- `ThemeChoice` (in `Design/ThemeStore.swift`) lists the two themes in the order
  Appearance shows them. Soft Light is declared first and is the default.
  Darkroom keeps the raw value earlier builds stored for it, so a stored choice
  survives the change; a value left by a theme this build no longer ships does
  not parse and falls back to Soft Light.
- `ThemeStore` is the single source of truth for the chosen theme and the
  interface density. It writes through to `UserDefaults`, publishes on every
  change and bumps `AppearanceStore.revision` so the tab stack is re-dressed.
- `Preferences.accent` is the palette, a choice of nine lamps. `Theme` reads it
  for Darkroom; `SoftGlassTheme` reads it for Soft Light's cards, tiles and
  field.
- `AppearanceStore` holds no choice of its own. It publishes the revision the
  tab stack is rebuilt on, and the Settings sheet state.

## The themes

01 **Soft Light** (main) — a black field lit by the palette, white capsules for
anything you can press, and colour cards for the figures.
02 **Darkroom** (alternative) — frosted panels, a capsule dock, a lit bench.

## Appearance controls

- **Theme** — Soft Light or Darkroom. Applied on tap.
- **Palette** — nine lamps: safelight, ruby, ember, rose, violet, sky, ice, mint
  and lime. Applies to both themes immediately.
- **Interface density** — compact, regular or spacious. Compact also shortens the
  native controls.

The reset returns to Soft Light, the safelight palette and regular density.

## Adding a third theme

A third theme is a third branch in `Theme` (and a field, card and control style
in the app's screens), plus a case on `ThemeChoice` with its own `name`, `role`,
`glyph` and `tagline`. Nothing else has to learn about it: the picker in
`Settings/AppearanceView.swift` iterates `ThemeChoice.allCases`, and the rest of
the app resolves its colours through `Theme`.
