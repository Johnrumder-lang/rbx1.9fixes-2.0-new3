# Ragdoll Sandbox v3.1

Open **[RagdollSandbox_v3_1.rbxlx](RagdollSandbox_v3_1.rbxlx)** with **File → Open from File** in Roblox Studio. This is the complete updated game. The previous version remains in Git history.

The startup now supports an unpublished Studio place using session-only progress. Published servers continue using persistent saves. Actual Roblox Studio multiplayer/visual testing is still required before publishing.

## Controls and changes

- **F4** toggles quickhack targeting. Aim at a player, select with the mouse wheel, execute with **F**. **K** remains the chip inventory.
- **F with a held chip** stores it and opens the deck; **SLOT / EJECT / TAKE** move it between slots, inventory and hand. Video chips have a **PLAY** button. While grabbing another player, F inserts the chip; target viruses first open a target chooser for the person inserting it.
- Viruses activate after **15 seconds**. Programming a blank virus costs **$250**, including for admins. Target directives force weapon pickup, movement, aiming and firing until the selected target dies. In-game controls are locked during directives and rampages.
- **JOBS**: a player bounty pays **$150**, three player kills without dying pay **$200**, and physical package delivery between random locations pays **$30**. Failure/death/cancellation costs **3 minutes**; success has no cooldown. Failure state is saved.
- **T → Weapons → Stillwater + Sheath** summons both, gated by the completed quest.
- **M → ADMIN → MY PSYCHOSIS IMMUNITY** controls immunity without injecting psychosis. No implants means no cyberware overload stress.
- **M → PLAYERS → WIPE** resets one player's progress globally. The owner's **WIPE ALL PROGRESS** resets all accounts, including offline ones. Reset players get the head-explosion effect, then reconnect into fresh saves.
- **M → GIFT LOG** browses saved gifts and revokes them for offline recipients. Admins manage their own grants; the owner manages all saved grants, including legacy records. Updates propagate between servers.
- Ripperdoc terminal moved onto the existing counter; original **Sarpanch** font restored; recordings explicitly include the baseplate; dodge physically sidesteps into a clear lane; fully blocked bullets no longer generate flesh holes or exit blood.
- Freecam gifting from **M → GIFTS → FREECAM** and activation with **U** remain available. Codes `netrunner` and `chips` remain available.

See [Aenderungen_und_Steuerung.md](Aenderungen_und_Steuerung.md) for the German change notes and Studio checklist.

## Sources and validation

`src/` contains all **159** scripts in their Roblox instance paths. The place already embeds them; no manual import is needed. `manifest.json` records their hashes, and `Pruefbericht.json` records the export checks.

The current export passes Luau compilation and **150 assertions** against current sources with mocked Roblox services. This covers unpublished startup, reset namespaces, PvP rewards/cooldowns, physical package requirements, virus incubation, target directives, gift permissions, dodge movement and blocked-hit feedback, plus earlier regression cases. It does not replace Roblox Studio physics, UI, DataStore and multiplayer tests.

To regenerate the harnesses and sync changed sources into the place, install the official Luau CLI and run:

```sh
python tools/sync_place.py --luau-compile luau-compile --luau luau
```

Or run the current harnesses directly:

```sh
luau tests/gameplay_tests.luau
luau tests/freecam_tests.luau
```

`tests/cases/*.luau.in` are source-insertion templates, not standalone Roblox scripts. The harness output uses cumulative totals. Changes to `src/` reach the `.rbxlx` only after running the sync script.
