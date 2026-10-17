# Wwise music states and events

How Darktide's own music reaches the player through Wwise, how Music Replacer silences it, and how to find out where a sound comes from.
It is a reference for reading `diagnostic.log` with Detailed Logging on.
Which mission or game mode is running is covered in [game-internals.md](game-internals.md).

## Where the game's music comes from

The game's music has two sources, and the mod handles each differently.

### State groups

The game sets Wwise state groups all the time, and Wwise picks the music from them.
With Detailed Logging on, every change shows up as a `[raw]` line, such as `[raw] music_zone: None -> hub`.
After the mod loads or is turned back on, it reads each group once more, which shows up as a line such as `[raw] music_zone: hub, read again`.
Four groups matter for music:

| Group | Values seen so far |
|---|---|
| `music_combat` | `None`, `normal`, `horde_low`, `horde_high`, `boss` |
| `music_zone` | `hub`, `None`, `zone_1` to `zone_6`, `zone_8`, `zone_2_depths`, `zone_twins`, `operations`, `horde_mode` |
| `music_game_state` | `title`, `main_menu`, `loading`, `mission`, `mission_board`, `mission_ready`, `loadout`, `mission_briefing`, `mission_intro`, `victory`, `defeat`, `game_score_win`, `game_score_lose`, `cinematic`, `None` |
| `music_objective` | `None`, `last_man_standing`, `kill_event`, `kill_event_2`, `kill_event_3`, `twins_event`, `fortification_event`, `hacking_event`, `scanning_event`, `escape_event`, `gauntlet_event`, `operation_stage_1`, `operation_2_stage_1` to `_4`, `progression_stage_1` to `_4`, `progression2_stage_1` to `_4`, and in Mortis Trials `horde_mode_wave`, `horde_mode_objective`, `horde_mode_wave_last`, `horde_mode_win` |

Wwise reports "no value" as the word `None`.

* `music_combat` is `normal` while enemies are attacking you, and it flips back to `None` every few seconds in a fight. The Combat Music Hold setting bridges those gaps. `horde_low` and `horde_high` mean a horde is on you, and `boss` means a monstrosity is near.
* `music_zone` names the hub or the mission's area. It arrives before the music can start: the hub zone about 10 seconds before the loading screen ends, and a mission zone partway through the briefing.
* `music_game_state` says where the player is. The hub and mission music only plays while it is `mission`, `mission_board`, or `mission_ready`. `loading`, `loadout`, and `mission_briefing` play the Loading music, and the mission intro keeps the game's own music. `cinematic` means a cutscene, which never gets custom music. After a mission, a story mission can go straight from `game_score_win` to `cinematic`.
* `music_objective` carries the last stand and mission event music. Some events set it to `None` for a few seconds between their stages, which the Event Music Hold setting bridges.

One more group, `options`, says which kind of menu is open.
It is `ingame_menu` in the Esc menu and its settings, the inventory, and the mission board, `vendor_menu` at vendors, `appearance_menu` in character appearance, `credit_store_menu` in the store, and `None` with no menu open.
The mod lowers custom music to the Menu Volume setting while it is anything but `None`, and logs its changes as `[raw] options` lines.

Expeditions have combat music of their own.
According to the game's source, an Expedition sets both `music_combat` and a group of its own, `expeditions_intensity`, to `no_combat`, `low_combat`, `med_combat`, `high_combat`, `safe_room`, or `extraction` instead of the values above.
The mod does not act on these values yet, but logs both groups' changes as `[raw]` lines.

### Events

Wwise events start sounds, and a few of them are music.

* `wwise/events/music/play_exploration_music` and `wwise/events/music/play_exploration_the_machine_spiri_1`, `_3`, and `_4` fire during hordes and around mission event sequences, such as holding a position or minigames.
* `cinematics/play_outro_win_generic_01` and `ui/play_ui_eor_start_stinger` fire during a mission's victory. Neither has "music" in its name, and which of them carries the victory music is not known.
* `cinematics/play_mission_intro_stinger_generic` fires at the start of a mission's intro.
* `world/stop_all_mission_sounds` fires when leaving the hub for a mission, and when the game closes.

