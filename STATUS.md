# Status

## Current state

- **Archived October 27, 2026.** The game now lives only in the Studio place `123038652032080`, edited directly in Studio without Rojo (Theodore's decision). This file is the final record of the Rojo era; new status goes in the seawind-ideas handoff (`ideas/co-op-pegboard-adventure/research/2026-10-27-game-state-handoff.md`).
- **Snapshot:** this repository's `main` holds the merged full loop (PR #1) and RPG redesign (PR #2). All 58 scripts matched the place exactly at the switch.
- **Not published.**

## Places and destinations

| Place | Purpose | Roblox place ID | Owner (writer) |
|---|---|---|---|
| Baseplate prototype (name unconfirmed) | Prototype | `123038652032080` (place ID reported by Theodore from Studio, Oct 27, 2026; universe ID not yet recorded) | Theodore |

Record real IDs only after verifying them in Studio or Creator Hub.

## Active work

| Who | Assistant | Task | Branch | Started |
|---|---|---|---|---|
| — | — | No active work (RPG redesign merged Oct 27, 2026) | — | — |

## Last handoff (October 27, 2026)

**Repo, branch, commit:** `Tedwardo6/peglin-remake`, `main` after merging PR #1 (`feature/full-loop`) and PR #2 (`feature/rpg-redesign`, last code commit `ae44d79`). `main` was at `a0ee5f2` before the merges.

**Sync state:** the agent switched Theodore's folder to `main` and pulled the merge. Rojo synced it into Studio.

**Studio place:** the agent's mesh generations left the generated monster sources in the place. At Theodore's request ("save everything") they were kept, moved out of the visible world into `ServerStorage.MonsterStage` (not needed at runtime: the game rebuilds monsters from `Content/MonsterModels`), and the place was saved.

### What changed

- **Peglin-style combat:** each player has a hero (their own Roblox avatar) on a raised battle ledge. Ball damage is banked over the hero's head while the ball flies, then the hero strikes and the monster's HP drops at impact. Contribution shows over each hero, as seat-coloured segments in the monster's HP bar, and on the results screen (share, shield, repairs, empowers, MVP).
- **Path map:** three acts per campaign, each opener → fight / elite / treasure → campfire or other → boss, with party voting.
- **Lobby hall:** form a party (max 2) or begin solo, pick hero class and campaign. One campaign: "The Dreaming Abyss".
- **Monsters:** ten generated 3D monsters (Roblox mesh generation), animated procedurally about joints so limbs stay attached in every pose: reveal, idle, wind-up, slam, flinch, armor, death. Held weapons stay upright and thrust on the slam; floaters rise and dive; tentacles flare; the seated Drowned King (Act I boss, on his throne with crown, chains and goblet) leans less and has gold-and-diamond glints. See `docs/ASSETS.md`.
- **Look:** dark fantasy + psychedelic scenery per act (crypt, floating isle, vortex spire), giant watching eyes, vortex sky, checkerboard ledge with key and rim lights.
- **UI (latest):** rebuilt the shared UI kit around Theodore's references: iron and ornate frames with violet gems, iron title plaques, spiked round portrait seals (your avatar headshot, the monster's live 3D bust), stone-housed glossy red health and blue shield bars, inset slots with rarity glow, red close buttons, warm near-black interiors, gold serif headings. Everything is built from Studio GUI objects (`UI/Ornament.luau`); no images to upload. (An earlier image-based attempt was dropped because Studio could not upload the images without a local server on Theodore's Mac.)
- **Docs:** `docs/ASSETS.md` (monster provenance, capture procedure, UI art), `docs/ARCHITECTURE.md` (strikes, run structure, layout), `docs/ANALYTICS.md` (event map v2).

### Tests and evidence

- **Headless (Lune):** 6122 checks pass. **Strict types:** `luau-lsp analyze` reports no errors across `src`.
- **Studio solo Play (screenshots taken by the agent):** lobby with Theodore's avatar; BEGIN SOLO → Act I map; Mire Imp fight with the banked number over the hero, strike and HP drop; relic draft after the win; the Drowned King boss fight; every monster posed in idle / wind-up / slam / flinch side by side with no detached limbs.
- **Not yet done:** a 2-client test, a phone readability pass, listening approval.

**Saved / tested / approved / published:** saved to GitHub on the branch; tested headlessly and in solo Studio Play; not approved; not published.

### Open issues

- **Phone checks gate 4-player parties** (`MAX_PARTY` stays 2).
- **Max Players 8** must be set by Theodore in Game Settings.
- **Creator Hub analytics ingestion:** unverified.
- **The place's own content** logs unrelated asset errors (`rbxassetid://203785492`, `911864050`), not from this code.

### Decisions left open on purpose

Theme and title (working title "Abyss Pegs"; monster and act names are placeholders), audience, monetization, daily/versus modes, the Rojo boundary, and the AGENTS.md wording.

**Proposed AGENTS.md correction (not applied):** replace "Ball physics runs on each player's client; the server checks the results." with "The server simulates every shot with the shared deterministic solver; each client predicts the same shot for instant feedback, and the server's result decides."

### Assumptions made

- The standing skeleton king model is kept but unused; the throne king now plays the Act I boss.
- A player knocked out during a fight the team still wins comes back at 50% health for the next fight.
- The custom solver was chosen over native Server Authority on reasoning, not a measured comparison.

### Next objective and owner

Theodore: play Act I solo and a 2-player test, and say what feels off. He decides whether to merge.
