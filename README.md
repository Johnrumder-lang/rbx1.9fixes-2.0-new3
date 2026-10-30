# Ragdoll Sandbox v3.2.1

Open **[RagdollSandbox_v3_2_1.rbxlx](RagdollSandbox_v3_2_1.rbxlx)** with **File → Open from File** in Roblox Studio. This is the complete updated game. The previous version remains in Git history.

The startup now supports an unpublished Studio place using session-only progress. Published servers continue using persistent saves. Actual Roblox Studio multiplayer/visual testing is still required before publishing.

## New in v3.2.1

- **Mobile chip inventory:** tap the **CHIPS** button above the left thumbstick. Its position can be customized with the existing touch-button editor.
- Separate **CHIPS** and **SLOTS** pages with scrolling, six equipped slots, and large touch buttons. The panel fits portrait/landscape phones and tablets inside the screen's safe area.
- **STORE HELD CHIP** puts a chip from either hand into your bag. **SLOT** installs it, **EJECT** removes it, and **TAKE** returns it to your hand and closes the inventory. Scanner/Zoom keep separate toggles; video chips have **PLAY**.
- The mobile inventory uses the existing server checks and respects forced-control/menu locks. Desktop **K** and **F** controls remain available.

## New in v3.2

- **M → CLANS**: create a filtered-name clan for **$2,500**, invite players in your server, accept/decline invitations, leave, remove members or disband as leader. Membership is saved; the clan name appears above the existing name/title. Up to 50 members; invitations expire after 5 minutes.
- **M → DAILY**: automatic reward popup, one claim per UTC day. **Day 3 = 1 skin; day 7 = 3 skins**. Other days give **$25–1,000** with a **0.5%** chance of a tier 1 implant case. Cases remain saved until collected. Consecutive seven-day cycle; a missed day restarts day 1.
- **Six equipped chip slots**. F stores every held chip type, including raw spawn-menu blank chips. Scanner and Zoom Optics have separate **ON/OFF** and **EJECT** buttons.
- Quickhacks, including Blackwall uploads, activate after **5 seconds**. Ejecting the chip, respawning, losing range/line of sight or disabled chips cancels the upload. Virus incubation remains **15 seconds**.
- **Ripperdoc → UNINSTALL CYBERWARE** lists installed implants with removal prices. Add a removal, sign the list and lie on the operating table.
- `fixes` grants **$200 + 1 unowned weapon skin** once. `2.0` and `update2` are retired; already-owned rewards remain. `netrunner` and `chips` stay available.
- Target-virus/rampage movement uses server-computed paths, waypoints, jumps and blocked/stuck-route recalculation. It only fires with a clear line of sight.
- Replay ground skips uncloneable **Terrain**. Video playback now cleans up on skip, timeout, replacement and scene errors, with separate IDs for repeated playback.
- Cyberpsychosis uses the visible overload meter. Exactly **23/23 capacity** is safe; Sandevistan no longer produces hidden psychosis independently of capacity. Admin immunity and explicit virus/quickhack attacks retain their separate rules.

Clan/reward writes require a public server with saving available. Unpublished Studio supports session-only testing. The M menu uses two readable tab rows.

## Existing controls and features

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

`src/` contains all **165** scripts in their Roblox instance paths. The place already embeds them; no manual import is needed. `manifest.json` records their hashes, and `Pruefbericht.json` records the export checks.

The current export passes Luau compilation and **440 assertions** against current sources with mocked Roblox services. This includes mobile inventory actions, page switching, full-slot handling and layout dimensions across phone/tablet sizes, plus clans, daily transactions, chip storage/ejection and upload delay, uninstall quotes, navigation, replay cleanup, psychosis capacity boundaries, and earlier gameplay/admin regressions. It does not replace Roblox Studio physics, touch input, UI rendering, DataStore and multiplayer tests.

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
