# Instructions for people and assistants

1. **Refresh standards first.** Read the current [Seawind handbook](https://github.com/Tedwardo6/seawind-handbook) main: WORKSPACES.md and the chapters relevant to the task (usually 12-engineering, 14-quality, 17-collaboration). Record the handbook commit you used.
2. **Read STATUS.md** before editing. It records who owns the Studio place and what's in progress.
3. **Respect the sync boundary** in README.md. Code lives in `src/`; Rojo syncs files → Studio. Never edit synced scripts inside Studio. Never regenerate or overwrite Studio-authored content (maps, models, lighting, UI).
4. **One writer per Studio place** at a time, across both people and all agents. Record ownership in STATUS.md (and the shared task/PR) before editing the place.
5. **Branches and pull requests.** Start each task on a branch from current `main`. Commit only your task's files. No force pushes, hard resets, or wholesale ours/theirs merges. Fetch again before pushing.
6. **Server decides consequences.** Damage, rewards, run state, and saves are server-validated; clients send inputs and results to check, never trusted values.
7. **Test multiplayer with at least two clients** (Studio's server + clients mode) for any shared system.
8. **Keep game-specific facts here,** not in the handbook. Design planning stays in seawind-ideas until moved here.
9. **End every session with a handoff** in STATUS.md: branch and commit, place and sync state, changes, tests and visual evidence, open issues, next objective. Never claim tests, syncs, or publishes you didn't verify.
