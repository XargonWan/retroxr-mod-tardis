# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`xenu.tardis` ("TARDIS XR") is a **RetroXR mod** in GDScript (Godot 4.7). The finished mod adds a Sonic
Screwdriver (several Doctors' models), a TARDIS you summon with it, and console rooms reached through
the TARDIS's door. `TODO.md` (git-ignored, in Italian) is the full plan; **the screwdrivers, the TARDIS exterior and the 10th Doctor's console room are built**
(see `README.txt` for Built / Not built). Keep that list current.

Like `xenu.synth_rift` (the model to follow: `~/gits/retroxr-mod-synth/CLAUDE.md`), this repo is not a
Godot project. It is the folder `RetroXR/mods/xenu.tardis/` of a RetroXR checkout, and every
`res://mods/xenu.tardis/...` path assumes that. Here `~/gits/RetroXR-xargon/RetroXR/mods/xenu.tardis` is
a **symlink to this repo**. RetroXR's own docs: `~/gits/RetroXR-xargon/docs/modding.md`.

## Commands

Godot is `~/Godot/Godot_v4.7.2-stable_linux.x86_64` (written `godot` below); `RETROXR=~/gits/RetroXR-xargon`.

```sh
# Tests. A SCENE run, not --script: the screwdriver extends XRToolsPickable, which needs the autoloads.
godot --headless --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/screwdriver_tests.tscn
godot --headless --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/tardis_tests.tscn
godot --headless --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/console_tests.tscn
# Screenshots (needs a window; OUT=dir): the screwdriver off and lit
OUT=/tmp godot --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/render_probe.tscn          # screwdriver
OUT=/tmp godot --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/render_tardis_probe.tscn   # TARDIS
ID=1 OUT=/tmp godot --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/render_room_probe.tscn   # a console room (ID: its table id), + the ray to its door
OUT=/tmp godot --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/render_bedroom_probe.tscn    # the TARDIS landing in RetroXR's own bedroom, 8 frames a second
OUT=/tmp godot --path $RETROXR/RetroXR res://mods/xenu.tardis/tests/render_bedroom_variants.tscn # the ghost drawn four ways in that room
# Build + verify + DEPLOY to ~/retroxr/mods/xenu.tardis.zip
python3 tools/pack.py
# Convert an original model (Blender 4.2 is at ~/gits/RetroQUEST/blender-4.2.3-linux-x64/blender)
python3 tools/build_models.py 10 11     # rebuild those GLBs from src.local/ (all if none given); each
                                        # model's settings are the table in tools/build_models.py
blender -b -P tools/render_lineup.py -- /tmp/lineup.png 2 3 4 5 10 11 12 13   # look at them
```

- **THE EXPORTED GAME USED TO CARRY ITS OWN COPY OF THIS MOD, AND IT WON (fixed 2026-11-10).** The user plays
  `~/gits/RetroXR-xargon/build_out/RetroXR.x86_64`, a release export. The symlink `RetroXR/mods/xenu.tardis` -> this repo is in
  the project, and the "Linux" preset (`export_presets.cfg`, preset.3) did not exclude `mods/*` as Quest and Windows do, so the
  mod's files (compiled `.gdc`, `.remap`) were INSIDE the binary's PCK. RetroXR mounts a mod pack with `replace_files=false`
  unless the mod claims a shipped path (`ModManager._mount_and_register`), so the embedded files beat the zip in
  `~/retroxr/mods/` and only `mod.json` was read from it: the Mods page showed the new version, the behaviour was the old
  one, and the boot log said `loaded xenu.tardis X - 1 room` when the table had 2. Every "it looks different in my game"
  report from 2026-11-06 to 11-10 was this. The user agreed to the fix: `exclude_filter="mods/*"` on preset.3 and a
  re-export with `Godot_v4.7-stable_linux.x86_64 --headless --path RetroXR --export-release Linux .../build_out/RetroXR.x86_64`
  (run through `flatpak-spawn --host`; the old binary is kept as `RetroXR.x86_64.before-tardis-fix`). A smoke run of the new binary
  (`XDG_DATA_HOME=<tmp> ./RetroXR.x86_64 --headless --quit-after 2400`, with the real `mods.json` copied into `<tmp>/godot/
  app_userdata/RetroXR/`) prints `[mods] loaded xenu.tardis 0.7.3 - 2 rooms, 2 props`: do that after any new export. If a report
  ever looks like "old behaviour, new version" again, `grep -a -c "mods/xenu.tardis"` the binary first. Do not edit RetroXR's
  checkout otherwise; that one line was done with the user's explicit OK.
- **Which build the user ran**: the game prints `[xenu.tardis X.Y.Z] ...` when a TARDIS is in the room or lands, and
  `[mods] loaded xenu.tardis X.Y.Z` at boot, in `~/.local/share/godot/app_userdata/RetroXR/logs/`. Those logs are named by
  the NEXT start's time. (My own runs from the VS Code extension are Flatpak-sandboxed and write to
  `~/.var/app/com.visualstudio.code/data/godot/`, so they do NOT touch the game's logs; the game's `user://` is
  `~/.local/share/godot/app_userdata/RetroXR/`.) A mod already running needs a restart. A TARDIS kept in a room's slot comes back SOLID, with no animation, and
  while one is in the room a summon does nothing: send it away (screwdriver on it, 1.5 s) to see a landing.
