# Wwise Music Sources and Event Probe

How Darktide's native music reaches the player, how Music Replacer silences it, and how to find out where a sound comes from.

Statements marked **Confirmed** were checked by ear or in a real session's log.
Statements marked **Not yet confirmed** describe code that has not been tested in-game.

## Where Native Music Comes From

Native music has two sources, and the mod handles each differently.

### State Groups

The game's `WwiseGameSyncManager` sets Wwise state groups every tick through `_set_state(group_name, new_state)`.
Only real changes are forwarded to Wwise, so the mod hooks that function and compares old and new values itself.
Three groups matter for music:

| Group | Values seen so far |
|---|---|
| `music_combat` | `None`, `normal`, `horde_low`, `horde_high`, `boss` |
| `music_zone` | `hub`, `None`, `zone_2`, `zone_4`, `zone_8`, `operations` |
| `music_game_state` | `title`, `main_menu`, `loading`, `mission`, `mission_board`, `mission_ready`, `loadout`, `mission_briefing`, `mission_intro`, `victory`, `defeat`, `game_score_win`, `game_score_lose`, `None` |

Wwise reports "no value" as the string `"None"`, not as Lua `nil`.
The source lists more state groups (circumstance, event intensity, event type, objective, objective progression, minion aggro intensity, options, player state, suppression state).
None of those has been tried as a lever.

### Events

`WwiseWorld.trigger_resource_event(wwise_world, event_name, ...)` starts Wwise events, and some of them are music.

- `wwise/events/music/play_music_manager` is triggered once by the manager's own init, according to the game source. The probe has never logged it.
- `wwise/events/music/play_exploration_music` and `wwise/events/music/play_exploration_the_machine_spiri_1`, `_3` and `_4` were logged during mission event sequences, such as holding a position or minigames. **Confirmed:** native music was audible under a custom track during those sequences, and these were the only music events logged in that mission.
- `cinematics/play_outro_win_generic_01` and `ui/play_ui_eor_start_stinger` were logged during a mission's victory. Neither has "music" in its name. Which of them carries the native victory music has not been isolated.
- `cinematics/play_mission_intro_stinger_generic` was logged at the start of a mission's intro.
- `world/stop_all_mission_sounds` was logged when leaving the hub for a mission, and on shutdown.

## How the Mod Silences It

Each mechanism switches on only while a custom track is confirmed playing for the current context, so a context with no files keeps the game's own music.
`play_context` in `MusicReplacer.lua` turns them on with `Suppression.engage` and off with `Suppression.release`, and the code lives in `suppression.lua`.

| Mechanism | What it does | Status |
|---|---|---|
| `Suppression.set_combat` | Forces `music_combat` to `"None"` right away and again after every real transition. | Combat music reported gone in two hectic missions. Not yet checked in a controlled test. |
| `Suppression.set_zone` | Forces `music_zone` to `"None"` while a hub track plays, and restores the real zone when it stops. | **Confirmed** by ear in the hub, including a round trip through a mission. |
| `Suppression.set_game_state` | Forces `music_game_state` to `"None"` for the victory and defeat contexts, and again after every real transition. | **Not yet confirmed.** It only runs when a file is present in `mission_victory` or `mission_defeat`. |
| `Suppression.set_events` | Drops any event containing `events/music/play_exploration`, so it never starts. | **Not yet confirmed.** |

Forcing a state calls `Wwise.set_state` directly.
That call does not reach the `_set_state` hook, so the mod's own tracked state keeps the game's real value.
Across every logged session, no forced call has been followed by a duplicate instant transition line in the log.

The game re-sends a state only when it changes.
A forced `music_zone` stayed in place until the next real zone change.
`music_combat` and `music_game_state` change repeatedly, so the mod forces them again after every real transition.

Dropping an event stops only its start.
No matching stop event for the exploration events has been logged.
An event that fires while suppression is off is not dropped.

## The Event Probe

`scripts/mods/MusicReplacer/event_probe.lua` hooks `WwiseWorld.trigger_resource_event` and logs to `diagnostic.log`.
It never changes or silences anything.

Turn on **Diagnostic Logging** in the mod options first.
The log is written to `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`.

### What It Logs

| Line | Meaning |
|---|---|
| `[probe] music event: <name> (extra args: N)` | Any event whose name contains "music". Logged every time it fires. |
| `[probe] new event: <name>` | Any other event, logged once per distinct name per session. |

