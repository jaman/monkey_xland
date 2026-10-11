# MonkeyXland

The Secret of Monkey Island, played in your terminal from your own copy of the game: the
original VGA graphics, the CD music, and the Special Edition's voices.

No game files are included. You need *The Secret of Monkey Island: Special Edition*
installed (Steam or GOG); MonkeyXland reads the original game out of it.

## Playing

```sh
mix deps.get
mix monkey_xland --game "path/to/The Secret of Monkey Island Special Edition"
```

`--game` is the directory holding `Monkey1.pak` and `audio/`. You can set
`MONKEYXLAND_GAME` to it instead.

The picture is best in a terminal that shows images (kitty, WezTerm, iTerm2, or any with
sixel); other terminals show it in block characters. Terminals that report the mouse in
pixels (kitty, WezTerm, foot, recent iTerm2) point to the exact pixel.

On a terminal that keeps images (kitty, Ghostty, WezTerm, iTerm2) the picture is drawn
at twice the game's 320×200 and the terminal scales it to the window, so a small font gives more
room without a blurrier picture. `--picture` (or `CAULDRON_PICTURE`, or
`config :cauldron_2d_drafter, picture: "..."` in a `config/runtime.exs`) chooses
otherwise, with any of these comma separated: `native` draws at the game's own size times
the largest whole number that fits the window, `native:N` at `N` times, `size:WxH`
sets the size itself, `png` sends each frame as a PNG (about a third smaller, for play
over ssh, at more CPU), `swap` replaces each frame without a blank between, and `none`
draws at the window's cells instead. The default is `native:2,swap`.

## Controls

| | |
|---|---|
| left button | do what the chosen verb says (walk, at first) |
| right button | do what the thing under the pointer suggests |
| verb letters | choose a verb |
| `.` | skip the line being said |
| `Escape` | skip a cutscene |
| `F10` | menu: resume, save, load, restart, quit |

Games are saved in nine slots in your user data directory under `monkey_xland`.

## Sound

* The CD music and the voices play from your install. Most music tracks are xWMA, decoded
  by `tuning_fork_wma` (LGPL-2.1-or-later, a dependency). Remove that dependency and they
  are decoded by `ffmpeg` on your `PATH` instead; with neither, they are silent.
* A few sounds were written for a Roland MT-32. Set `MUNT_LOCATION` to a directory with
  your own [Munt](https://github.com/munt/munt) library and MT-32 ROMs to hear them as
  written; otherwise they play through General MIDI.
