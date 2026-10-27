# Status

## Current state

- **Stage:** Full playable loop built on branch `feature/full-loop` (draft PR #1). Not merged, not published.
- **Setup:** Rokit and Rojo 7.7.1 on Theodore's Mac; repo at `~/Documents/SeawindStudios/peglin-remake`. Rojo sync of `main` confirmed on October 27, 2026 (Play printed both "Rojo sync OK" lines).
- **Design authority:** `ideas/co-op-pegboard-adventure/research/2026-10-27-merged-multiplayer-proposal.md` in seawind-ideas at `54167c6`. The build prompt deliberately extended its "Prototype 1 only" scope to the whole loop.
- **Next objective:** Theodore checks out the branch and plays it in Studio, then runs a 2-player test (steps below).

## Places and destinations

| Place | Purpose | Roblox place ID | Owner (writer) |
|---|---|---|---|
| Baseplate prototype (name unconfirmed) | Prototype | `123038652032080` (place ID reported by Theodore from Studio, Oct 27, 2026; universe ID not yet recorded) | Theodore |

Record real IDs only after verifying them in Studio or Creator Hub.

## Active work

| Who | Assistant | Task | Branch | Started |
|---|---|---|---|---|
| Theodore | Claude (cloud session) | Full playable loop | `feature/full-loop` | Oct 27, 2026 |

## Last handoff (October 27, 2026)

**Repo, branch, commit:** `Tedwardo6/peglin-remake`, `feature/full-loop`, latest commit is the one that adds this handoff (code at `0887e93`). Branched from `main` at `a0ee5f2`; `main` had not moved when last fetched. Handbook read at `ca39f94` (still current on Oct 27). Design plan read at seawind-ideas `54167c6`.

**Sync state:** Theodore's folder is still on `main`, so Studio does not have this code yet. For the Studio checks below, the agent copied the branch's scripts into **Play sessions only**. Those copies vanish when Play stops. After stopping, the place's edit view held only `ServerScriptService.Server` and `ReplicatedStorage.Shared` from `main`. Nothing was saved to place `123038652032080`.

### What changed

- **Shot:** fixed launch strength; separate aim (drag / A-D / arrows) and launch (button / Space); a guide to the first collision; 8 s flight cap; one ball in flight per player.
- **Authority:** a custom deterministic 2D solver in `src/shared/Sim`. The server resolves every accepted launch and schedules its hits. The client predicts the same shot and compares fingerprints. The Server Authority assessment is in `docs/ARCHITECTURE.md`.
- **Run:** 3 legs × (2 fights + boss). Threats come every 16–20 s with 12 s or more of warning. Drafts have a 20 s deadline and a free fallback (repair). Relay Charge rules include return-to-sender when the target is full or has left. HP scales by 1 + 0.75 × (active − 1).
- **Joining and leaving:**
  - People join only at drafts. While waiting they get a practice board, an honest wait estimate, a solo option, and a catch-up kit.
  - A departing player's seat is held for 60 s.
  - Idle players get a warning at 45 s and become observers 15 s later.
  - HP percentage is preserved through joins and departures.
- **Party size:** the workshop handles parties. Servers hold 8 players. Parties are capped at **2** (`Config.Party.MAX_PARTY`). Four-player play is built but reachable only in developer test mode until the phone checks pass. The join list shows the cap (for example "1/2", then FULL).
- **Content:**
  - 12 balls plus the always-available Basic ball.
  - 18 components and 6 special pegs plus ordinary pegs.
  - 3 kits and 6 boards, plus the `lanes` test board.
  - 6 ordinary behaviours and 3 bosses. The intro brute is the brute's tutorial tuning.
  - 4 modifiers and 3 earned trail sets, plus the default trail.
- **Retention:** options and appearance only (modifiers, trails, milestones). No monetization of any kind.
- **Funnels:** event map v1 implemented exactly as the plan defines it (`docs/ANALYTICS.md`).
- **Persistence:** profiles save to the isolated scope `isolated-test-v1`. A session lock is used. Loads fail fast in Studio without API access, and play continues without saving.
- **Art and presentation:**
  - Code-built, chunky, outlined art (workshop, cabinet, board, monster), swappable per `docs/ARCHITECTURE.md`.
  - Cutscenes are 5 s or less and skippable after the first viewing.
  - Juice: rising-pitch peg SFX, scaled damage numbers, combos, hit-stop, shake, the charge send/use arc, and button hover/press sounds.
- **Audio:** Roblox-provided client sounds only. Provenance is in `docs/ASSETS.md`.
- **Developer test mode:** three conditions (solo, duo_self, duo_teammate) with logging, documented in `docs/TEST-MODE.md`.

### Tests and evidence

- **Headless (Lune):** 904 checks pass, covering solver determinism, encounter rules, run flow, persistence, protocol validation, and bot runs.
  - Bot pacing: solo sharp 8.0 min; solo casual 20.9 min with 4 losses; duo 8.9 min; four bots 8.6 min.
  - Test-mode fights: 29–32 s each.
- **Strict types:** `luau-lsp analyze` reports no errors across `src`.
- **Studio solo Play, seen on screen or in Output:**
  - Run start; client and server shot fingerprints match (no divergence logs).
  - Funnel steps 1–5 plus `rematch_offered`.
  - Threat telegraph and countdown.
  - Monster defeat leading to the draft screen with its timer and fallback.
  - The knocked-out screen with a free restart.
  - Idle warning and observer.
  - The fast-fail profile path.
  - Server game work p95 about 0.03 ms per frame with one player in a run.
- **Not yet done in Studio:**
  - 2-client and 4-client tests. The agent's Studio tool can only start single-player Play; the 2- and 4-player rules are covered by the headless bot runs.
  - Watching a full shot mid-flight at normal speed.
  - A phone or emulator readability pass.
  - Listening approval for the audio mix.

**Saved / tested / approved / published:** Saved to GitHub on the branch. Tested headlessly and in solo Studio Play. Not approved. Not published.

### Open issues

- **Phone checks gate 4-player parties.** Peg readability and load must be checked on a physical baseline phone before raising `MAX_PARTY` to 4.
- **Max Players 8** must be set by Theodore in Game Settings, because it is a place setting, not code.
- **Visual polish to review in Studio:**
  - The turret colour was lightened, but not yet re-checked.
  - The threat card sits close to the monster on narrow screens.
  - A "BLOCKED 5!" callout appeared once and was not reproduced.
- **Relay charges in 4-bot runs:** about half the charges came back to the sender because the default recipient already held one. Watch this in real 3–4 player tests.
- **Creator Hub analytics ingestion:** unverified. It needs an authorized restricted test publish.
- **The place's own content** logs two unrelated asset errors (`rbxassetid://203785492`, `911864050`). They are not from this code.

### Decisions left open on purpose

Theme and title (working title "Cabinet"), audience, monetization, daily/versus modes, the Rojo boundary, and the AGENTS.md wording.

**Proposed AGENTS.md correction (not applied):** replace "Ball physics runs on each player's client; the server checks the results." with "The server simulates every shot with the shared deterministic solver; each client predicts the same shot for instant feedback, and the server's result decides."

### Assumptions made

- A player knocked out during a fight the team still wins comes back at 50% hull for the next fight.
- The Basic ball sits outside the 12-ball ceiling, as the plan's "three selectable balls, with an always-available basic ball" reads.
- The custom solver was chosen over native Server Authority on reasoning. It was not a measured comparison.
- Workshop PointLights were removed because they washed the room out. The place's Lighting does the work, and it was left untouched.

### Next objective and owner

Theodore: check out the branch, play solo, then run **Test → Clients and Servers** with 2 players and report what feels off. Then he decides whether to merge.