- **The TARDIS reports on itself**: while it materialises it appends a line every 2 s to
  `~/.local/share/godot/app_userdata/RetroXR/mods/xenu.tardis/ghost_debug.log` (the game's `user://`): version, renderer,
  how many surfaces wear the ghost and still do, how many have the depth pass, the alpha of the blended copies, and any
  other mesh drawn. When the user says the landing looks different in the game from the probes, ask them to land one and
  read that file: it is the only way to see their machine. (The depth pass is a `StandardMaterial3D`, not a shader of
  our own, so nothing depends on the renderer compiling a string.)
- **Deploy after every change meant for testing**: run `python3 tools/pack.py`. The user tries the mod in
  RetroXR from `~/retroxr/mods/` (MODS tab, enable, *Apply now*; a mod already running needs a restart).
  Bump `version` in `mod.json` when it matters, so the Mods page shows which build is installed.
- The suite exits non-zero on a failure, on zero cases, **and on a case count other than
  `EXPECTED_CASES`**: a script error aborts the running function silently and the rest still prints
  `0 failed`. Update `EXPECTED_CASES` when adding cases.
- **This host cannot load RetroXR's native extensions** (glibc too old), so `ModApi`, `SpawnCatalog` and
  `ScenePersistence` do not compile here, and anything that calls them dies. Registration is therefore
  only checked as text; the real check is enabling the mod in the game. A `--script` run has no autoloads.
  Both produce a wall of unrelated `SCRIPT ERROR` lines; filter the output (`grep tardis-tests`).
- No linter or build step beyond `tools/pack.py`.

## Architecture

- `mod_main.gd` registers ONE screwdriver object, `xenu.tardis:sonic_screwdriver` (**permanent**: written into
  save slots), whose Doctors (`screwdriver_models.gd`, ids "2".."13") are its `variants`: the row is held to
  choose, the id reaches the object as `model_variant` metadata before it enters the room and RetroXR saves
  it (generic, in `ScenePersistence.serialize_node`). **This needs a RetroXR change** (SpawnCatalog.objects
  did not pass a mod object's `variants`): `tools/retroxr-mod-object-variants.patch`, written against
  RetroXR master and checked with `git apply --check`, NOT applied (the user decides; do not edit RetroXR's
  checkout). Without it a RetroXR shows the 10th alone, and ignores `variants` harmlessly. Model ids are
  saved too: never rename one.
- The screwdriver's usage text is NOT in the object's menu row (RetroXR reads only `label` from it): it is `mod.json`'s
  `description` (the Mods page) and `HeldHint` rows the script adds to itself (`_teach_verbs`: Shift + left click on a
  desktop, A / X or the trigger in a headset, and what it does aimed at something). The user keeps the list of what the mod
  API lacks in the issue https://github.com/XargonWan/RetroXR/issues/6 (`gh` is not installed here).
- `scripts/sonic_screwdriver.gd` is the pickable. It reads its model (GLB) and its sound (MP3) **from the
  mod's files at run time** (`GLTFDocument`, `AudioStreamMP3`), because a pack made by RetroXR's
  `pack_mod.gd` carries source files only and nothing imported. Do not `load()` a `.glb`/`.mp3` here:
  it works in the checkout and fails in the pack. The meshes are made direct children of the node,
  where `PickableHighlight` looks. Use is the pickable's own `action_pressed`/`action_released` (trigger;
  Shift + click on desktop) **and** the holding controller's `ax_button` polled in `_process`.
- It is also a remote: held on a device (anything in RetroXR's `remote_target` group, `RemoteTarget`) for
  `TARGET_HOLD` (1.5 s) with the button down, it presses the device's `power` cell once per press. The
  aim is the TV remote's (cone from the tip in VR, crosshair on desktop, layer 21 `PointerArea`s). The
  tests build a fake device (`tests/fake_remote_device.gd`).
- `scripts/tardis.gd` is the TARDIS (a cabinet-like pickable: hold-to-grab, never thrown, `GroundPlacement`,
  stands itself upright). It is a `RemoteTarget` with one `power` cell that sends it away, so the
  screwdriver held on it does that with no TARDIS-specific code in the screwdriver. Held on NOTHING, the
  screwdriver calls `TardisSummon.summon` (tests replace it with `summon_handler`). Where it lands is
  `TardisSummon.find_spot`: candidate spots best-first (ahead of the player), each judged by the physics
  world (a box overlaps nothing on `BLOCK_MASK`, floor under the base on layer 1, in sight). **It assumes
  rooms have a floor collider on layer 1**: if a room has none, nothing will ever land there.
  The door is a `VRButton` over the front; the leaf is the mesh the exterior's table names (origin on its
  hinge, turned about Y). Materialising is `Tardis.alpha_at` (pure), measured on a reference clip of the show: it forms in
  place and SWITCHES, almost fully on and almost fully off, once per pulse of landing.mp3 (period 2.0 s): the solid
  tops reach full by 30% of the way, the offs stay low (cubic) and shorten until the two meet, solid for good at 92%.
  Wrong first versions: a faint ghost that only filled in, a swing that was too gentle. **See-through must keep the
  TARDIS SOLID** (the user: invisible but solid, never the inside or the far wall through the near one):
  `_dress_ghosts` puts on every surface a depth-only pass (`_DEPTH_CODE`, render_priority -1, `next_pass` = the blended
  copy) and a `duplicate()` of the surface's OWN material in alpha (so nothing pops when the originals go back at the
  end). The depth pass leaves only the nearest surface able to draw. Without it (`tests/render_ghost_probe`, last shot) it
  is a glass box with doubled windows and the back sign showing, which is what the user saw. Also tried and dropped:
  Forward+'s `GeometryInstance3D.transparency` (the glass box; ignored by the Quest) and a `discard` dither (clean in a
  probe, measured to the pixel, yet the user saw the glass box in the game: cause never found; the probe cannot see it).
  Not seen in a headset. The last 20% of the curve (`TAIL_FROM`) converges on solid so the final transition is a rise.
  The open door shows a WHITE light: `Inside` is an HDR white box drawn from within and smaller than the shell's
  inner walls (+-0.394), which would otherwise hide it.
  The TARDIS is SAVED: `_init` stamps `mod_object_type` (RetroXR's `MOD_TYPE_META`) whoever makes it, and the
  scene is in the `spawned` group. Its `PointerArea` has its origin at the body's MIDDLE: the screwdriver's cone
  measures to a collider's origin, from the floor a 2.3 m box is 40 degrees below where the hand points.
- `tools/convert_tardis.py` builds the TARDIS GLB (door leaf split off by a box of faces: `--leaf-*`).
  Entering the TARDIS (console room) is not built; `Tardis.entry` keeps where the player stood.
- Console rooms (`console_rooms.gd`: one per interior, room id `xenu.tardis:console_<id>`, permanent; **the default is
  "1", the 1st Doctor's**: the 10th's needs work. The table row has `scale`, `console` (radius, height), `door_light`,
  and `lights(id)` has each room's lights from photographs of the sets: the 10th is DARK, lit by amber roundels, a cyan
  rotor and console, the 1st is bright white with the roundels lit white. Each scene has its own Environment):
  `console_room.gd` builds the room at load from the GLB + JSON that `tools/convert_interior.py` makes
  (`tools/build_interiors.py` is not written: run the converter by hand, see its docstring; the sources are
  Blender scenes made for rendering: 4 M triangles to ~230 k, a minute and a half). The model is drawn at
  `ROOM_SCALE` (0.75: at 1.0 it was 19 m across with a 2.3 m door, "enormous") and everything built here
  follows it, the hull points scaled by hand (a collision shape's own scale is not trusted); the rig in the
  `.tscn` stands at the door scaled the same. It adds colliders on
  layer 1 (a flat floor at y = 0, wall ring, ceiling, console cylinder, plus one convex hull per pillar and part of
  the console from `10_collision.glb`), every material drawn on both sides, lights, the rotor bobbing, the door `VRButton` and the
  console (`console_menu.gd`: a pointable + `toggle_options_ui`, the way every RetroXR object's menu opens).
  `tools/convert_interior_fbx.py` makes the 1st Doctor's room from its FBX (no textures: colours; run by hand, its
  docstring says how). **Blender: `mesh.materials.clear()` zeroes every polygon's material index**: keep them
  aside and put them back (the first version put the whole room on one grey). The 10th's door is a dark alcove, so it
  gets a white `DoorLight`; the collision hulls over the doorway are skipped (one blocked the pointer's ray to the
  door's button: `tests/render_room_probe` prints what a ray from the eye to the door meets, and the suite asserts
  it is the button, for every room). `tardis_travel.gd` is the way in and out: the origin room is `SceneManager.current_scene_id` and the
  change is `change_scene`; coming out, a TARDIS is put back if the slot did not keep it, and the player
  placed at its door. RetroXR gives the room's slots, last-room memory and fallback by itself.
  The converter puts the floor at the median height where rays dropped on rings round the console land (the
  model has a raised platform and a lower floor: "the biggest flat area" was the wrong one). **Blender 4.2 crashes on `mesh.separate(type="MATERIAL")` and on `new_from_object` here**: the converter
  splits with bmesh and copies with `to_mesh()`; keep it that way. A RetroXR room has no way to be hidden
  from the SCENE tab; `register_room` is given `"hidden": true` for when it learns.
- The LED is the mesh named `Led` in the GLB (on the 10th: the emitter dome at the tip, split off the core
  rod by `--led-above`). A see-through LED would scale its glow by alpha, so lit it is made more opaque
  (`LED_ALPHA_ON`); an opaque one is not. It is emission only, no `Light3D`: RetroXR
  documents that a tiny light near a surface renders black on Quest.
- `tools/pack.py` exists because `pack_mod.gd` skips `.glb`/`.mp3`. RetroXR refuses a pack containing a
  `.md` (also a Mega Drive ROM extension) or any program/ROM extension: keep notes as `.txt`.
- Models: the originals live in `src.local/` (git-ignored, ~300 MB, has a `.gdignore` so Godot does not
  import it). Every converted GLB must have the same frame: origin on the grip, tip toward -Z, metres,
  LED mesh named `Led`, under 6000 triangles and at most 8 meshes, textures at 256 px (Quest 3 shares its budget with a room).

## Licences

Each model's licence must travel with it: `CREDITS.txt` (shipped in the pack). The 10th Doctor's and
the 5th's are CC BY 4.0 (attribution). The 11th's may require linking where it was
used on the site (the user's recollection, unverified: read its page); other models and the sounds have no recorded licence: ask the user.

## Conventions

- Comments are `##` doc blocks that explain *why*. Pure data in node-free scripts so tests can drive it.
