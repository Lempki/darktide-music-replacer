# Settings

Every setting of Music Replacer, with its default. The settings are in the in-game mod options under Music Replacer, in six groups, in the order the menu shows them.

## Playback

| Setting | Default | What it does |
|---|---|---|
| Rescan Audio Folders | (button) | Lists the audio folders again at once, and checks every song again. The mod notices added, removed, and replaced files by itself. It lists the folders again 3 seconds after files stop changing. Use this button on drives where Windows cannot report changes, such as some network drives, and to try a song again that would not play. It also lets the mod try playback again after it gave up. It does not measure loudness again. |
| Resume Songs | On | Explore, combat, Mortis Trials, and Expedition fight and safe room songs continue where they stopped when their music comes back. Horde, boss, and event songs continue too after music that outranks them interrupts them, such as a boss during a horde or a last stand during an event, while that horde, fight, or event lasts. A new horde, boss fight, or event gets a new pick. A song that stopped in its last 10 seconds is not continued. A new song is picked once one ends on its own. Every mission and hub visit starts with fresh songs. |

## Music per Situation

One dropdown per situation, with the choices Custom, Vanilla, and Silence. See [Choosing what plays](../README.md#choosing-what-plays) in the README for what each choice does.

## Volume

| Setting | Default | What it does |
|---|---|---|
| Custom Music Volume | 100% | How loud your songs play, on top of the game's master and music volume sliders. At 100%, they play as loud as the files themselves. The game's music is not affected. |
| Menu Volume | 50% | How loud your songs play while a menu is open, as a share of the Custom Music Volume. The menus are the ones the game reports to its audio: the Esc menu and its settings, the inventory, the mission board, vendors, the store, and character appearance. The music fades down over half a second. It fades back up once no menu has been open for half a second, so moving between menus does not raise it. 100% keeps the music at full volume in menus. |
| Even Out Loudness | Off | Plays every song at about the same loudness, without changing your files. Each song is measured once in the background and remembered, starting with the folder that plays. A song not measured yet plays at its own level, and a song measured while it plays changes level at its next start. Loud songs are turned down. A quiet song is only raised as far as it can go without distorting, and a very quiet one only partway, since raising it further mostly raises its hiss. |

## Boss Music

| Setting | Default | What it does |
|---|---|---|
| Boss Music for Captains | Off | Plays your boss music while a captain is in the fight, from the moment it engages until it dies. Off leaves captains to the game's music. During an event, event music still plays. |
| Boss Music for Daemonhosts | Off | Plays your boss music while an angered daemonhost is alive. Off follows the game, which plays no music for daemonhosts. |

## Music Holds

Each hold goes from 0 to 30 seconds. Set one to 0 to follow the game exactly.

| Setting | Default | What it does |
|---|---|---|
| Combat Music Hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. |
| Horde Music Hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops that signal for a moment whenever few enemies are on you, so a short hold keeps the song from switching away and back. |
| Boss Music Hold | 3 seconds | How long boss music keeps playing after the game stops reporting a boss that is still alive. The game drops that signal for a moment now and then during a boss fight. Boss music still ends as soon as the boss dies. |
| Event Music Hold | 5 seconds | How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. |

## Debug

| Setting | Default | What it does |
|---|---|---|
| Detailed Logging | Off | Writes much more to `diagnostic.log`: every change in the game's music, each time the mod silences it, and the game's sound events. The important events are always logged, which is enough for most bug reports. The extra lines add up quickly, so turn this on only while tracking down a problem. |
| Debug Overlay | Off | Shows which situation the mod sees, the song playing, and how loud it plays in the top left corner of the screen. It shows on every screen, loading screens and the preparation screen included. It is useful for checking which music a moment counts as. |
| Overlay Size | 100% | How big the debug overlay is, from 50% to 200%, shown while the overlay is on. It grows and shrinks away from the corner. |
| Backdrop Opacity | 70% | How dark the backdrop behind the debug overlay is, from 0% to 100%, shown while the overlay is on. The text always stays fully visible, and 0% leaves out the backdrop. |

The debug overlay shows, from the top:

* **The situation,** by its name in Music per Situation, with a tag for what plays there. The tag is green for Custom, gold for Vanilla, and red for Silence. When the game's music plays for a reason, the tag says so, for example `Vanilla, no songs` or `Vanilla, its songs would not play`.
* **The folder** that plays, and the override names the moment looks for.
* **The song,** with a bar that shows how far into it the song is, and its time and length. While no song of yours plays, this line says what plays instead.
* **Level,** a meter that moves with the music as you hear it, so it also follows the volume sliders, fades, and the menu lowering. Beside it, the Menu marker lights up while a menu is open, and the Loudness marker while Even Out Loudness is on. With Even Out Loudness on, the song's level shows after them, such as `-6.1 dB`. The row only shows while one of your songs plays.
* **Waiting,** a bar and the seconds left of a hold or a change that is still settling. It appears only while one of them is counting down.
