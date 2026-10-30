# Wwise music states and events

How Darktide's music reaches the player through Wwise, how Music Replacer silences it, and how to find out where a sound comes from. It is a reference for reading `diagnostic.log` with Detailed Logging on. In the log, each situation from the README is a context, named after its audio folder, such as `explore` or `mission_briefing`. Which mission or game mode is running is covered in [game-internals.md](game-internals.md).

## Where the game's music comes from

The game's music has two sources, and the mod handles each differently.

### State groups

The game sets Wwise state groups all the time, and Wwise picks the music from them. With Detailed Logging on, every change shows up as a `[raw]` line, such as `[raw] music_zone: None -> hub`. After the mod loads or is turned back on, it reads each group once more, which shows up as a line such as `[raw] music_game_state: mission, read again`. Four groups matter for music:

| Group | Values |
|---|---|
| `music_combat` | `None`, `normal`, `horde_low`, `horde_high`, `boss`, and in Expeditions `no_combat`, `low_combat`, `med_combat`, `high_combat`, `safe_room`, `extraction` |
| `music_zone` | `None`, `prologue`, `hub`, `zone_1`, `zone_2`, `zone_2_depths`, `zone_twins`, `zone_3`, `zone_4`, `zone_5`, `zone_6`, `zone_8`, `operations`, `horde_mode`, `expeditions` |
| `music_game_state` | `title`, `main_menu`, `character_creation`, `loading`, `mission_loading`, `mission`, `mission_board`, `mission_ready`, `loadout`, `loadout_ready`, `mission_briefing`, `mission_intro`, `victory`, `defeat`, `game_score_win`, `game_score_lose`, `cinematic`, `cinematic_pot`, `None` |
| `music_objective` | `None`, `last_man_standing`, in the prologue `prologue_explore`, `prologue_combat`, `prologue_end_event`, in missions `kill_event`, `kill_event_2`, `kill_event_3`, `twins_event`, `fortification_event`, `hacking_event`, `scanning_event`, `collect_event`, `demolition_event`, `escape_event`, `gauntlet_event`, `progression_stage_1` to `_4`, `progression2_stage_1` to `_4`, in Operations `operation_stage_1` to `_4`, `operation_2_stage_1` to `_4`, and in Mortis Trials `horde_mode_wave`, `horde_mode_objective`, `horde_mode_wave_last`, `horde_mode_win` |

The game's settings also list `music_game_state` values that have not shown up in play: `credits`, `game_start`, `mission_start`, `mission_outro`, and `game_score`. Any of them would resolve no situation, so the game's music would play.

Wwise reports "no value" as the word `None`.

* `music_combat` is `normal` while enemies are attacking you. It flips back to `None` every few seconds in a fight, and the Combat Music Hold setting bridges those gaps. `horde_low` and `horde_high` mean a horde is on you. Every horde starts at `horde_high` and drops to `horde_low` as it thins out. The game reports a horde only while at least 5 enemies are aggroed, and the Horde Music Hold setting bridges the moments it drops out. `boss` means a monstrosity is near. It can drop out for a second or two while the boss is still alive, and the Boss Music Hold setting bridges that until the boss's encounter ends. In an Expedition, the group carries the Expedition values in place of the others. These values follow how alert the enemy is, not how hard the fight is. The mod resolves `low_combat`, `med_combat`, and `high_combat` as `expedition_combat`, `safe_room` as `expedition_safe_room`, `extraction` as `expedition_extraction`, and `no_combat` as `explore`. The Combat Music Hold setting covers `expedition_combat` too.
* `music_zone` names the hub or the mission's area. It arrives before the music can start. The hub zone arrives about 10 seconds before the loading screen ends, and a mission zone partway through the briefing.
* `music_game_state` says where the player is, as the table below lays out.
* `music_objective` carries the last stand and mission event music. Some events set it to `None` for a few seconds between their stages, which the Event Music Hold setting bridges.

