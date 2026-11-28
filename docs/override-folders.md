# Override folders

Override folders are optional and for advanced use. Your music works without them.

A folder can hold folders of its own, named after what the game reports, that take over from it while they apply. For example:

```
audio\
├── boss\
│   └── chaos_spawn\       While a Chaos Spawn is the boss.
├── event\
│   └── escape_event\      During an escape.
├── explore\
│   └── expeditions\       While you explore in an Expedition.
└── victory\
    └── game_score_win\    On the score screen after a win.
```

The mod does not create these folders, so make the ones you want. Their names are not case-sensitive, and folders inside an override folder are not read.

## Folder names

Every folder except `title_screen`, `character_select`, `hub`, and `loading` can hold these. Those four belong to no one mission, so the mod never looks for a mission's code or a game mode in them, even while the game already or still names a mission:

* The mission's code, such as `spillway` or `km_enforcer_twins`. [Missions](#missions) lists every mission with its in-game name and folder name.
* The mission's circumstance, by the name the game's music uses for it, which [Circumstances](#circumstances) lists. A circumstance applies once the mission has loaded.
* The event's intensity, `high_intensity` or `low_intensity`, in `event` and `mortis_trials_wave` only. The game turns it high as an event starts and while its progress moves on, and lets it fall back to low over about 80 seconds once nothing moves it, such as while a decoder is blocked.
* The game mode: `havoc`, `expeditions`, or `mortis_trials`.

These folders can also hold the game's name for a moment inside them:

| Folder | Names | When they play |
|---|---|---|
| `event` | The kind of event: `kill_event`, `kill_event_2`, `kill_event_3`, `twins_event`, `fortification_event`, `hacking_event`, `scanning_event`, `collect_event`, `demolition_event`, `escape_event`, `gauntlet_event`, `progression_stage_1` to `_4`, or `progression2_stage_1` to `_4`. In the prologue, `prologue_explore`, `prologue_combat`, or `prologue_end_event`. In an Operation, its stage: `operation_stage_1` to `_4` in Rolling Steel and `operation_2_stage_1` to `_4` in No Man's Land. | During that kind of event. |
| `boss_near` | The same names as `boss`, and with Boss Music for Daemonhosts on, also `chaos_mutator_daemonhost`, which shows no HP bar. With the folder empty, it looks for the same names inside `boss`, such as `boss\chaos_spawn\`. | While that boss is near. With several, the one that came near first, until it is gone or far enough away. |
| `boss` | `chaos_spawn`, `chaos_beast_of_nurgle`, `chaos_plague_ogryn`, `chaos_ogryn_houndmaster`. With Boss Music for Captains on, also `renegade_captain`, `cultist_captain`, `renegade_twin_captain`, `renegade_twin_captain_two`. With Boss Music for Daemonhosts on, also `chaos_daemonhost` and `chaos_daemonhost_torment`. | While that boss is in the fight. With several, the one that came first, until it dies or despawns, so bosses that come back to back do not change the music each time. |
| `hub` | `mission_ready` | While your party is matchmaking, from choosing a mission until it starts. |
| `character_select` | `character_creation` | While you create a character. |
| `victory`, `defeat` | `game_score_win`, `game_score_lose` | Once the score screen opens. The parent folder then plays only the closing shot of the mission. |
| `cutscene` | The cutscene's name: `cutscene_2` to `cutscene_10` and `cutscene_5_hub` for the story cutscenes, `traitor_captain_intro`, `path_of_trust_01` to `_09`, and `hub_location_intro_barber`, `_contracts`, `_crafting`, `_gun_shop`, `_mission_board`, and `_training_grounds` for the Mourningstar's first visits. | During that cutscene. Cutscenes belong to no one mission, so the mod looks for no mission's code or game mode in this folder. |
| `mortis_trials_wave` | `horde_mode_wave`, `horde_mode_objective`, `horde_mode_wave_last`, `horde_mode_win` | During a wave, an objective round, the last wave, or the final win. |
| `expedition_combat` | `low_combat`, `med_combat`, `high_combat` | At that fight level, which follows how alert the enemy is. The level can change during a fight, which switches the song, and a level that comes back continues its song. |

## Circumstances

A mission's circumstance gets the name the game's music uses for it. Several circumstances share one name, since the game's music tells them apart no further:

| Folder name | Circumstances |
|---|---|
| `darkness_01` | Power Supply Interruption, alone or with another condition, such as Hunting Grounds (Power Supply Interruption) |
| `hunting_grounds_01` | Hunting Grounds, alone or with another condition other than Power Supply Interruption |
| `ventilation_purge_01` | Ventilation Purge, Pox Gas, and Cartel's Favours |
| `ember_01` | Inferno |
| `nurgle_manifestation_01` | Heretical Disruption |
| `assault_01` | Assault |

Every other circumstance, such as Shock Troop Gauntlet, Engagement Zone, or Stolen Rations, sets no name for the game's music, so no folder applies to it. With Debug Overlay on, the Folder line names the circumstance a mission has.

## Combining names

A folder's name can join several of the names above with `+`, such as `boss\chaos_spawn+havoc\`, which plays while a Chaos Spawn is the boss in a Havoc run. A combined folder plays only while every one of its names applies, and the order they are written in does not matter. Some more examples:

* `explore\spillway+darkness_01\` plays while you explore Spillway with Power Supply Interruption.
* `event\kill_event+high_intensity\` plays while a kill event runs at high intensity.
* `horde\havoc+hunting_grounds_01\` plays during a horde in a Havoc run with Hunting Grounds.

## Missions

A mission's folder is named after its code, which the game uses for it internally. For example, `explore\spillway\` plays while you explore Spillway.

| Mission | Area | Folder name |
|---|---|---|
| Hab Dreyko | Chasm Terminus | `cm_habs` |
| Ascension Riser 31 | Chasm Terminus | `dm_rise` |
| Chasm Station HL-16-11 | Chasm Terminus | `km_station` |
| Chasm Logistratum | Chasm Terminus | `lm_rails` |
| Silo Cluster 18-66/a | The Torrent | `dm_stockpile` |
| Vigil Station Oblivium | The Torrent | `hm_cartel` |
| Magistrati Oubliette TM8-707 | The Torrent | `km_enforcer` |
| The Orthus Offensive | The Torrent | `km_enforcer_twins` |
| Spillway | The Torrent | `spillway` |
| Smelter Complex HL-17-36 | Metalfab 36 | `dm_forge` |
| Consignment Yard HL-17-36 | Metalfab 36 | `fm_cargo` |
| Power Matrix HL-17-36 | Metalfab 36 | `lm_cooling` |
| Relay Station TRS-150 | Hourglass | `dm_propaganda` |
| Refinery Delta-17 | Hourglass | `hm_strain` |
| Excise Vault Spireside-13 | Hourglass | `lm_scavenge` |
| Archivum Sycorax | Throneside | `cm_archives` |
| Enclavum Baross | Throneside | `fm_resurgence` |
| Comms-Plex 154/2f | Throneside | `hm_complex` |
| Warren 6-19 | The Carnival | `cm_raid` |
| Mercantile HL-70-04 | The Carnival | `fm_armoury` |
| Dark Communion | The Carnival | `km_heresy` |
| Clandestium Gloriana | Void Sector Omega-12 | `core_research` |
| Rolling Steel | Operations | `op_train` |
| No Man's Land | Operations | `op_no_mans_land` |
| Tancred Bastion, the prologue | | `prologue` |
| Mortis Trials | | `psykhanium` |
| Expeditions | | `exp_wastes` |
| Meat Grinder | | `tg_shooting_range` |
| Basic Training and Advanced Training in the Psykhanium | | `om_basic_combat_01` |

Havoc plays the ordinary missions, so their folders apply there too. For Havoc, Mortis Trials, and Expeditions as a whole, the game mode folders `havoc`, `mortis_trials`, and `expeditions` are simpler.

## Which one plays

When several apply, the most specific one that has songs wins:

1. A folder that combines more names wins over one with fewer, so `chaos_spawn+havoc` wins over both `chaos_spawn` and `havoc`.
2. Between folders with as many names, the one with the more specific name wins. From the most specific, the names rank: the moment's name, the event's intensity, the mission's code, the circumstance, and the game mode. So `chaos_spawn` wins over `spillway`, and `spillway` wins over `havoc`.
3. Between two combined folders with as many names, their most specific names are compared first, then the next ones. So `chaos_spawn+spillway` wins over `chaos_spawn+havoc`.

An override folder with no songs is skipped, so its parent folder, or the game's music, plays as before. A [Vanilla marker](../README.md#the-vanilla-marker) or a [Silence marker](../README.md#the-silence-marker) counts as a song here, so an override folder that holds only a marker keeps the game's music, or silence, for its moment.

Both Operations end with an `escape_event`, the same kind every mission's escape has. So `event\escape_event\` plays at the end of Rolling Steel and No Man's Land too, ahead of `event\op_train\` and `event\op_no_mans_land\`.

On the way into a mission, the mission's code and its game mode apply on the preparation screen and in the briefing. So `mission_briefing\mortis_trials\` plays during the Mortis Trials briefing. Havoc applies only once the mission has loaded, so a `havoc` folder does not apply on the preparation screen or during most of the briefing.

The music switches within half a second once another override applies, for example when the first boss to come near is gone while another is still near, or when an event moves on to its escape. When the situation switches back to a folder it already played, its song continues where it stopped, as long as Resume Songs is on. Rolling Steel goes back and forth between its first two stages, so each stage's folder keeps its own song going. A new situation starts every folder with a fresh song. A moment the game names by its screen, such as matchmaking, character creation, or the score screen, keeps its folder for 2 seconds after it ends, since the game passes through another state on the way out. With Debug Overlay on, its Folder line shows the folder that plays and the override names the moment looks for.

To try out a boss override folder, set Meat Grinder's Music to One Situation and pick Boss. While a boss dummy is alive, the folder named after its breed plays, such as `boss\chaos_spawn\`. Meat Grinder runs no events, waves, or score screens, and belongs to no game mode, so the override folders for those never play there. A folder named after Meat Grinder's own mission code, `tg_shooting_range`, does.
