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

Every folder except `title_screen`, `character_select`, `hub`, and `loading` can hold these:

* The mission's code, such as `spillway` or `km_enforcer_twins`. [game-internals.md](game-internals.md) lists every mission's code with its in-game name.
* The game mode: `havoc`, `expeditions`, or `mortis_trials`.

These folders can also hold the game's name for a moment inside them:

| Folder | Names | When they play |
|---|---|---|
| `event` | The kind of event, such as `escape_event`, `fortification_event`, `twins_event`, or an Operation's `operation_stage_1`. [wwise-events.md](wwise-events.md) lists the kinds. | During that kind of event. |
| `boss` | `chaos_spawn`, `chaos_beast_of_nurgle`, `chaos_plague_ogryn`, `chaos_ogryn_houndmaster`. With Boss Music for Captains on, also `renegade_captain`, `cultist_captain`, `renegade_twin_captain`, `renegade_twin_captain_two`. With Boss Music for Daemonhosts on, also `chaos_daemonhost`, `chaos_daemonhost_torment`, `chaos_mutator_daemonhost`. | While that boss is in the fight. With several, the one that came last. |
| `hub` | `mission_ready` | While your party is matchmaking, from choosing a mission until it starts. |
| `character_select` | `character_creation` | While you create a character. |
| `victory`, `defeat` | `game_score_win`, `game_score_lose` | Once the score screen opens. The parent folder then plays only the closing shot of the mission. |
| `mortis_trials_wave` | `horde_mode_wave`, `horde_mode_objective`, `horde_mode_wave_last`, `horde_mode_win` | During a wave, an objective round, the last wave, or the final win. |
| `expedition_combat` | `low_combat`, `med_combat`, `high_combat` | At that fight level, which follows how alert the enemy is. The level can change during a fight, which switches the song. |

## Which one plays

When several apply, the first one that has songs wins: the moment's name, then the mission's code, then the game mode. An override folder with no songs is skipped, so its parent folder, or the game's music, plays as before.

On the way into a mission, the mission's code and its game mode apply during the loading screens, the preparation screen, and the briefing. So `mission_briefing\mortis_trials\` plays during the Mortis Trials briefing. Havoc applies only once the mission has loaded, so a `havoc` folder does not apply on the preparation screen or during most of the briefing.

The music switches within half a second once another override applies, for example when the game names a boss a few seconds after the boss music started, or when an event moves on to its escape. A moment the game names by its screen, such as matchmaking, character creation, or the score screen, keeps its folder for 2 seconds after it ends, since the game passes through another state on the way out. With Debug Overlay on, its Folder line shows the folder that plays and the override names the moment looks for.
