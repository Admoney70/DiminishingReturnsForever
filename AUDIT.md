# Audit 2.0.0-beta.1 — October 15, 2026

The active foundation is replaced by the nine modules from the Forever DR 0.8.0 ZIP, adapted under MIT. The TOC files load Runtime and the minimap integration; they do not load the 1.x Bootstrap/Core/UI/Options/Data modules.

Import transformations affect product names, commands, globals, module names, visual accents, and integration points. The engine and evidence adapters preserve the reference algorithms. `Integration.lua` adds non-destructive migration and the minimap bridge.

Verification: 12 functional scenarios executed against both implementations (24 runs), plus migration, reload, incompatible schema handling, parsing of every TOC module, and startup with visual constructors replaced. No Fengari errors.

Pending: validation of settings, previews, rendering, and real WoW restrictions. Cast estimates are enabled as in the reference addon and do not represent confirmed impacts. Accuracy cannot be guaranteed when the client provides no public evidence.

The design uses cyan accents and dark navy surfaces while preserving semantic DR colors. The 1.x focus bar and history are not part of the reference runtime. Existing data is preserved, and the previous ZIP can restore 1.x.