The hook is installed from `on_all_mods_loaded`, so it cannot see anything that fires earlier.
Music events are logged before the noise check, so they always appear.

### Noise Patterns

`NOISE_PATTERNS` in `event_probe.lua` is a list of plain substrings.
An event matching any of them is left out of the log, unless it contains "music".

The last column says how much the log would grow if that pattern were removed from the list.
Heavy would dominate the log, medium would add a noticeable block, and light would add a few lines.

Left out of the log, in the order they appear in `NOISE_PATTERNS`:

| Pattern | Covers | If removed |
|---|---|---|
| `events/minions/` | Enemy movement, voice, and footstep sounds. | Heavy |
| `events/weapon/` | Weapon swings, shots, hits, and impacts. | Heavy |
| `events/player/` | The player's own gear, footsteps, voice, pickups, and hits. | Heavy |
| `events/world/` | Doors, chests, elevators, destructibles, and mission sequence sounds. | Heavy |
| `events/ui/play_hud_` | HUD notification and popup sounds. | Medium |
| `events/ui/play_smart_tag` | Smart tag sounds. | Light |
| `events/ui/play_ui_mouseover` | Menu hover sounds. | Light |
| `events/ui/play_ui_click` | Menu click sounds. | Light |
| `events/ui/play_ui_enter` | Menu enter sounds, including `play_ui_enter_short`. | Light |
| `events/ui/play_ui_back` | Menu back sounds, including `play_ui_back_short`. | Light |
| `events/ui/play_ui_popup_` | Popup open and close sounds. | Light |
| `events/ui/play_ui_mission_` | Mission board and lobby sounds. | Medium |
| `events/ui/play_ui_npc_interacts` | Hub NPC interaction sounds. | Light |
| `events/ui/play_ui_character_loadout` | Loadout equip sounds. | Light |

Still logged, because no pattern matches them:

| Category | What it holds |
|---|---|
| `events/ui/` (everything not listed above) | The character-select ambience, the Valkyrie ambience and rumble, `play_ui_silence`, and the end-of-round stinger and loops. |
| `events/cinematics/` | The hub servitor fly-in, the mission intro stinger, and the win outro. |
| `events/vo/` | The hub PA notification and radio static events. |
| `events/npc/` | NPC sounds. |

Any event that matches no pattern is logged, whatever its folder.

What is left is short enough to read whole.

`events/ui/` and `events/cinematics/` are only partly excluded because the events logged during a victory, `cinematics/play_outro_win_generic_01` and `ui/play_ui_eor_start_stinger`, have no "music" in their names.
The "music" rule alone does not catch them.

`events/world/` is left out to keep the log short, not because it was shown to hold no music.
Removing `"events/world/"` from the list shows when each mission sequence starts and ends.
That is how the exploration music events were matched to the sequences they were logged during.

### Adding or Removing Patterns

Edit `NOISE_PATTERNS`.
Patterns are matched as plain substrings against the full event name, for example `wwise/events/world/play_door_x`.
Redeploy with `tools\build.ps1 -Deploy` and restart the game.

## Tracing a New Sound

1. Enable Diagnostic Logging and reproduce the sound.
2. Read `diagnostic.log` around the moment you hear it. The `[raw]`, `[context]`, `[playback]` and `[suppress]` lines show what the mod recorded as happening.
3. Look for `[probe] music event:` lines first, then for `[probe] new event:` lines that appeared shortly before the sound.
4. If no probe line fits, check whether a `[raw] music_*` transition lines up with the sound. Native music also comes from state groups, and the probe cannot see events that fire before its hook is installed.
5. If an event fits, add its pattern to `SUPPRESSED_MUSIC_EVENT_PATTERNS` in `suppression.lua`. If a state group is responsible, add a forcing toggle beside the existing ones.

The Audio Plugin has its own Wwise event logging, the `log_wwise` setting, which prints to the game's console log instead of this file.

## Reading the Game's Source

The public repository `Aussiemon/Darktide-Source-Code` holds the game's Lua.
The relevant files are under `scripts/managers/wwise_game_sync/`.

- `wwise_game_sync_manager.lua` triggers `play_music_manager` on init and sets each state group in `update`.
- `wwise_state_groups/wwise_state_group_zone.lua` takes the active mission's Wwise state, or a default when there is no mission.
- `wwise_state_groups/wwise_state_group_game.lua` maps the game state machine to the `music_game_state` values above.
