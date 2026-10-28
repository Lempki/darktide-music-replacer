# Game missions and modes

How Darktide reports which mission or game mode is running, as Music Replacer sees it. It is a reference for reading `diagnostic.log`, next to [wwise-events.md](wwise-events.md), which covers the music states and events. In the log, each situation from the README is a context, named after its audio folder, such as `explore` or `event`.

## The mission line

Every time the current mission changes, including on entering the hub, the log gets one line:

```
[mission] name=<mission name> type=<mission type> | <key>=<value>, <key>=<value>, ...
```

The name and the rest of the line come from the game's own mission template. The part after the bar lists every field of the template that holds plain text, a number, or true or false, sorted by name. The template's `wwise_state` field is what the game reports as `music_zone`. These lines are always logged, so every bug report says which mission it came from.

## Zones

`music_zone` names the area a mission takes place in, with its own music in the game.

| `music_zone` | Area |
|---|---|
| `prologue` | Tancred Bastion, the prologue |
| `hub` | The Mourningstar |
| `zone_1` | Transit Hub HL-16-11, "Chasm Terminus" |
| `zone_2` | Habzone HL-18-66, "The Torrent" |
| `zone_2_depths` | Spillway's area |
| `zone_twins` | The Torrent, for The Orthus Offensive |
| `zone_3` | Manufactory HL-17-36, "Metalfab 36" |
| `zone_4` | Freight Port HL-32-2, "Hourglass" |
| `zone_5` | Habzone HL-19-24, "Throneside" |
| `zone_6` | Habzone HL-70-04, "The Carnival" |
| `zone_8` | Inter-Zone Void Sector Omega-12 |
| `operations` | Operations, except for Rolling Steel |
| `horde_mode` | Mortis Trials |
| `expeditions` | Expeditions |

## Missions

The mission line names a mission by its code. These are the in-game names of the ordinary missions, which Havoc plays too, by area.

| Code | In-game name | `mission_type` | `music_zone` |
|---|---|---|---|
| `cm_habs` | Hab Dreyko | `investigation` | `zone_1` |
| `dm_rise` | Ascension Riser 31 | `strike` | `zone_1` |
| `km_station` | Chasm Station HL-16-11 | `assassination` | `zone_1` |
| `lm_rails` | Chasm Logistratum | `raid` | `zone_1` |
| `dm_stockpile` | Silo Cluster 18-66/a | `strike` | `zone_2` |
| `hm_cartel` | Vigil Station Oblivium | `espionage` | `zone_2` |
| `km_enforcer` | Magistrati Oubliette TM8-707 | `assassination` | `zone_2` |
| `km_enforcer_twins` | The Orthus Offensive | `assassination` | `zone_twins` |
| `spillway` | Spillway | `assassination` | `zone_2_depths` |
| `dm_forge` | Smelter Complex HL-17-36 | `repair` | `zone_3` |
| `fm_cargo` | Consignment Yard HL-17-36 | `raid` | `zone_3` |
| `lm_cooling` | Power Matrix HL-17-36 | `repair` | `zone_3` |
| `dm_propaganda` | Relay Station TRS-150 | `disruption` | `zone_4` |
| `hm_strain` | Refinery Delta-17 | `disruption` | `zone_4` |
| `lm_scavenge` | Excise Vault Spireside-13 | `investigation` | `zone_4` |
| `cm_archives` | Archivum Sycorax | `espionage` | `zone_5` |
| `fm_resurgence` | Enclavum Baross | `strike` | `zone_5` |
| `hm_complex` | Comms-Plex 154/2f | `espionage` | `zone_5` |
| `cm_raid` | Warren 6-19 | `disruption` | `zone_6` |
| `fm_armoury` | Mercantile HL-70-04 | `raid` | `zone_6` |
| `km_heresy` | Dark Communion | `investigation` | `zone_6` |
| `core_research` | Clandestium Gloriana | `repair` | `zone_8` |
| `op_train` | Rolling Steel | `operations` | none |
| `op_no_mans_land` | No Man's Land | `operations` | `operations` |

## Missions and modes with notes

