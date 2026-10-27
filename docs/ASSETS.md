# Asset provenance

Every asset the game uses at runtime. The scene, monster, cabinet, board, and all UI are built from code at runtime (parts, tweens, GUI objects); there are no uploaded meshes, images, or models.

## Audio

All sounds are Roblox-provided client sounds (`rbxasset://sounds/...`). They ship inside every Roblox client, need no upload, and carry no third-party licence. They are played through modular audio objects (`AudioPlayer → AudioFader → AudioDeviceOutput`). Cue names, mix levels, and voice limits are in `src/client/Juice/AudioCatalog.luau`.

| File | Used for (cues) |
|---|---|
| `rbxasset://sounds/electronicpingshort.wav` | peg hits (pitch rises across a combo), guard/relay/power/mend peg voices, charge arrival, reward, victory |
| `rbxasset://sounds/clickfast.wav` | UI click and hover, wall bounce, aim tick, countdown, reject |
| `rbxasset://sounds/Rocket shot.wav` | launch, burst peg, big hit |
| `rbxasset://sounds/action_jump.mp3` | spring peg |
| `rbxasset://sounds/Rocket whoosh 01.wav` | ball drain, panel open, title cards, charge send, charge use |
| `rbxasset://sounds/collide.wav` | monster flinch |
| `rbxasset://sounds/HalloweenThunder.wav` | threat telegraph, threat landing |
| `rbxasset://sounds/unsheath.wav` | shield block, armor up |
| `rbxasset://sounds/glassbreak.wav` | monster death |
| `rbxasset://sounds/HalloweenGhost.wav` | defeat |

Load status (Studio Play session, October 27, 2026): every file above loaded. `rbxasset://sounds/swoosh.wav` was tried first and refused by Studio ("Asset is not approved for the requester"), so its four cues were moved to `Rocket whoosh 01.wav`; no load errors appeared after that change. Any cue that fails to load stays silent and never blocks input.

**Music:** none selected. A licensed or Roblox-provided track still needs choosing and listening approval.

**Listening approval:** not done. Mix levels are first-pass values; Theodore should listen on phone speakers and headphones (handbook ch. 11).

## Textures

| Asset | Use |
|---|---|
| `rbxasset://textures/particles/sparkles_main.dds` | Peg sparks and victory confetti (Roblox-provided default sparkle texture) |

## Fonts

FredokaOne (`rbxasset://fonts/families/FredokaOne.json`), a Roblox-provided font family.

## Not used

No Peglin names, characters, art, orb or relic names, or text. No icon-pack images (the Seawind icon packs' rights are unresolved; see the icon catalog). No Creator Store uploads by third parties.
