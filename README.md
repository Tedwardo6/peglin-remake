# Peglin Remake (working title)

Seawind Interactive's multiplayer pachinko roguelike for Roblox. This is a private game repository. Studio standards live in the [Seawind handbook](https://github.com/Tedwardo6/seawind-handbook). Design planning lives in [seawind-ideas](https://github.com/Tedwardo6/seawind-ideas).

> The working title is temporary. The shipped game will have its own name, art, characters, orbs, and relics, not Peglin's.

## Code and Studio boundary

| What | Owned by | How it moves |
|---|---|---|
| Scripts in `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client` | Files in `src/` (this repo) | Rojo syncs files → Studio |
| Everything else: Workspace, models, maps, lighting, UI made in Studio, sounds | The Studio place / Team Create | Saved in Studio, never in Git |

- Rojo only touches the three folders above. Everything else in each service is left alone (`$ignoreUnknownInstances`).
- **Never edit or add scripts inside those three folders in Studio.** Rojo overwrites or removes them on the next sync. Edit the files in `src/` instead.
- If you need a script outside these folders, add it to `src/` and map it in `default.project.json`.
- Sync direction is files → Studio only. Selected October 27, 2026 by Theodore (code in files; models, maps, and lighting stay in Studio). Native Script Sync was the handbook's default alternative; Rojo was chosen for this filesystem-first code layout.

## First-time setup (macOS)

1. **Install Rokit** (the tool manager), then restart Terminal:
   ```sh
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```
2. **Install the pinned tools** from the repo folder:
   ```sh
   rokit install
   rojo --version   # should print Rojo 7.7.1
   ```
3. **Install the Rojo Studio plugin** (close Studio first):
   ```sh
   rojo plugin install
   ```
4. **Start syncing:** open the game's place in Studio, then run:
   ```sh
   rojo serve
   ```
   In Studio, open the Rojo plugin and click **Connect**.
5. **Check it worked:** press Play. The Output should show `server started (Rojo sync OK)` and `client started (Rojo sync OK)`.

## Layout

```
src/
  server/   ServerScriptService.Server   (Script / ModuleScripts; server authority)
  client/   StarterPlayerScripts.Client  (LocalScript / ModuleScripts; input + presentation)
  shared/   ReplicatedStorage.Shared     (ModuleScripts used by both)
docs/       Game-specific notes and decisions
```

File naming: `Name.server.luau` = Script, `Name.client.luau` = LocalScript, `Name.luau` = ModuleScript.

## Working rules

See [AGENTS.md](AGENTS.md) and [STATUS.md](STATUS.md).
