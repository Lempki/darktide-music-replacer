# Override folders

Override folders are optional and for advanced use. Your music works without them.

A folder can hold folders of its own, named after what the game reports, that take over from it while they apply. For example, songs in `boss\chaos_spawn\` play while a Chaos Spawn is the boss, songs in `victory\game_score_win\` play on the score screen after a win, and songs in `explore\expeditions\` play while you explore in an Expedition. When several apply, the first one in this order that has songs wins:

1. The moment, as the game names it:
   * In `event`, the kind of event, as the game names its event music: for example `escape_event`, `fortification_event`, `twins_event`, or an Operation's `operation_stage_1`. [wwise-events.md](wwise-events.md) lists the kinds.
   * In `boss`, the kind of boss: for example `chaos_spawn`, `chaos_beast_of_nurgle`, `chaos_plague_ogryn`, or `chaos_ogryn_houndmaster`, and with their settings on, `renegade_twin_captain` or `chaos_daemonhost`.
   * In `hub`, `mission_ready`, while your party is matchmaking, from choosing a mission until it starts.
   * In `character_select`, `character_creation`, while you create a character.
   * In `victory` and `defeat`, `game_score_win` and `game_score_lose`, the score screen after the mission.
   * In `mortis_trials_wave`, the kind of round: `horde_mode_wave`, `horde_mode_objective` for an objective round, `horde_mode_wave_last` for the last wave, or `horde_mode_win` for the final win.
   * In `expedition_combat`, the fight's level: `low_combat`, `med_combat`, or `high_combat`. The level follows how alert the enemy is and can change during a fight, which switches the song.
2. In any folder, the mission's code: for example `spillway` or `km_enforcer_twins`. [game-internals.md](game-internals.md) lists every mission's code with its in-game name.
3. In any folder, the game mode: `havoc`, `expeditions`, or `mortis_trials`.

On the way into a mission, the mission's code and its game mode apply during the loading screens, the preparation screen, and the briefing. So `mission_briefing\mortis_trials\` plays during the Mortis Trials briefing. Havoc applies only once the mission has loaded, so a `havoc` folder does not apply on the preparation screen or during most of the briefing.

An override folder with no songs is skipped, so its parent folder, or the game's music, plays as before. The mod does not create these folders, so make the ones you want. Their names are not case-sensitive, and folders inside an override folder are not read.

The music switches within half a second once another override applies, for example when the game names a boss a few seconds after the boss music started, or when an event moves on to its escape. A moment the game names by its screen, such as matchmaking, character creation, or the score screen, keeps its folder for 2 seconds after it ends, since the game passes through another state on the way out. With Debug Overlay on, its Folder line shows the folder that plays and the override names the moment looks for.
