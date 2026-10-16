# Changelog

## 2.0.0-beta.6 - October 16, 2026

- Add an icon font selector: Game default, Friz Quadrata, Arial Narrow, Morpheus and Skurri, applied to timers and stack text on the target and nameplates.
- Add horizontal and vertical nameplate icon offsets from -300 to 300 pixels, preserving existing above/below placement and separation.
- Update live settings previews for fonts and offsets, fitting extreme positions inside the preview area.
- Include the new settings in Reset appearance; existing saved profiles retain their current appearance.

## 2.0.0-beta.5 - October 15, 2026

- Move settings out of the Blizzard AddOns panel into a standalone Drpulse window.
- Add a draggable title bar, close button, and Escape-key support.
- Preserve the General, Appearance, Detection, Tools, and Guide navigation in the new window.
- Add a persistent support area with an optional PayPal donation link that can be selected and copied.
- Route `/drpulse`, the minimap launcher, AddOn Compartment, and target-display settings shortcut to the standalone window.
- Remove the active ForeverSettings dependency and legacy AddOns-panel registration.
- Update the CurseForge description with the current features, data-confidence behavior, installation steps, and complete command list.

## 2.0.0-beta.4 — October 15, 2026

- Replace the inherited accordion settings layout with a Drpulse control deck split into General, Appearance, Detection, Tools and Guide.
- Standardize the public command and every help reference on `/drpulse`; remove the `/rdr` alias.
- Keep all in-game text and release documentation in English.

## 2.0.0-beta.3 — October 15, 2026

- Enlarge and center the three DR application markers, scaling their width and height to the icon size.
- Add a dark backing behind the markers for contrast against spell artwork and cooldown shading.
- Tracking and timer calculations are unchanged.

## 2.0.0-beta.2 — October 15, 2026

- Restyle live icons and previews with a navy shell, cyan corner accent, thin stage rail and segmented application markers.
- Prefix estimated countdowns with ~ and clarify unconfirmed immunity in tooltips.
- Keep tracking calculations unchanged. The timer measures time until DR reset, not remaining CC duration.

## 2.0.0-beta.1 — October 15, 2026

- Replace the active runtime with a complete MIT-attributed adaptation of Forever DR 0.8.0, including its tracker, evidence sources, catalog, settings, menus and previews.
- Restore reference behavior when native DR is unsupported, including unconfirmed cast estimates, pet/group casts and combat feedback.
- Use Drpulse-specific commands, globals and saved data, with non-destructive migration of compatible 1.x settings.
- Introduce cyan accents and dark blue hover states; retain the Drpulse minimap launcher.
- Match 12 offline behavior scenarios against the original ZIP; verify migration and startup wiring. Real-client visual and combat validation remains pending.
- Target and nameplate displays follow the reference. The separate 1.x focus bar and history are not part of this runtime.

## 1.0.13 — October 15, 2026

- Preserve known spell IDs when returned aura identities are restricted.
- Process partial native countdowns without extending timers on duplicate events.
- Let readable auras end independently of restricted effects.
- Correlate recent direct player CC casts with opaque native events on the same enemy; show unknown timing and percentage for estimated evidence. Casts alone do not create DR.
- Expand the provisional effect catalog from the reference addon, including higher ranks, trap effects and item CC.
- Retry enabling Blizzard's native feed after combat and option changes.
- Add regression coverage for per-spell scans, opaque correlation and per-unit watchers. In-game validation remains pending.

## 1.0.12 — October 15, 2026

- Read only client-approved crowd-control auras by spell ID, avoiding blocked full aura enumeration on Forever.
- Register aura and native DR events per observed unit so restricted event payloads do not hide target, focus or nameplate updates.
- Share DR state by full player name when Forever hides the hostile GUID.
- Preserve the existing interface and settings.

## 1.0.11 — October 15, 2026

- Skip client-marked restricted aura indexes when the per-index access predicate is available, allowing later readable CC entries to be processed.
- Preserve and report the actual aura API error; back off failed polling for one second while continuing to process aura events.
- Recognize secret event tables before iterating them.
- Preserve a single application when an aura instance ID becomes readable or restricted.
- Stop treating changes to an existing aura's timing as proof of another application; mark the percentage unknown instead.
- Retain a bounded unknown indicator after observation is lost, without claiming active CC, immunity or a precise cooldown. Remove it automatically after the configured reset window.
- Mark countdown timing unknown when removal was only discovered after a gap.
- Clarify that 50 / 25 / IMM describes the estimated next CC.
- Passed 39 core and 50 lifecycle/UI offline tests. In-game validation remains pending; no accurate DR can be reconstructed if both native events and readable aura data are unavailable.

## 1.0.10 — October 15, 2026

