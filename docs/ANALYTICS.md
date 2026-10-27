# Event map v2

Implements plan §6 and the handbook's required onboarding and progression funnels (chapter 15). Code: `src/server/Analytics/Funnels.luau`; wiring: `src/server/Run/RunManager.luau`. `Config.EVENT_MAP_VERSION = 2`, `Config.BUILD_VERSION = 0.2.0`.

**What changed in v2 (RPG redesign):** players now land in the lobby hall and choose to begin, so `first_launch` timing includes lobby and path-map time; compare v1 and v2 numbers separately. `leg_N` and `boss_N` now mean **act** N and that act's boss. Event names and step numbers are otherwise unchanged.

## Scope and identity

- **Repeatable experiment funnel.** Every server join gets a unique session ID (GUID). Every developer test condition run gets a new session/condition ID too.
- Each milestone is recorded **once per ID**. Events are sent by the server, after the underlying action was validated.
- **Time origin:** server join. Every milestone also sends a custom event `t_<milestone>` whose value is seconds since join. `t_ready_to_first_launch` keeps readiness-to-action timing.
- **Fields** (Roblox allows three custom fields): `CustomField01 = b<build>|m<event map>`, `CustomField02 = device` (`touch`, `keyboard`, `gamepad`, `unknown`), `CustomField03 = <condition>|<prior exposure>` where condition is `normal` or `test_<condition>` and prior is `new` or `returning` (profile has started a run before).

## Funnels

| Funnel | Step | Event | Completion trigger (server) | Eligible denominator |
|---|---|---|---|---|
| Onboarding | 1 | `join` | Player added to the server | All entrants, including early exits |
| Onboarding | 2 | `ready_to_act` | Client reports scene and controls ready (acknowledgment, not proof of action) | Joined sessions |
| Onboarding | 3 | `first_launch` | Server accepts a valid launch | Joined; also report ready sessions |
| Onboarding | 4 | `first_useful_hit` | Server applies the first hit with any effect (damage, shield, repair, or charge) | Joined sessions |
| Onboarding | 5 | `first_reward` | Encounter won; result granted once | Joined sessions |
| Onboarding | 6 | `first_upgrade` | Server commits a draft pick (fallback does not count) | Sessions offered a draft |
| Onboarding | 7 | `independent_repeat` | First accepted launch after the first upgrade (no forced input exists) | Upgrade completers |
| Assist | 1 | `assist_opportunity` | Accepted launch while ≥ 2 active players and teammate relay is on | Eligible duo+ sessions |
| Assist | 2 | `assist_sent` | Charge delivered to a teammate | Opportunity sessions |
| Assist | 3 | `assist_used` | Recipient's launch consumed a teammate's charge | Recipients |
| Rematch | 1 | `rematch_offered` | Free restart, run-end, or test rematch shown | Sessions shown the offer |
| Rematch | 2 | `rematch_started` | Player restarts or rematches | Sessions offered |

Solo and duo-self-charge relay use is tracked separately as custom events `self_charge_sent` / `self_charge_used`, so the Assist funnel only counts teammate assists.

## Progression milestones (custom events, once per ID)

`boss_1`, `boss_2`, `boss_3`, `leg_1`, `leg_2`, `leg_3`, `run_complete`, `alt_kit_run` (a run started with a kit the profile has not used before, after at least one earlier kit), `modifier_run` (a run with any optional challenge).

## Other custom events

| Event | Value | Purpose |
|---|---|---|
| `test_bonus_damage` | Realized bonus damage from received charges | Developer test protocol (plan §12) |
| `test_duration` | Encounter duration, seconds | Developer test protocol |
| `sim_divergence` | Running count for the session | Client prediction differed from the server |

## Targets (hypotheses, from join, including loading)

Controls ready ≤ 10 s · useful shot ≤ 30 s · first reward ≤ 75 s · upgrade ≤ 90 s · independent repeat ≤ 120 s · understood assist ≤ 180 s in a duo. The first fight (100 HP Small Monster, first threat at 24 s) is sized so a new player usually wins in three or four shots.

## Verification status

- **Studio:** events print as `[funnel] …` lines in Output. Studio does not prove dashboard ingestion.
- **Creator Hub ingestion: not verified.** Needs an explicitly authorized restricted published test with isolated data, then View Events in Creator Hub (charts can take ~24 h). No publication was done or authorized in this task.
- Roblox backfills earlier funnel steps when a later one arrives; use the `t_<milestone>` custom events to audit which actions actually happened.
