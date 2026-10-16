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

## Missions seen so far

| Mission | Notes |
|---|---|
| `hub_ship` | The hub, the Mourningstar. `wwise_state` is `hub`. |
| `tg_shooting_range` | The training area that Meat Grinder runs in. Its template has `game_mode_name = "shooting_range"`, `mechanism_name = "onboarding"`, and no `wwise_state`, which is why `music_zone` reads `None` there. The mod tells Meat Grinder apart from a mission by this name. |
| `fm_cargo`, `fm_resurgence`, `lm_rails`, `km_enforcer`, `km_station`, `cm_raid` | Ordinary missions. `mission_type` was `raid` for `fm_cargo` and `lm_rails`, `strike` for `fm_resurgence`, `assassination` for `km_enforcer` and `km_station`, and `disruption` for `cm_raid`. |
| `psykhanium` | Mortis Trials. `mission_type` is `horde`, and `game_mode_name` is `survival`. Its `music_zone` is `horde_mode` from the briefing until after the win. Waves set `music_objective` to `horde_mode_wave`, objective rounds to `horde_mode_objective`, the last wave to `horde_mode_wave_last`, and the win to `horde_mode_win`, with `None` between them. The mod recognizes Mortis Trials by its zone. |
| `op_train`, `op_no_mans_land` | Operations, Rolling Steel and No Man's Land. `mission_type` is `operations`, which the mod uses to treat the whole mission as one event. |

Whether the free Psykhanium also runs in `tg_shooting_range` is not known. If it does, the Meat Grinder choice in Music per Context covers it too.

Havoc and Expeditions have not been checked yet.

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
