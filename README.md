# Ragdoll Sandbox v3.0

The updated Roblox place is **[RagdollSandbox_v3_0.rbxlx](RagdollSandbox_v3_0.rbxlx)** in this repository's root. Open it with **File → Open from File** in Roblox Studio.

## Files

- `RagdollSandbox_v3_0.rbxlx`: complete game, including the existing world and updated scripts.
- `src/`: all 154 script sources, organized by their Roblox instance paths. The place already contains these scripts; no manual import is needed.
- [Aenderungen_und_Steuerung.md](Aenderungen_und_Steuerung.md): full changes, controls and Studio test checklist.
- `tests/`: regression harnesses for the official Luau CLI.
- `manifest.json`: source paths and hashes.
- `Pruefbericht.json`: export validation report.

## Main controls

- **O**: quickhack targeting mode; **mouse wheel** selects; **F** executes.
- **K**: chip inventory. **I**: existing admin time stop.
- **M → GIFTS → player → FREECAM**: grant or revoke freecam. Recipient uses **U**.
- **JOBS**: paid contracts.
- **SUMMON / DISMISS**: Stillwater after its quest.
- **M → ADMIN → MY PSYCHOSIS IMMUNITY: OFF**: experience cyberpsychosis as an admin.
- Codes: `netrunner` gives $200 and one skin; `chips` gives $1–500 and one or two skins.

## Validation

All 154 exported scripts compile with Luau. The mocked-service regression harnesses pass 49 gameplay/storage assertions and 13 freecam/permission assertions. XML structure, references, original instance properties and source hashes were checked.

Roblox Studio multiplayer, physics and visual testing has **not** been run. Use the checklist in the change notes before publishing. No game was published and no live progress was wiped.

```sh
luau tests/gameplay_tests.luau
luau tests/freecam_tests.luau
```

The gameplay harness prints cumulative totals (20, 41, 49); these are not separate assertion counts. Editing a file in `src/` does not automatically update the `.rbxlx`.
