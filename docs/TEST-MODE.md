# Developer test mode (plan §12 learning question)

**Question:** does deliberately preparing a teammate's next shot improve the same fight over solo and independent-damage co-op?

Test mode runs one identical encounter in three conditions. Only the relay recipient changes between the duo conditions.

| Condition | Players | Relay Charge goes to | Monster HP |
|---|---|---|---|
| `solo` | 1 | the shooter | 400 (solo) |
| `duo_self` | 2 | the shooter (control: same bonus, no teammate effect) | 700 (duo scaling, ×1.75) |
| `duo_teammate` | 2 | the other player | 700 (duo scaling, ×1.75) |

Fixed in every condition: board `lanes` (relay lane vs power lane, split by a divider), Brute Monster's 8-damage slam every 18 s (first at 18 s), Ricochet kit, one identical upgrade (Whetstone), same timing, fixed seed. The solo/duo HP difference is the plan's scaling rule and is intentional.

## How to run it

1. In Studio: **Test → Clients and Servers**, 2 players (or Play for solo).
2. On a client, the workshop menu shows **DEVELOPER TEST MODE** (Studio, or the experience owner in a live server). Press SOLO, DUO · SELF, or DUO · TEAM. Duo conditions pull in the other connected player.
3. Play the fight. When it ends, the result card shows the condition, outcome, duration, and each player's damage and charges, with **RUN AGAIN** (free rematch) and **WORKSHOP**.

## What gets logged

- Server Output: `[testlog] condition=… won=… duration=…s bonusDamage=… players=…` after every test fight.
- Analytics custom events `test_bonus_damage` and `test_duration` per player, under a fresh session/condition ID with condition field `test_<condition>`.
- The workshop menu's test panel shows the last three results.

## Running the tester protocol later

Follow plan §12: eight unfamiliar testers in four pairs (at least four on phones, two unfamiliar with Peglin), counterbalanced condition order, up to five minutes per condition, offer the free rematch, then ask each tester to explain a teammate-caused moment. Record realized bonus damage and duration from the log, not just preference.