## How the mod silences it

The mod only silences the game's music once it has a custom song for the current context, so a context with no files keeps the game's own music.
A context set to Silence in Music per Context is the one exception, which silences the game's music with no song at all. Meat Grinder is set to Silence by default.

Each line below shows up in the log with Detailed Logging on:

| Log line | What it means |
|---|---|
| `[suppress] forcing music_combat to None while a custom track plays` | The game's combat, horde, and boss music is off. It stays off through every change of `music_combat` until the custom song stops. |
| `[suppress] forcing music_zone hub -> None` | The game's hub music is off while a custom hub song plays. |
| `[suppress] forcing music_game_state victory -> None` | The game's victory, defeat, or loading music is off while a custom song for that context plays. |
| `[suppress] forcing music_objective fortification_event -> None` | The game's event, last stand, or Mortis Trials wave music is off while a custom song for that context plays. |
| `[suppress] skipped native music event: wwise/events/music/play_exploration_music` | The game's exploration music did not start, because a custom song plays. |
| `[suppress] restoring music_zone to hub` | The custom song stopped, so the game's own state, and with it its music, is back. |

A silenced state does not show up as a `[raw]` line, since the `[raw]` lines always show the game's own values.
An exploration music event that fires while no custom song plays is not skipped, so the game's music plays as usual.

## The event probe

With Detailed Logging on, the mod also logs the game's sound events, without changing or silencing any of them.

| Log line | What it means |
|---|---|
| `[probe] music event: <name> (extra args: N)` | An event whose name contains "music". It is logged every time it fires. |
| `[probe] new event: <name>` | Any other event, logged the first time it fires in a session. |

The probe starts once every mod has loaded, so it cannot see events from before that, such as the title screen's first sounds.

Most sound events are too frequent to log, so these are left out unless their name contains "music":

| Left out | Covers |
|---|---|
| `events/minions/` | Enemy movement, voice, and footstep sounds. |
| `events/weapon/` | Weapon swings, shots, hits, and impacts. |
| `events/player/` | The player's own gear, footsteps, voice, pickups, and hits. |
| `events/world/` | Doors, chests, elevators, destructibles, and mission sequence sounds. |
| `events/ui/play_hud_` | HUD notification and popup sounds. |
| `events/ui/play_smart_tag` | Smart tag sounds. |
| `events/ui/play_ui_mouseover`, `play_ui_click`, `play_ui_enter`, `play_ui_back` | Menu hover, click, enter, and back sounds. |
| `events/ui/play_ui_popup_` | Popup open and close sounds. |
| `events/ui/play_ui_mission_` | Mission board and lobby sounds. |
| `events/ui/play_ui_npc_interacts` | Hub NPC interaction sounds. |
| `events/ui/play_ui_character_loadout` | Loadout equip sounds. |

Everything else is logged, such as the rest of `events/ui/`, `events/cinematics/`, `events/vo/`, and `events/npc/`.
The victory events above have no "music" in their names, which is why `events/ui/` and `events/cinematics/` are only partly left out.

## Tracing a sound

1. Turn on Detailed Logging in the Debug group of the mod options, and play until you hear the sound.
2. Read `diagnostic.log` around that moment. The `[context]` and `[playback]` lines show which music the mod chose and why.
3. Look for `[probe] music event:` lines first, then for `[probe] new event:` lines from shortly before the sound.
4. If no probe line fits, look for a `[raw] music_*` change at that moment, since the game's music also follows its state groups.
5. If the game's music plays under a custom song, check for the matching `[suppress]` line from the table above. Its absence, or a `restoring` line, explains why the game's music came back.

A sound that turns out to be the game's music, but that the mod does not silence, is worth a bug report with the log attached.
