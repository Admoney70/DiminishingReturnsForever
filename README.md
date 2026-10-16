# Diminishing Returns Forever

Diminishing-returns (DR) icons on your **Target** and **Focus** frames for **World of Warcraft: Forever** (interface `16001`).

This is a port of [MidnightDiminish](https://www.curseforge.com/wow/addons/midnightdiminish) 3.1.2 by splitheads (MIT). The features, options and look are the original's. The changes are what Forever needed, listed below. The first commit in this repository is the unmodified upstream release, so `git diff` against it shows the whole port.

## Features

- **Arena DR**: icons on the Target and Focus frames for whichever arena enemy you have targeted or focused, with independent positions for each frame. They can go on nameplates instead, or on both.
- **sArena-style borders**: green after the first application (the next one is halved), red after the second (the next one is immune), plus optional `1/2` and `2/2` text.
- **World DR**: in the open world, tracks crowd control you land on your target.
- **Blitz/battleground DR**: tracks your own crowd control on the Target and Focus frames in battlegrounds.
- Options for icon size, spacing, grow direction, fonts, border style, cooldown swipe and the DR reset time, plus profiles with import/export. A test mode previews icons you can drag into place.

## What was changed for Forever

1. **Arena DR works without Blizzard's arena frames.** The original copies the DR trays Blizzard attaches to its arena frames (`CompactArenaFrame`). Forever runs as the "camelot" game type, and its unit-frame `.toc` leaves `CompactArenaFrame` out, so those trays never exist and the original showed nothing in arenas.
   [`Modules/NativeTray.lua`](Modules/NativeTray.lua) builds a tray of its own for each arena enemy, fed by the same `UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED` event, and the original code copies it unchanged. Where Blizzard's arena frames do exist (retail), they are still used.
2. **Midnight "secret" values are handled.** If the DR timings or the immunity flag arrive secret, nothing passes them to an API that refuses secrets from add-on code: borders switch with `SetAlphaFromBoolean`, and the window is timed locally. An update whose category is secret is skipped, because there is no way to tell which icon it belongs to.
3. **The `.toc` lists `16001`**, so Forever no longer flags the add-on as out of date. Retail interface numbers (`120105`, `120100`) are still listed.
4. **Renamed**, with its own saved variables (`DiminishingReturnsForeverDB`), global, popup and window names, so it can't clash with an installed copy of MidnightDiminish. Settings are not imported from MidnightDiminish.

Everything else was checked against the Forever 1.60.1 client's UI source: every API function, event and frame template the add-on references exists there, as do the Target and Focus frames.

## Installation

1. Download or clone this repository.
2. Copy it into `Interface/AddOns/` in your WoW Forever install and name the folder **`DiminishingReturnsForever`** (it must match the `.toc` file name).
3. Restart the game client. A `/reload` does not pick up new add-on files.

Packaged builds made with the BigWigs packager are named correctly via `.pkgmeta`.

## Usage

- `/dr`: open the options window (also listed under *Esc → Options → AddOns*)
- `/dr debug`: arena diagnostics, including whether the add-on's own trays are in use and whether the client reports the DR system as supported
- `/dr blitz`: battleground diagnostics

The add-on turns on the game's `spellDiminishPVPEnemiesEnabled` setting (*Options → Gameplay → Spell Diminishing Returns*), which the DR event depends on.

## Known limits

- Arena DR depends on the Forever server sending DR updates for arena enemies (`arena1` to `arena5`). If icons never appear in an arena, run `/dr debug` there and check that the DR system is reported as supported.
- When DR timings arrive secret, the window is re-timed from each update rather than read from the event, so it can run up to a couple of seconds long.
- The DR rules themselves (reset time, two applications before immunity) follow retail Midnight. Forever's server may differ; the reset time can be changed under *Arena DR → Tracking*.

## Development

```sh
luacheck .            # lint
lua5.1 tests/run.lua  # tests against a small WoW API mock
```

`tests/widgetapi.lua` lists the widget methods of the Forever 1.60.1 client, generated from its API documentation. The mock accepts only those, so a call to a method Forever doesn't have fails the tests.

## Credits

MidnightDiminish by splitheads; this port keeps its MIT license (see [LICENSE](LICENSE)). The Ace3, LibStub and CallbackHandler libraries in `Libs/` are by their respective authors.