- Process readable crowd-control auras even when other auras on the same unit are restricted.
- Consume readable UNIT_AURA additions, updates and removals immediately, without waiting for polling.
- Limit unavailable indicators to the affected categories instead of hiding every estimated DR on the unit.
- Preserve aura identities across partial scans; show an unknown percentage after an observation gap instead of restarting the count at 50%.
- Expand /drpulse status with the version, aura events, readable CC data, scan errors and unreadable entries.
- Passed 32 core and 48 lifecycle/UI offline tests; this fix still needs validation in Forever. Fully restricted CC cannot be identified without readable aura data or native DR events.

## 1.0.9 — October 15, 2026

- Recheck visible nameplate auras periodically, including plates that become hostile when a duel starts, without requiring another target selection or aura event.
- Detect repeated crowd control with the same aura instance ID when readable application times change, including shorter Polymorph refreshes.
- Recover readable aura tracking when native DR state is cleared or expires while the aura remains visible.
- Preserve the existing DR position above nameplates.
- Pass 32 core and 39 lifecycle/UI offline tests, covering all eight native DR categories, all seven categories with built-in aura fallback, and independent simultaneous categories. Validation of this fix in the Forever client is pending.

## 1.0.8 — October 15, 2026

- Show a short, colored login message with the version and settings command.

## 1.0.7 — October 15, 2026

- Track visible target, focus, and nameplate DR while GUID or attackability is restricted by the client. Token-scoped state is cleared when the observed unit changes, so it cannot be reused for another enemy.
- Show native DR timers when the immunity flag alone is restricted; show `?` for the unknown percentage.
- Estimate readable CC auras by spell ID when the aura instance ID is unavailable.
- Recognize additional level-60 ranks of Polymorph, Hammer of Justice, Fear, Frost Nova, Entangling Roots, Freezing Trap, and Kidney Shot in the aura fallback.
- Add `/drpulse status` diagnostics for native events, restricted data, visible units, and display settings.
- Avoid refreshing nameplates with no DR state on every timer tick.
- Keep rejecting explicitly friendly or nonexistent units. In-game validation is still pending.

## 1.0.6 — October 14, 2026

- Fixed settings controls rendering over the PayPal window. The dialog now uses a dedicated modal layer with an opaque background and blocks clicks behind it.
- Improved settings spacing, section headings, footer alignment, and support button text fit.
- Added a draggable minimap button: left-click opens settings; right-click locks or unlocks the tracker bars.
- Minimap position and visibility are saved between sessions. Toggle visibility in settings or with `/drpulse minimap`.
- Closing the support dialog releases keyboard focus and removes the background input blocker.
- All 45 offline automated tests pass. In-game visual validation is still pending.

## 1.0.5 — 2026-10-14

- Redesigned the support experience with a prominent but restrained button and a dedicated PayPal dialog.
- Clarified that Drpulse will remain free and donations are optional and one-time.
- Added `/drpulse donate` and `/drpulse support` commands.
- Added the direct PayPal link to README and CurseForge.
- The link is selected for copying with `Ctrl+C`; the addon does not attempt to open a browser.

## 1.0.4 — 2026-10-14

- Translated in-game text to English, including Target and Focus bars, categories, settings, and history.
- Added a Donate button that displays the selected PayPal link for copying; WoW addons cannot open a browser directly.
- 39 automated offline tests. Validation in the Forever client remains pending.

## 1.0.2-beta.2 — 2026-10-14

- Rebranded to Drpulse, including the `/drpulse` command and the `Drpulse` package folder.
- Added read compatibility to migrate `DRiftDB` into `DrpulseDB` when the previous variable is available.
- 37 offline tests. Distribution marked Beta; combat rules and client behavior remain pending validation.

## 1.0.2-beta.1 — 2026-10-13

- Recovered SavedVariables with invalid types, ranges, and anchors.
- Rejected unreadable or malformed events, tables, and numbers before operating on them.
- Hid estimates during aura restrictions and reset counts when visibility returned.
- Protected against delayed native removals; associated arena events with already observed GUIDs.
- Limited tracking to attackable units; cleared state on world changes and performed initial target/focus reads.
- Fixed first history access, history closing, and settings reset synchronization.
- Kept radial animation stable across ticks, disabled duplicate numbers, and added a fallback icon when spell artwork is unavailable.
- Disabling the local feed preserves the Blizzard native UI preference.
- 36 offline tests. Distribution marked Beta; combat rules and client behavior remain pending validation.

## 1.0.1 — 2026-10-13

- Based identity only on readable GUIDs to avoid merging enemies.
- Estimated reset after the last aura in each category without expiring during active CC.
- Prioritized the native feed and removed the 0.35-second temporal deduplication.
- Marked unknown percentages with `?`; preserved native immunity and duration data.
- Added regression coverage for identity, aura lifecycle, and source priority.

## 1.0.0 — 2026-10-13

- First release for WoW: Forever 1.60.1.
- Target, focus, and nameplates.
- SpellDiminishUI integration with a safe aura fallback.
- Settings, preview, history, and confidence indicator.

