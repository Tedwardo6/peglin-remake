# Asset provenance

Every asset the game uses at runtime, where it came from, and whether we may reuse it. The board, altar, scenery, lobby hall, UI and effects are built from code at runtime (parts, tweens, GUI objects). The monsters are the only generated 3D art.

## Monster models (generated meshes)

Generated in Roblox Studio with Roblox's built-in mesh generation (Studio MCP `generate_mesh`, explicit segmentation into limb parts) on October 27, 2026, in Theodore's Studio session. Studio published each generated mesh and texture as an asset under Theodore's account. They are original generations from our text prompts, not copies of anyone's model. **Reuse status:** ours to use in this game. Check Roblox's current terms for AI-generated assets before any commercial use outside Roblox.

| Model key | Used by | Parts (joints are computed from these) |
|---|---|---|
| `imp` | Mire Imp | body, head, left/right arm, left/right leg |
| `brute` | Gloom Brute | body, head, left/right arm, left/right leg |
| `hound` | Twinfang Hound | body, left/right head, front legs, back legs, tail |
| `hex` | Hex Weaver | robe, hood, left/right arm, staff (held) |
| `fungal` | Spore Colossus | body, head, left/right arm, left/right leg (regenerated with one consistent palette; the first version mixed colours between parts) |
| `golem` | Carapace Golem | body, head, left/right arm, left/right leg |
| `wraith` | Thorn Wraith | cloak, helm, left/right arm, lance (held) |
| `throne` | The Drowned King (Act I boss) | body, head, left/right arm, goblet (held), throne (fixed base) |
| `eyetree` | The Eye Warden (Act II boss) | trunk, crown, left/right arm, roots |
| `overseer` | The Vortex Eye (Act III boss) | eye body, crown, left/right/lower tentacles |
| `king` | not used right now (standing skeleton king, kept for later) | torso, head, left/right arm, left/right leg |

The mesh and texture ids, part sizes and placements are in `src/shared/Content/MonsterModels.luau`. The server rebuilds them at start (`src/server/World/MonsterAssets.luau`, `AssetService:CreateMeshPartAsync`) into `ReplicatedStorage.MonsterModels`, so the models travel with the code and nothing has to be saved in the place file.

### Regenerating or adding a monster

1. In Studio (Edit mode), generate the mesh with explicit parts. Name limbs `left …` / `right …` (arms, legs, heads, tentacles) and held items `staff`, `lance` or `goblet`; a seat is `throne`. Those names decide how each piece animates (`roleOf` in `src/client/World/Monster.luau`).
2. Put the generated model in `workspace.MonsterStage`.
3. Run the capture snippet (below) in the Edit data model. It finds the facing from the left/right pair, puts the origin at the centre of the feet, and prints the `MonsterModels` entry.
4. Paste the entry into `Content/MonsterModels.luau` and point the enemy's `look.model` at it (`Content/Enemies.luau`).
5. Check it in the Monster Gallery (lobby → DEV → MONSTER GALLERY): reveal, idle, wind-up, slam, small hits, big strike, armor, death.

```lua
-- Capture snippet (Edit data model). Set KEY and MATCH for the new model.
local KEY, MATCH = "hound", "spectral wolf"
local PAIRS = { { "left arm", "right arm" }, { "left head", "right head" }, { "left tentacles", "right tentacles" } }
local function fmt(n) return string.format("%.3f", n) end
for _, m in workspace.MonsterStage:GetChildren() do
	if m:IsA("Model") and string.find(string.lower(m.Name), MATCH, 1, true) then
		local parts = {}
		for _, d in m:GetDescendants() do
			if d:IsA("MeshPart") then parts[d.Parent.Name] = d end
		end
		local facing
		for _, pr in PAIRS do
			local l, r = parts[pr[1]], parts[pr[2]]
			if l and r then
				local rv = (r.Position - l.Position) * Vector3.new(1, 0, 1)
				if rv.Magnitude > 0.1 then facing = Vector3.yAxis:Cross(rv.Unit) end
				break
			end
		end
		facing = facing or Vector3.new(0, 0, -1)
		local cf, size = m:GetBoundingBox()
		local minY = math.huge
		for _, p in parts do minY = math.min(minY, p.Position.Y - p.Size.Y / 2) end
		local feet = Vector3.new(cf.Position.X, minY, cf.Position.Z)
		local origin = CFrame.lookAt(feet, feet + facing)
		local lines = { `\t{KEY} = \{`, `\t\theight = {fmt(size.Y)},`, "\t\tparts = {" }
		local names = {}
		for n in parts do table.insert(names, n) end
		table.sort(names)
		for _, n in names do
			local p = parts[n]
			local c = { origin:ToObjectSpace(p.CFrame):GetComponents() }
			for i, v in c do c[i] = fmt(v) end
			table.insert(lines, `\t\t\t\{ name = "{n}", mesh = "{p.MeshId}", tex = "{p.TextureID}", size = \{ {fmt(p.Size.X)}, {fmt(p.Size.Y)}, {fmt(p.Size.Z)} \}, cf = \{ {table.concat(c, ", ")} \} \},`)
		end
		table.insert(lines, "\t\t},\n\t},")
		return table.concat(lines, "\n")
	end
end
```

### How monsters animate

Each piece rotates about a joint: the middle of where its box overlaps the core's box (the seam the generator already hides), with arms hinged near the top of that overlap. Rotating about these joints keeps limbs attached in every pose. Held items ride the gripping hand but stay mostly upright, then thrust forward on the slam. Floaters rise on the wind-up and dive on the slam; tentacles flare out. Seated monsters lean less so they stay on the throne. All motion is eased (no snapping), and reduced motion turns off idle sway.

## Heroes

Each player's hero is their own Roblox avatar, built on the server with `Players:CreateHumanoidModelFromDescription` and animated with the avatar's own animation set (idle, tool slash/lunge, point, cheer, wave). Class gear (cape, hood, Warden helm and pauldrons, Mystic hat and staff, daggers, shield) is built from parts in `src/client/World/Hero.luau`. Avatar items belong to their creators and are shown the way Roblox shows any avatar.

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

Load status (Studio Play session, October 27, 2026): every file above loaded. Any cue that fails to load stays silent and never blocks input.

**Music:** none selected. A licensed or Roblox-provided track still needs choosing and listening approval.

**Listening approval:** not done. Mix levels are first-pass values; Theodore should listen on phone speakers and headphones (handbook ch. 11).

## Textures

| Asset | Use |
|---|---|
| `rbxasset://textures/particles/sparkles_main.dds` | Peg sparks, monster aura motes, boss bling glints, hero cape sparkle, victory confetti |
| `rbxasset://textures/particles/smoke_main.dds` | Drifting smoke over the battlefield |

Both are Roblox-provided default textures.

## Fonts

GrenzeGotisch (titles) and Merriweather (body text), both Roblox-provided font families.

## Not used

No Peglin names, characters, art, orb or relic names, or text. No icon-pack images (the Seawind icon packs' rights are unresolved; see the icon catalog). No Creator Store uploads by third parties. The reference images Theodore shared (dark fantasy + psychedelic, @OZAVRY-style and others) were mood references only; nothing was traced or copied from them.
