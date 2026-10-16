# Drpulse — WoW: Forever

Version 2.0.0-beta.6-friendly.1: Drpulse 2.0.0-beta.6 with **friendly DR tracking** added (see below). Adaptation of Forever DR 0.8.0 (reference ZIP), licensed under MIT with attribution to Tarolg. Drpulse integration and blue theme by Joaqoz.

Icons use a dark navy frame, cyan accent, and a bottom status rail. The `~` prefix marks an estimated time until DR resets; it does not represent the remaining CC duration. This visual update keeps the beta.1 tracking engine unchanged.

## Features

- Complete reference engine: per-spell auras, public/partial/opaque native feed, your own casts, pets and group members, failure feedback, and estimates when no observable confirmation is available.
- Target and nameplate displays, filters for your own categories, bag items, Auto/Always/Never category modes, and custom spells.
- Learned durations, reset after CC ends, percentages/pips/count display, previews, context menu, and diagnostics.
- Estimated indicators are grey and may represent a cast without confirmed impact. Disable them under Tracking sources → Show unconfirmed casts.
- If the native feed is reported as unsupported, the remaining sources continue to work as in the reference addon.
- Settings open in a standalone movable Drpulse window with fixed navigation, blue/cyan accents, and a selectable PayPal support link. The Drpulse minimap button remains available.

## Friendly DR tracking

Drpulse tracks DR on friendly players, not only the DR you put on enemies: you, your party (party1 to party4), and any friendly player you target, focus or see on a nameplate.

- **Friendly display.** A movable display with one row per player who has DR: their name in class colour, then their DR icons. It uses the same icons, stages, timers and tooltips as the target display, and is hidden while nobody has DR. It moves and locks with *Lock target display*; unlocked, it shows a blue strip to drag and a sample row.
- **Your own DR comes from loss of control.** Forever keeps loss-of-control data readable for your own character (it is secret only for other units), so your stuns, roots and the rest arrive with exact spell, start and length even where CC auras are secret. A spell outside the catalog counts only when its effect type maps to a single DR category (stun, root, silence, disarm).
- **Any friendly player you target, focus or see on a nameplate** is tracked too, for example both players in a duel you watch. Their DR shows on the target display and on their nameplate (turn on friendly nameplates to see it there).
- **Party members' DR comes from readable CC auras** on them and from Blizzard's DR feed, if Forever sends it for friendly units. Where a CC aura is secret and the feed sends nothing, a party member's DR can't be seen.
- Every category shows in the friendly display unless it is set to *Never* under Categories. *Only CC I can apply* does not apply here, because enemies apply this CC.
- Settings: *General → Friendly DR* (on/off, include yourself, icon size), and *Detection → Tracking sources → Loss of control on you*. `/drpulse friendly` turns it on or off. `/drpulse status` lists the watched friendly units and counts.

Friendly tracking is on by default. Existing `DrpulseV2DB` settings load unchanged; the new options take their defaults.

## Installation and migration

Close WoW completely. Replace the `Drpulse` folder under `Interface/AddOns` with the folder from the ZIP, then launch the game again. Test each addon separately when comparing results.

The new runtime uses `DrpulseV2DB`. Existing `DrpulseDB` and `DRiftDB` data remains untouched. Compatible settings are migrated: size, reset window, visibility, categories, custom spells, center position, and minimap preferences. New tracking sources start with the reference defaults. The old standalone focus bar and history are not part of this runtime; focus remains a tracking source.

## Commands

- `/drpulse`: open settings and list commands.
- `/drpulse status`: print sources, counters, native data, and Blizzard options.
- `/drpulse unlock` and `/drpulse lock`: move or lock the target display.
- `/drpulse preview`: show a temporary preview.
- `/drpulse clear`: clear current tracking data.
- `/drpulse all` and `/drpulse mine`: switch the global category filter.
- `/drpulse friendly`: turn friendly DR tracking on or off.
- `/drpulse reset`: restore the target display position.
- Minimap: left-click for settings, right-click to lock, drag to reposition.

## Validation

Twelve scenarios run against both the original ZIP and this adaptation: unsupported feed, repeated events, resistances, observable auras, pets/group, unconfirmed area effects, opaque events, secret identity, full names, expiry, duplicates, and restricted timing data.

Migration, data preservation, execution of both TOC module sets, and startup/command wiring are also checked. Startup tests replace visual constructors, so they do not validate pixels, taint, or the real client. This beta still requires in-game validation.

`Core.spec.lua` and `UI.spec.lua` cover the historical 1.x implementation, which remains in the repository but is not loaded or distributed with this beta.

## Development

```sh
luacheck .            # lint
lua5.1 tests/run.lua  # friendly-tracking tests against a small WoW API mock
```

`tests/widgetapi.lua` lists the widget methods of the Forever 1.60.1 client, generated from its API documentation; the mock accepts only those.

## License

MIT. `THIRD-PARTY-LICENSE.txt` preserves Tarolg's complete notice. Adapted modules include attribution. Reproducible import logic is in `scripts/import-reference.mts`; Drpulse-specific integrations are in `Runtime/Integration.lua`.
