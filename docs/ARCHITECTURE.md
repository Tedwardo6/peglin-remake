# Architecture (feature/rpg-redesign)

How the game is put together, where each rule lives, and how to change it safely. Design authority: `ideas/co-op-pegboard-adventure/research/2026-10-27-merged-multiplayer-proposal.md` in seawind-ideas (commit `54167c6`).

## Authority model

The server simulates every accepted launch; the client predicts its own shot with the same code.

1. The client sends `launch {seq, slot, aim, boardRev, predicted}`. Aim is one integer (see `Sim/Aim`), so both sides start from identical inputs.
2. The server validates the request (`Net/Protocol` shape and size, per-player rate limit, then `EncounterCore.launch`: membership, phase, board revision, monotonic sequence, ball available, cooldown, finite aim, one ball in flight, frequency).
3. The server freezes the loadout (ball, components, held Relay Charge, monster HP fraction), runs `Sim/Shot.resolve`, and schedules every hit at `launch time + step / 60`. Damage, shield and repair apply when earned, so a Guard hit before a threat's deadline counts even if the ball is still flying.
4. The client already started the same shot locally. When the server's `shot` message arrives it re-times its predicted hits and compares fingerprints. A mismatch is logged on the server (`[Cabinet] divergence …`) and as the `sim_divergence` analytics event; the server's numbers always win.
5. Teammates receive the shot inputs (`shot` message) and re-simulate it on their mini board. No per-peg network traffic.

Clients never send damage, hits, or results; `Protocol.validate` rejects any unknown field.

### Hero strikes (RPG redesign)

Each player has a hero on the battlefield (their own avatar). While a player's ball is in flight its damage is **banked** on their hero (the number above the hero's head). The server schedules a `strike` at `shot end + Config.Combat.STRIKE_DELAY` (0.55 s); that is when the damage lands on the monster and is recorded per player. The client plays the hero's lunge and a bolt timed to land at that moment, and the monster's HP bar only drops at impact. Guard (shield) and mend still apply when their peg is hit, so a guard hit before a threat's deadline counts even if the ball is still flying.

Contribution is shown three ways: the banked number over each hero, coloured segments in the monster's HP bar (one colour per seat), and the results screen (damage share, shield given, repairs, empowers, MVP).

## Run structure

1. **Lobby hall.** Players land here (`ready` no longer starts a run by itself). They pick a hero class, a campaign, and either begin solo or form a party (`Lobby/PartyCore`: leader, members, kits, ready flags, privacy). The leader starts when everyone is ready.
2. **Path map.** Each act is a deterministic map (`Sim/MapGen.generate(campaign, act, seed)`): an opener fight, a row of fight / elite / treasure, a row with a campfire and one other node, then the boss. The party votes on the next node; majority wins, the host breaks ties, and no votes takes the first choice. A solo player's forced step closes after `MAP_SINGLE_SECONDS`.
3. **Nodes.** Fight and elite (elite: `ELITE_HP_MULT`, `ELITE_DAMAGE_MULT`, then a component reward or `ELITE_SPOILS_MAX_HULL`), treasure (a component-only draft), campfire (heal `REST_HEAL_FRACTION` of max health, or train one ball), boss (a draft, then the next act).
4. Checkpoints store campaign, act and the current map node, so **Continue** resumes on the map.

Campaigns and acts are data (`Content/Campaigns.luau`): one campaign, "The Dreaming Abyss", with three acts (Drowned Crypt, Floating Isle, Vortex Spire), each with its own monster pool, boards, boss and palette.

## Determinism

`src/shared/Sim/Solver.luau` is a fixed-step (60 Hz × 4 substeps) circle/wall solver with bounded speed, quantized integer aim, no trigonometry, and a fixed collision order (grid cell order, then peg index). Boards carry a revision number; a shot records the revision it used.

Proof so far (headless, `tests/suites/sim.luau` and `encounter.luau`): identical inputs give identical fingerprints, and the server path and the client prediction path produce the same fingerprint. **Not yet proven:** bit-identical results between the Roblox server and a physical phone client. The divergence log above is how that gets measured in a published test.