A `music_combat` value outside the table is unknown to the mod, so below the last stand, Mortis Trials, the Expedition extraction, and events, the mod hands that moment to the game's music. It always logs the value once, such as `[context] music_combat has a value the mod does not know, new_state, so the game's music plays`.

What each `music_game_state` value plays, by the dropdowns in Music per Situation:

| `music_game_state` | What plays |
|---|---|
| `title` | The Title Screen music. |
| `main_menu`, `character_creation` | The Character Select music. Character creation is a step inside character select. |
| `mission`, `mission_board`, `mission_ready` | The hub and mission music, picked by the other groups. It plays in these states only. `mission_board` is the mission board's screen, and `mission_ready` is matchmaking, from choosing a mission until it starts. |
| `loadout`, `loadout_ready` | The Mission Preparation music. These states are the mission preparation screen. |
| `mission_briefing` | The Mission Briefing music. |
| `loading`, `mission_loading` | The Mission Briefing music on the way into a mission, else the Loading music. |
| `mission_intro` | The game's music. This state is the mission's intro. |
| `victory`, `game_score_win` | The Victory music, until the loading screen. `game_score_win` is the score screen. |
| `defeat`, `game_score_lose` | The Defeat music, until the loading screen. `game_score_lose` is the score screen. |
| `cinematic`, `cinematic_pot` | The game's music. These states are cutscenes, which never get custom music. Story cutscenes use `cinematic`, and the hub's own, such as Path of Trust and the hub location intros, use `cinematic_pot`. |

A loading screen leads into a mission when it follows `mission_ready`, `loadout`, or `mission_briefing`. Matchmaking that finds a mission goes back to `mission` for about a second before the loading screen. When `mission` lasts 5 seconds after `mission_ready`, the matchmaking ended without a mission, and with Detailed Logging on the log says `[mission] matchmaking ended without a mission`. After a mission, a story mission can go straight from `game_score_win` to `cinematic`.

Two more groups matter to the mod. The `options` group says which kind of menu is open. It is `ingame_menu` in the Esc menu and its settings, the inventory, and the mission board. It is `vendor_menu` at vendors, `appearance_menu` in character appearance, and `credit_store_menu` in the store. It is `None` with no menu open. The game's settings also list `story_mission_menu` and `credits`. The mod lowers custom music to the Menu Volume setting while it is anything but `None`, and logs its changes as `[raw] options` lines.

The `expeditions_intensity` group always holds the same value as `music_combat`, in every mission and in Expeditions. While a custom song plays, the mod forces both groups to `None`. Unlike `music_combat`, it only shows up as a `[raw]` line when it moves to or from an Expedition value.

The `[raw]` lines also show `music_objective_progression`, `event_intensity`, `event_category`, and `circumstance`, which do not affect the context.

### Events

Wwise events start sounds, and a few of them are music.

* `wwise/events/music/play_exploration_music` and `wwise/events/music/play_exploration_the_machine_spiri_1`, `_3`, and `_4` fire during hordes and around mission event sequences, such as holding a position or minigames.
* `wwise/events/cinematics/play_outro_win_generic_01` and `wwise/events/ui/play_ui_eor_start_stinger` fire during a mission's victory. Neither has "music" in its name.
* `wwise/events/cinematics/play_mission_intro_stinger_generic` fires at the start of a mission's intro.
* Events under `wwise/events/cinematics/` with `music` in their name, such as `play_cs01_cs02_music_combat` or `play_cs03_music_116bpm`, start a cutscene's music. It can run on after the cutscene ends, so the mod stops it once a custom song takes over.

## How the mod silences it

The mod only silences the game's music once it has a custom song for the current context, so a context with no songs keeps the game's music. A context set to Silence is the one exception. It silences the game's music with no song at all, by forcing the same groups as a custom song for that context does. Meat Grinder is set to Silence by default. A context set to Vanilla never silences the game's music.

Each line below shows up in the log with Detailed Logging on.

| Log line | What it means |
|---|---|
| `[suppress] forcing music_combat normal -> None` | The game's combat, horde, and boss music is off. It shows when the silencing starts while `music_combat` has a value other than `None`. It stays off through every later change of `music_combat` until the custom song stops. |
| `[suppress] forcing expeditions_intensity normal -> None` | The same for `expeditions_intensity`. The mod forces and restores it together with `music_combat`, in every context. |
| `[suppress] forcing music_zone hub -> None` | The game's hub music is off while a custom `hub` song plays. |
| `[suppress] forcing music_game_state victory -> None` | The game's music for `title_screen`, `character_select`, `loading`, `mission_preparation`, `mission_briefing`, `victory`, or `defeat` is off while a custom song for that context plays. |
| `[suppress] forcing music_objective fortification_event -> None` | The game's music for `event`, `last_stand`, or `mortis_trials_wave` is off while a custom song for that context plays. |
| `[suppress] stopped the game's music event: wwise/events/music/play_exploration_music` | The mod stopped the game's exploration music event as it started, since a custom song plays. It stops every event whose name contains `events/music/play_exploration`. |
| `[suppress] stopped the cutscene's music event: wwise/events/cinematics/play_cs03_music_116bpm` | A custom song took over after a cutscene, so the mod stopped that cutscene's music event, which can run on after the cutscene ends. It shows for every cutscene music event of the current level, even one that had already ended. When a level ends, or the mod is turned off, the mod forgets its cutscene music, since the game stops it and its Wwise world goes away. |
| `[suppress] restoring music_zone to hub` | The group is back at the game's value, and the game's music with it. It shows when the custom song stops, or when the next context does not silence that group. Each restored group logs its own line. |

A silenced state does not show up as a `[raw]` line, since the `[raw]` lines always show the game's values. An exploration music event that fires while the mod is not silencing the game's music is not stopped, so the game's music plays as usual.

## Holds and bosses

These lines also show up with Detailed Logging on:

| Log line | What it means |
|---|---|
| `[hold] combat quiet, holding combat for 8.0s more` | The game's state for that context went quiet, and its Music Holds setting keeps the context for the seconds shown. |
| `[raw] boss_encounter_start breed=chaos_spawn` | A boss's encounter window opened, named by its breed. A breed that counts as a boss names the `boss` override folder. |
| `[raw] boss_encounter_end breed=chaos_spawn` | That window closed, as when the boss dies or despawns. Once no boss that counts is left, the Boss Music Hold ends at once. |

## The event probe

With Detailed Logging on, the mod also logs the game's sound events, without changing or silencing any of them.

| Log line | What it means |
|---|---|
| `[probe] music event: <name> (extra args: N)` | An event whose name contains "music". It is logged every time it fires. |
| `[probe] new event: <name>` | Any other event, logged the first time it fires after the game starts. |

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

Everything else is logged, such as the rest of `events/ui/`, `events/cinematics/`, `events/vo/`, and `events/npc/`. The victory events above have no "music" in their names, which is why `events/ui/` and `events/cinematics/` are only partly left out.

## Tracing a sound

1. Turn on Detailed Logging in the Debug group of the mod options, and play until you hear the sound.
2. Read `diagnostic.log` around that moment. The `[context]` and `[playback]` lines show which music the mod chose and why.
3. Look for `[probe] music event:` lines first, then for `[probe] new event:` lines from shortly before the sound.
4. If no probe line fits, look for a `[raw] music_*` change at that moment, since the game's music also follows its state groups.
5. If the game's music plays under a custom song, check for the matching `[suppress]` line from the table above. Its absence, or a `restoring` line, explains why the game's music came back.

A sound that turns out to be the game's music, but that the mod does not silence, is worth a bug report with the log attached.
