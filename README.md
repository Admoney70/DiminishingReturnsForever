# Drpulse — WoW: Forever

Version 2.0.0-beta.6. Adaptation of Forever DR 0.8.0 (reference ZIP), licensed under MIT with attribution to Tarolg. Drpulse integration and blue theme by Joaqoz.

Icons use a dark navy frame, cyan accent, and a bottom status rail. The `~` prefix marks an estimated time until DR resets; it does not represent the remaining CC duration. This visual update keeps the beta.1 tracking engine unchanged.

## Features

- Complete reference engine: per-spell auras, public/partial/opaque native feed, your own casts, pets and group members, failure feedback, and estimates when no observable confirmation is available.
- Target and nameplate displays, filters for your own categories, bag items, Auto/Always/Never category modes, and custom spells.
- Learned durations, reset after CC ends, percentages/pips/count display, previews, context menu, and diagnostics.
- Estimated indicators are grey and may represent a cast without confirmed impact. Disable them under Tracking sources → Show unconfirmed casts.
- If the native feed is reported as unsupported, the remaining sources continue to work as in the reference addon.
- Settings open in a standalone movable Drpulse window with fixed navigation, blue/cyan accents, and a selectable PayPal support link. The Drpulse minimap button remains available.

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
- `/drpulse reset`: restore the target display position.
- Minimap: left-click for settings, right-click to lock, drag to reposition.

## Validation

Twelve scenarios run against both the original ZIP and this adaptation: unsupported feed, repeated events, resistances, observable auras, pets/group, unconfirmed area effects, opaque events, secret identity, full names, expiry, duplicates, and restricted timing data.

Migration, data preservation, execution of both TOC module sets, and startup/command wiring are also checked. Startup tests replace visual constructors, so they do not validate pixels, taint, or the real client. This beta still requires in-game validation.

`Core.spec.lua` and `UI.spec.lua` cover the historical 1.x implementation, which remains in the repository but is not loaded or distributed with this beta.

## License

MIT. `THIRD-PARTY-LICENSE.txt` preserves Tarolg's complete notice. Adapted modules include attribution. Reproducible import logic is in `scripts/import-reference.mts`; Drpulse-specific integrations are in `Runtime/Integration.lua`.