| Mission | Notes |
|---|---|
| `prologue` | Tancred Bastion, the prologue a new character plays, with `game_mode_name` `prologue` and the zone `prologue`. It scripts its music through `music_objective`, with `prologue_explore`, `prologue_combat`, and `prologue_end_event`, so most of it resolves to `event`. The `event\prologue\` override folder covers every event in the prologue, and `event\prologue_explore\`, `event\prologue_combat\`, and `event\prologue_end_event\` cover its parts. Its cutscenes start music events of their own, which the mod stops once a custom song takes over after one. |
| `hub_ship` | The hub, the Mourningstar. `wwise_state` is `hub`. |
| `tg_shooting_range` | The training area that Meat Grinder runs in. Its template has `game_mode_name = "shooting_range"`, `mechanism_name = "onboarding"`, and no `wwise_state`, so `music_zone` reads `None` there. The mod tells Meat Grinder apart from a mission by this name. Its Meat Grinder settings then decide what it resolves: `meat_grinder`, the situation One Situation picks, or the mission situations. |
| `om_basic_combat_01` | The Psykhanium's Basic Training. Its template has `game_mode_name = "training_grounds"` and `mechanism_name = "onboarding"`. It runs in the same level as Meat Grinder and reports no zone. It counts as a zoneless mission, so the `explore` and `combat` folders play, not `meat_grinder`. |
| `psykhanium` | Mortis Trials. `mission_type` is `horde`, and `game_mode_name` is `survival`. Its `music_zone` is `horde_mode` from the briefing until after the win. Waves set `music_objective` to `horde_mode_wave`, objective rounds to `horde_mode_objective`, the last wave to `horde_mode_wave_last`, and the win to `horde_mode_win`. It is `None` between them. Each of these values resolves to `mortis_trials_wave`, and `None` resolves to `mortis_trials_break`. The mod recognizes Mortis Trials by its zone, and by `game_mode_name` for the `mortis_trials` override folders. |
| `km_enforcer_twins` | The Orthus Offensive, the Karnak Twins mission, with a zone of its own. Each fight with the Twins sets `music_objective` to `twins_event`, and the final fight with both of them to `kill_event_2`. All of them resolve to `event`. A short cutscene before the final fight resolves to no context. |
| `exp_wastes` | Expeditions. `mission_type` is `expeditions`, `game_mode_name` is `expedition`, and its zone is `expeditions`. It reports its own combat states, which resolve to `expedition_combat`, `expedition_safe_room`, and `expedition_extraction`. It reports no horde or boss. The game decides only once per launch, on the first mission, whether it runs an Expedition. So the mod makes it decide again at every mission. Without that, an Expedition after an ordinary mission would report the ordinary states, and an ordinary mission after an Expedition the Expedition states. The game's music for an Expedition sets no `music_objective`. |
| `op_train`, `op_no_mans_land` | Operations. Their `mission_type` is `operations`, which the mod uses to treat the whole mission as one `event`. |

## Game modes and early mission names

Havoc plays the ordinary missions and reports nothing of its own to the music. The mission line, the zone, and every music state are the same as in an ordinary run, and `circumstance` stays `None`. The game keeps Havoc's own data in its difficulty manager, which is how the mod tells a Havoc run apart for the `havoc` override folders. With Detailed Logging on, the log says `[mission] game mode: havoc` once a Havoc run starts. It says `[mission] game mode: expeditions` in an Expedition, `[mission] game mode: mortis_trials` in Mortis Trials, and `[mission] game mode: ordinary` after any of them.

The level names its mission only seconds before the briefing ends. The game's mechanism data names it earlier, once the client has joined the mission server, before the level loads. On the way into a mission, the mod reads the mission and its game mode from there, so override folders apply on the loading screens, the preparation screen, and the briefing too. With Detailed Logging on, the log then says, for example, `[mission] heading to exp_wastes, game mode: expeditions`. Havoc is only known once the mission has loaded, since its data arrives with the level.

## Moving between the hub, missions, and menus

* Leaving the hub for a mission clears the hub zone a moment before it switches the game state to `loading`. The game then reports a loading screen for about 2 seconds before the preparation screen. So a change to a loading screen waits 3 seconds, and the hub song carries straight on into the preparation screen's song. The step from the preparation screen into the briefing takes the usual half a second.
* The prologue reports `mission` for about two seconds after its loading screen, before its intro starts. So the first situation after a loading screen waits 3 seconds before its song starts, and an intro or cutscene that begins in that time takes its place. The hub and the preparation screen take the usual half a second, since nothing replaces them a moment after they arrive.
* After a victory or defeat, the game state goes back to `mission` for a few seconds before the score screen. The mod keeps the `victory` or `defeat` music through it.
* Leaving the hub for character select clears the zone and unloads the hub at once. The game state stays on `mission` for a few seconds before it switches to `main_menu`. The mod plays no music in between.
* Some missions never report a zone, such as Rolling Steel and Basic Training. There, the mod treats the `mission` game state with a mission loaded as being in a mission. With Detailed Logging on, the log then says `[zoneless] music_zone=None with music_game_state=mission, treating as a mission`.

## Reading the game's source

The public repository `Aussiemon/Darktide-Source-Code` holds the game's Lua, which is where most fields and values above come from. The rest, such as the Basic Training row, are observations from play.

* `scripts/managers/wwise_game_sync/wwise_game_sync_manager.lua` sets each music state group on every tick.
* `scripts/managers/wwise_game_sync/wwise_state_groups/` holds one file per state group. `wwise_state_group_zone.lua` takes the current mission's `wwise_state`, and `wwise_state_group_game.lua` maps the game's state to the `music_game_state` values.
* `scripts/managers/mission/mission_manager.lua` holds the current mission and its template.
* `scripts/managers/mechanism/mechanism_manager.lua` holds the mechanism data that names a mission before its level loads.
* `scripts/settings/mission/mission_types.lua` lists the mission types.
