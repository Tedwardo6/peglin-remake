# Instructions for agents working on this game

Read this whole file before doing anything. It applies to Claude Code, Codex, Fable, ChatGPT, and any other assistant.

## Who you're working for

The owner, Theodore, directs this project but is **new to Git and Rojo**. That changes how you work:

- **You run Git, not him.** Branch, commit, push, and open pull requests yourself when you have Git access. Don't hand him Git chores you can do.
- **When he must do something on his Mac, give exact steps.** One step at a time, the exact command, which folder to run it in, and what he should see when it works. Never say "just sync it" or "pull the changes" without the actual commands.
- **Explain in plain words.** Say what you changed and what he'll see in Studio, not Git internals.
- **Never claim something worked unless you saw evidence** (command output, Studio console, a screenshot, or his confirmation). Say "please check X" instead.

## How this setup works

```
 src/ files (this repo)  --rojo serve-->  Rojo plugin in Studio  -->  scripts in the open place
```

1. All game **code** lives as files in `src/` in this GitHub repo.
2. On Theodore's Mac, the repo is cloned at `~/Documents/SeawindStudios/peglin-remake` (Mason's path may differ).
3. When `rojo serve` is running in that folder **and** the Rojo plugin in Studio is connected, any file saved in `src/` appears in Studio within about a second.
4. Rojo syncs **whatever is in that folder right now**: the currently checked-out branch, including unsaved-to-Git edits. GitHub itself is not connected to Studio.

| Files in the repo | Appear in Studio as |
|---|---|
| `src/server/` | `ServerScriptService.Server` |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared/` | `ReplicatedStorage.Shared` |

File names decide script type: `Name.server.luau` → Script, `Name.client.luau` → LocalScript, `Name.luau` → ModuleScript. A folder with `init.luau` (or `init.server.luau` / `init.client.luau`) becomes that script with children.

**Rojo only manages those three folders.** Workspace, models, maps, lighting, sounds, and UI built in Studio belong to the Studio place (Team Create) and are never in Git. Rojo leaves them alone.

## Rules for code changes

- **Edit files in `src/`. Never edit or create scripts inside the three synced folders in Studio** (by hand or with a Studio tool). Rojo will overwrite or delete them.
- Need a script somewhere else (e.g. `ReplicatedFirst`, `StarterGui`)? Add a folder in `src/` and map it in `default.project.json` with `$ignoreUnknownInstances: true` on the parent service. Tell Theodore that Rojo must be restarted (Ctrl+C, then `rojo serve`).
- Don't edit Studio-authored content (maps, models, lighting, UI) unless Theodore asks and you are the recorded writer for the place in STATUS.md.
- **The server decides consequences:** damage, rewards, run state, saves. Clients send inputs and results for the server to validate. Ball physics runs on each player's client; the server checks the results.
- Use `--!strict` Luau. Keep modules small and focused. No large frameworks unless the design plan calls for one.
- Test multiplayer systems with at least two clients (Studio: **Test → Clients and Servers**, 2 players).

## How your changes reach Studio

This is the part Theodore most needs walked through. Pick the case that matches you:

**A. You are running on Theodore's Mac, in his `peglin-remake` folder.**
Your file edits sync to Studio immediately while `rojo serve` is running. Ask him to confirm `rojo serve` is running and the plugin says Connected, then press Play.

**B. You are running elsewhere (cloud session, another checkout, Mason's machine) and pushed a branch.**
His folder does not have your changes yet. Give him these exact steps:

```sh
cd ~/Documents/SeawindStudios/peglin-remake
git fetch
git checkout <your-branch-name>
```

With `rojo serve` running, Studio updates as soon as the checkout finishes. To return to the main version later: `git checkout main`, then `git pull`.

After a pull request is merged into `main`:

```sh
cd ~/Documents/SeawindStudios/peglin-remake
git checkout main
git pull
```

If Studio still looks unchanged: check the Rojo plugin says Connected, and that the Terminal running `rojo serve` shows no errors.

## Git workflow

- Start each task on a new branch from current `main` (e.g. `feature/pegboard-physics`). Commit only your task's files.
- Fetch before you start and again before you push. No force pushes, hard resets, or wholesale ours/theirs merges. Never discard someone else's work to clear a conflict; ask.
- Push your branch and open a pull request. Describe what changed and **how Theodore can test it in Studio**. He approves merges into `main`.
- Never commit place files (`.rbxl`, `.rbxlx`), secrets, or API keys.

## Studio tools (Roblox Studio MCP)

If you have Roblox Studio tools, use them to **inspect**: read the Explorer tree, read Output/console logs, start and stop play tests, take screenshots. Do not use them to write scripts in the synced folders; change the files instead. Before editing anything else in the place, confirm you are the recorded writer in STATUS.md.

## Before you start and when you finish

1. **Start:** read the current [Seawind handbook](https://github.com/Tedwardo6/seawind-handbook) main (WORKSPACES.md plus relevant chapters, usually 12-engineering, 14-quality, 17-collaboration) and record its commit. Read STATUS.md and the design plan (in [seawind-ideas](https://github.com/Tedwardo6/seawind-ideas) until it moves into `docs/`).
2. **One writer per Studio place** across both people and all agents. Record it in STATUS.md before editing the place.
3. **Finish:** update STATUS.md's handoff (branch and commit, sync state, what changed, tests and evidence, open issues, next step). Then tell Theodore in plain words what to do next, using the steps above.

## Troubleshooting to offer Theodore

| Symptom | Fix |
|---|---|
| `rokit` or `rojo`: command not found | Quit Terminal fully (Cmd+Q), reopen, `cd` back into the repo folder |
| `rojo serve` says the address/port is in use | Another `rojo serve` is already running. Close that Terminal window or press Ctrl+C in it |
| Studio doesn't show file changes | Rojo plugin not connected, `rojo serve` not running, or he's on a different branch (`git branch` shows the current one with `*`) |
| Scripts he made in Studio disappeared | They were inside a synced folder. Recreate them as files in `src/` |
| `git checkout` refuses because of local changes | Don't tell him to discard anything. Ask what the changes are, then commit them to a branch or decide together |
