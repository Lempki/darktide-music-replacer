# Settings

Every setting of Music Replacer, with its default. The settings are in the in-game mod options under Music Replacer, in ten groups, in the order the menu shows them.

## Your Songs

| Setting | Default | What it does |
|---|---|---|
| Rescan Audio Folders | (button) | Lists the audio folders again at once, and checks again whether every song plays. The mod notices added, removed, and replaced files by itself, and lists the folders again 3 seconds after files stop changing. Use this button on drives where Windows cannot report changes, such as some network drives, and to retry a song that would not play. It also lets the mod try playback again after it has given up, and creates any situation's folder that went missing. It does not measure songs again that were measured before, only those that could not be measured. |
| Restore Removed Songs | (button) | Puts every song that Remove from Rotation took out back into its folder's rotation, and a message says how many came back. A situation left with no songs plays them again at once. |

## Playback

| Setting | Default | What it does |
|---|---|---|
| Shuffle | On | Plays each folder's songs in a random order, each once before any song repeats. A new round never starts with the song that ended the last one. A folder's round lasts until the game closes, so a short visit to a situation does not start it over. Turned off, each folder plays in the order File Explorer sorts it by name, where `2.mp3` comes before `10.mp3`, and starts over after its last song. A folder continues after the song it played last. A change takes effect at the next song. |
| Repeat Song | Off | Loops the song playing now with no gap added between its end and its start, and every song that starts after it, in any situation. Next Song, Previous Song, and a new situation still change the song. A change takes effect on the song playing now. Turned on in a song's last 4 seconds, the song starts over once it ends, and loops from then on. Turned off at that point after the song has looped, it plays through once more. A folder's only song loops whether it is on or off. |
| Let Songs Finish | Off | When the music would switch to a situation that ranks the same or lower, such as from a fight back to explore, the song playing now plays to its end first, and then that situation takes over. A looping song plays to the end of the pass it is in. A switch to a situation that ranks higher still happens at once, and so does a switch to the game's music, to silence, or to a situation with no songs. If the song's own situation comes back before the song ends, the song plays on as before. Next Song ends the wait at once, and so does turning the setting off. The debug overlay's Waiting row shows the situation that waits, such as `explore after this song`. |
| Resume Songs | On | Explore, combat, Mortis Trials, and Expedition fight and safe room songs continue where they stopped when their music comes back. Horde, boss, and event songs also continue after an interruption by music that outranks them, such as a boss during a horde or a last stand during an event, as long as that horde, boss, or event lasts. A new horde, boss fight, or event gets a new pick. A song that stopped in its last 10 seconds is not continued, unless it loops. A new song is picked once one ends on its own. Every mission and hub visit starts with fresh songs. Within one situation, a song from an override folder also continues when the music switches back to that folder, such as an Operation's stage or an Expedition's fight level. |
| Fade Length | 2 seconds | How long the music crossfades when the situation changes, and how long a song fades out at its end, from 0 to 10 seconds. A song that does not loop starts its end fade that long before it ends. A song loops when it is alone in its folder or [Repeat Song](#playback) is on. A song shorter than two fades fades in over its first half and out over its second. A song that gives way to the game's music or to silence always fades out over half a second. Set it to 0 to switch at once. |

## Playback Controls

Keys that control the song playing now, and the setting that goes with them. Every key starts unbound. DMF runs keybinds even while you type in chat, so a key that is not a letter, such as one on the numpad or an F-key, works best. Each press shows a short message, see [On-Screen Messages](#on-screen-messages). A press while none of your songs plays, as in a situation set to Vanilla or Silence or with an empty folder, says so and changes nothing.

| Setting | Default | What it does |
|---|---|---|
| Next Song | Unbound | Crossfades to another song from the folder playing now, and the message names it. After Previous Song, with Shuffle on, it first returns to the songs Previous Song went back past. With one song in the folder, that song keeps playing, or resumes where it stopped while it is paused, and the message says it is the folder's only song, such as `Only song in Boss (chaos_spawn): x.mp3`. With no song left in the folder, such as after you delete its files while the game runs, the song playing now keeps playing, and the message says `No songs left in Hub`. It only changes the song of the situation playing now, so the next situation still starts its own pick, and the skipped song does not continue later. |
| Previous Song | Unbound | Within the first 3 seconds of a song, crossfades back to the song that played before it in this situation, and each further press goes back one more. With Shuffle off, it goes to the song before in name order instead, and from the folder's first song to its last. Later into a song, or with no earlier song, it starts the song playing now over. A new situation starts with no earlier songs, and so does a switch to an override folder, or a replay after a rescan or a changed setting. A song that could not play or that a rescan removed is passed over. |
| Restart Song | Unbound | Jumps back to the start of the song playing now. A song whose file you deleted or moved while it played keeps playing instead, and the message says so, such as `No longer in Hub: a.mp3`. Previous Song does the same when it would start such a song over. |
| Pause / Resume | Unbound | Pauses the song playing now, and the next press resumes it where it stopped. The game's music stays silent while it is paused, and the debug overlay's status reads `Custom, paused`. Next Song, Previous Song, Restart Song, and removing the song with Remove from Rotation also end the pause. A new situation ends it too, and the paused song continues later like any song that was playing. |
| Remove from Rotation | Unbound | Press it twice to stop the song playing now from ever being picked in its folder again, and move on to another song. The first press asks, and a second press removes the song while the question shows, through its fade in, the Message Duration, and the Message Fade Out. The same time counts with For Key Presses off, when no question shows. Both messages name the song and where it plays, such as `Hub`, or `Boss (chaos_spawn)` for an override folder. The file stays where it is, and a copy of the song in another folder still plays there. After a folder's last song, the situation plays as if the folder were empty. The removed songs are listed in `removed.txt`, see [Files the mod writes](troubleshooting.md#files-the-mod-writes). |
| Toggle Shuffle | Unbound | Turns [Shuffle](#playback) on or off, and the message says which. It works whatever plays, and the mod options keep the new choice. |
| Toggle Repeat Song | Unbound | Turns [Repeat Song](#playback) on or off, and the message says which. It works whatever plays, and the mod options keep the new choice. |
| Key Fade Length | 0.5 seconds | How long the music crossfades when one of these keys changes the song, pauses it, or resumes it, from 0 to 10 seconds. Fade Length still sets the fades when the situation changes and when a song ends by itself. A key that starts the song playing now over, as Restart Song does, jumps to its start in a tenth of a second, so two copies of the song never play over each other. While the song is paused, it fades in from its start over the Key Fade Length instead. Set it to 0 to switch at once. |

## Volume

| Setting | Default | What it does |
|---|---|---|
| Custom Music Volume | 100% | How loud your songs play, on top of the game's master and music volume sliders. At 100%, they play as loud as the files themselves. The game's music is not affected. |
| Menu Volume | 50% | How loud your songs play while a menu is open, as a share of the Custom Music Volume. The menus are the ones the game reports to its audio: the Esc menu and its settings, the inventory, the mission board, vendors, crafting, penances, the Havoc menu, the store, character appearance, and the score screen after a mission. The music fades down over half a second. It fades back up once no menu has been open for half a second, so moving between menus does not raise it. 100% keeps the music at full volume in menus. |
| Even Out Loudness | Off | Plays every song at about the same loudness, without changing your files. Each song is measured once in the background and remembered, starting with the folder that plays. A song not measured yet plays at its own level, and a song measured while it plays changes level at its next start. Loud songs are turned down. A quiet song is only raised as far as it can go without distorting, and a very quiet one only partway, since raising it further mostly raises its hiss. |

## On-Screen Messages

A message is one line of text on a backdrop in the corner of the screen that Message Corner sets. At offsets of 0 the backdrop touches the corner's two edges, and the text sits a few pixels inside it. It fades in over 0.4 seconds, stays for the Message Duration, and fades out over the Message Fade Out. A new message crossfades from the one showing over 0.3 seconds and then stays its own Message Duration, so pressing keys quickly never makes the text flicker. The same message again, such as a second Restart Song press's, keeps its line and stays another Message Duration. The messages are drawn in the game's always-visible layer, so they also show on loading screens and the mission briefing. With For Key Presses and For Song Changes both off, no message shows.

| Setting | Default | What it does |
|---|---|---|
| For Key Presses | On | Shows a message for each press of a Playback Controls key, such as `Next song: song.mp3`, and for each press of Restore Removed Songs. |
| For Song Changes | On | Shows `Now playing:` and the song's name whenever one of your songs starts by itself: when a situation starts its music, when a song ends and the next one plays, and when a song resumes where it stopped. A folder's only song that keeps playing into the next situation shows nothing. While For Key Presses is off, it also names the song that Next Song, Previous Song, or Remove from Rotation starts, since no key message names it then. |
| Message Duration | 4 seconds | How long a message stays at full opacity before it fades out, from 1 to 10 seconds. With Message Fade Out, it also sets how long a second press of Remove from Rotation counts. |
| Message Fade Out | 1 second | How long a message takes to fade out, from 0 to 3 seconds. Set it to 0 to hide a message at once. |
| Message Size | 100% | How big the messages are, from 50% to 200%, on top of the game's HUD Scale setting. |
| Message Color | Grey, 85% opacity | The messages' color, picked with DMF's color picker. Its alpha sets how opaque they are. |
| Message Backdrop Opacity | 70% | How dark the backdrop behind the messages is, from 0% to 100%. The backdrop is the same as the debug overlay's: a dark box behind the text that fades out toward the middle of the screen. It fades with the message, and during a crossfade it changes width smoothly from one message to the next. 0% leaves out the backdrop. |
| Message Corner | Bottom Left | The corner of the screen the messages show in: Bottom Left, Bottom Right, Top Left, or Top Right. They align to its side, so in a right corner they are right-aligned and grow to the left. |
| Message Offset X | 0 px | Moves the messages sideways, away from their corner toward the middle of the screen, from 0 to 10000. Type the exact number into the field. |
| Message Offset Y | 0 px | Moves the messages up or down, away from their corner toward the middle of the screen, from 0 to 10000. |

## Music per Situation

One dropdown per situation except Meat Grinder, which has a group of its own below, with the choices Custom, Vanilla, and Silence, and Skip for the mission situations that rank above another. Changing a choice to or from Skip applies at once, without the short wait a situation change takes. See [Choosing what plays](../README.md#choosing-what-plays) in the README for what each choice does.

## Meat Grinder

| Setting | Default | What it does |
|---|---|---|
| Music | Silence | What plays in the Meat Grinder training area: Silence, Meat Grinder Folder, One Situation, or Like a Mission. [Meat Grinder](../README.md#meat-grinder) in the README explains each one. |
| Situation | Explore | The situation One Situation plays, shown while One Situation is chosen. Every situation but Meat Grinder itself is offered. |

## Boss Music

| Setting | Default | What it does |
|---|---|---|
| Boss Music for Captains | Off | Plays your boss music while a captain is in the fight, from the moment it engages until it dies. Off leaves captains to the game's music. During an event, event music still plays. |
| Boss Music for Daemonhosts | Off | Plays your boss music while an angered daemonhost is alive. Off follows the game, which plays no music for daemonhosts. |

## Music Holds

Each hold goes from 0 to 30 seconds. Set one to 0 to follow the game exactly.

| Setting | Default | What it does |
|---|---|---|
| Combat Music Hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. It also covers Expedition Combat. |
| Horde Music Hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops that signal for a moment whenever few enemies are on you, so a short hold keeps the song from switching away and back. |
| Boss Music Hold | 3 seconds | How long boss music keeps playing after the game stops reporting a boss that is still alive. The game drops that signal for a moment now and then during a boss fight. Boss music still ends as soon as the boss dies. |
| Event Music Hold | 5 seconds | How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. |

## Debug

| Setting | Default | What it does |
|---|---|---|
| Detailed Logging | Off | Writes much more to `diagnostic.log`: every change in the game's music, each time the mod silences it, and the game's sound events. The important events are always logged, which is enough for most bug reports. The extra lines add up quickly, so turn this on only while tracking down a problem. |
| Debug Overlay | Off | Shows, in the top left corner of the screen, which situation the mod sees, the song playing, and how loud it plays. It shows on every screen, loading screens and the preparation screen included. It is useful for checking which music a moment counts as. |
| Overlay Size | 100% | How big the debug overlay is, from 50% to 200% on top of the game's HUD Scale setting, shown while the overlay is on. It grows and shrinks away from the corner. |
| Backdrop Opacity | 70% | How dark the backdrop behind the debug overlay is, from 0% to 100%, shown while the overlay is on. The text always stays fully visible, and 0% leaves out the backdrop. |

The debug overlay shows, from the top:

* **The situation,** by its name in the mod options, with a tag for what plays there. The tag is green for Custom, gold for Vanilla, and red for Silence. When the game's music plays for a reason, the tag says so, for example `Vanilla, no songs` or `Vanilla, its songs would not play`. It also names a skipped situation that is going on, such as `Custom, boss skipped`. While no situation applies, it names the reason instead, such as Cutscene or Mission Intro. Unknown Music State means the game reports a music state the mod does not know, and No situation covers everything else.
* **The folder** that plays, and the override names the moment looks for.
* **The song,** with a bar that shows how far it has played, and its time and length. While no song of yours plays, this line says what plays instead.
* **Level,** a meter that moves with the music as you hear it, so it also follows the volume sliders, fades, and the menu lowering. Beside it, the Menu marker lights up while a menu is open, and the Loudness marker while Even Out Loudness is on. With Even Out Loudness on, the song's level shows after them, such as `-6.1 dB`. A song not yet measured when it started shows `not measured` there instead. The row only shows while one of your songs plays.
* **Fade in** and **Fade out,** a bar and the level of each fade under way, with its seconds left. Fade in is the song playing now as it comes in, and Fade out names the song going out, with how many more fade out with it, such as `(+2 more)` after quick key presses. Both rows always show, and while nothing fades they are greyed out and say `none`. A crossfade fills both, a song's own end fade and a pause fill only Fade out, and a song starting from silence fills only Fade in. They follow whichever fade applies: Fade Length, Key Fade Length, or the short fade of a stop.
* **Waiting,** a bar and the seconds left of a hold, such as `combat hold 5.2s`, or of the short wait before the next situation's music starts, such as `explore in 0.4s`. With Let Songs Finish on, it also names the situation that waits for the song to end, such as `explore after this song`, and the bar shows how much of the song is left. While none of them counts down, it is greyed out and says `none`.
* **Measuring,** a bar and the count of songs Even Out Loudness has measured, such as `12 / 40`. While no songs are left to measure, it is greyed out and says `all measured`, or `off` while Even Out Loudness is off. It counts only the songs that need measuring, not those measured before.