Measured cost: about 1.9 ms to resolve a full 8-second shot (Lune interpreter, desktop CPU). This is a one-off cost per launch, not per frame.

### Server Authority assessment (plan §9)

Roblox's opt-in Server Authority (full release July 9, 2026) makes engine physics server-authoritative with client prediction. For this game the custom solver is the better fit, and is what is implemented:

- **Reproducible scoring.** The whole shot is known the moment it is accepted, so damage can be scheduled, predicted exactly, replayed in tests, and audited. Engine physics would give consequences only as frames run, with no replay guarantee.
- **Traffic.** Inputs only (a few bytes per shot) versus replicated ball transforms for up to four balls per board.
- **Geometry.** Static circles and segments in a plane need none of the engine's 3D contact features.

What the native option would still offer: no custom collision code to maintain. It was not prototyped here; that trade-off is recorded as an assumption, not a measured comparison.

## Module map

| Area | Path | Notes |
|---|---|---|
| Tuning | `src/shared/Config.luau` | Every number is a hypothesis (H) from the plan |
| Simulation | `src/shared/Sim/` | `Aim`, `Solver`, `Scoring`, `Shot`, `MapGen`, `Rng` |
| Content | `src/shared/Content/` | 7 peg types, 6 boards, 12 balls, 18 components, 3 hero classes, 10 monsters, 1 campaign (3 acts), monster model data, 4 modifiers, 4 trails |
| Wire contract | `src/shared/Net/Protocol.luau` | Request schemas and validation |
| Encounter rules | `src/server/Encounter/EncounterCore.luau` | Pure; threats, strikes, relay, scaling, roster, idle, per-player stats |
| Run rules | `src/server/Run/RunCore.luau`, `Draft.luau` | Pure; path map, votes, campfires, treasure, elites, drafts, joins, seats, restarts, test conditions |
| Lobby | `src/server/Lobby/PartyCore.luau` | Pure; parties (leader, kits, ready, campaign, privacy) |
| Server world | `src/server/World/` | `Heroes` (avatar models), `MonsterAssets` (rebuilds generated monster meshes) |
| Server glue | `src/server/Run/RunManager.luau` | Remotes, players, parties, profiles, analytics, clock |
| Persistence | `src/server/Persistence/` | Schema, migrations, session-locked store |
| Analytics | `src/server/Analytics/Funnels.luau` | Event map v2 |
| Client | `src/client/Game.luau` | Orchestration |
| Scene | `src/client/World/` | Lobby hall, rune altar (board cabinet), act scenery, battle ledge, heroes, generated monsters, monster gallery |
| Board view | `src/client/BoardView/` | Pegs, ball playback, aim guide |
| UI | `src/client/UI/` | Theme tokens, component kit, HUD, screens, lobby menu, path map, teammate previews |
| Feedback | `src/client/Juice/` | Audio (modular audio objects), effects |
| Cutscenes | `src/client/Cutscenes/Director.luau` | Camera and ≤ 5 s sequences |

## Art and models

`World/Cabinet`, `World/Monster`, `World/Hero`, `World/Scenery`, `World/LobbyHall` and `BoardView/Board` each build their visuals in one place and expose a small API (`setPalette`, `hit`, `attack`, `die`, `strike`, …). Monsters come from generated meshes recorded as data (see `docs/ASSETS.md`); nothing depends on models saved in the place file.

Screen layout: the board sits on the left; the battle ledge is raised (`Layout.BATTLE_Y`) so heroes and the monster stand at the board's mid-height, clear of the HUD along the bottom. The top band holds act progress, the monster's name and HP, the threat card and the teammate card.

## Tests

```sh
lune run tests/run.luau          # all suites
lune run tests/run.luau run      # run flow + bot pacing estimates
```

Bots are balance estimates, not player evidence. Latest pacing (solo): sharp bot 8.0 min, random-aim bot 20.9 min with 4 restarts; duo sharp 8.9 min.
