# Game missions and modes

How Darktide reports which mission or game mode is running, as Music Replacer sees it.
It is a reference for reading `diagnostic.log`, next to [wwise-events.md](wwise-events.md), which covers the music states and events.

## The mission line

Every time the current mission changes, including on entering the hub, the log gets one line:

```
[mission] name=<mission name> type=<mission type> | <key>=<value>, <key>=<value>, ...
```

The name and the rest of the line come from the game's own mission template.
The part after the bar lists every field of the template that holds plain text, a number, or true or false, sorted by name.
The template's `wwise_state` field is what the game reports as `music_zone`.
These lines are always logged, so every bug report says which mission it came from.

## Missions

The mission line names a mission by its code. These are the in-game names of the ordinary missions, which Havoc plays too, by area.

| Code | In-game name | `mission_type` | `music_zone` |
|---|---|---|---|
| `cm_habs` | Hab Dreyko | `investigation` | `zone_1` |
| `dm_rise` | Ascension Riser 31 | `strike` | `zone_1` |
| `km_station` | Chasm Station HL-16-11 | `assassination` | `zone_1` |
| `lm_rails` | Not known yet | `raid` | `zone_1` |
| `dm_stockpile` | Silo Cluster 18-66/a | `strike` | `zone_2` |
| `hm_cartel` | Vigil Station Oblivium | `espionage` | `zone_2` |
| `km_enforcer` | Magistrati Oubliette TM8-707 | `assassination` | `zone_2` |
| `km_enforcer_twins` | The Orthus Offensive | `assassination` | `zone_twins` |
| `spillway` | Spillway | `assassination` | `zone_2_depths` |
| `dm_forge` | Smelter Complex HL-17-36 | `repair` | `zone_3` |
| `fm_cargo` | Consignment Yard HL-17-36 | `raid` | `zone_3` |
| `lm_cooling` | Not known yet | `repair` | `zone_3` |
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

`hm_strain`'s name is inferred, since it is the only disruption mission left for it.

## Missions and modes with notes

| Mission | Notes |
|---|---|
| `hub_ship` | The hub, the Mourningstar. `wwise_state` is `hub`. |
| `tg_shooting_range` | The training area that Meat Grinder runs in. Its template has `game_mode_name = "shooting_range"`, `mechanism_name = "onboarding"`, and no `wwise_state`, which is why `music_zone` reads `None` there. The mod tells Meat Grinder apart from a mission by this name. |
| `psykhanium` | Mortis Trials. `mission_type` is `horde`, and `game_mode_name` is `survival`. Its `music_zone` is `horde_mode` from the briefing until after the win. Waves set `music_objective` to `horde_mode_wave`, objective rounds to `horde_mode_objective`, the last wave to `horde_mode_wave_last`, and the win to `horde_mode_win`, with `None` between them. The mod recognizes Mortis Trials by its zone. |
| `km_enforcer_twins` | The Orthus Offensive, the Karnak Twins mission, with a zone of its own. Each fight with the Twins sets `music_objective` to `twins_event`, and the final fight with both of them to `kill_event_2`, so all of them resolve as events. A short cutscene before the final fight resolves no context. |
| `exp_wastes` | Expeditions. `mission_type` is `expeditions`, `game_mode_name` is `expedition`, and its zone is `expeditions`. Its combat, horde, and boss states are the same as in an ordinary mission, so the mission contexts play there as usual. The game's own music for an Expedition sets no `music_objective`. |
| `op_train`, `op_no_mans_land` | Operations. Their `mission_type` is `operations`, which the mod uses to treat the whole mission as one event. |

Whether the free Psykhanium also runs in `tg_shooting_range` is not known. If it does, the Meat Grinder choice in Music per Context covers it too.

Havoc has not been checked yet.

## Moving between the hub, missions, and menus

* Leaving the hub for a mission clears the hub zone and switches the game state to `loading` at the same moment.
* Leaving the hub for character select clears the zone and unloads the hub at once, but keeps the game state on `mission` for a few seconds before it switches to `main_menu`. The mod plays no music in between.
* After a victory or defeat, the game state goes back to `mission` for a few seconds before the score screen. The mod keeps the victory or defeat music through it.
* Some missions never report a zone, such as Rolling Steel. The mod counts the `mission` game state with a mission loaded as being in a mission there.

## Reading the game's source

The public repository `Aussiemon/Darktide-Source-Code` holds the game's Lua, which is where the fields and values above come from.

* `scripts/managers/wwise_game_sync/wwise_game_sync_manager.lua` sets each music state group on every tick.
* `scripts/managers/wwise_game_sync/wwise_state_groups/` holds one file per state group. `wwise_state_group_zone.lua` takes the current mission's `wwise_state`, and `wwise_state_group_game.lua` maps the game's state to the `music_game_state` values.
* `scripts/managers/mission/mission_manager.lua` holds the current mission and its template.
* `scripts/settings/mission/mission_types.lua` lists the mission types.
