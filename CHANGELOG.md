# Changelog

## [Unreleased]

### Changed

* Licensed GPL-2.0-or-later instead of MIT. GrogVM, the SCUMM machine it runs on, stays
  MIT.
* The picture is drawn at twice the game's 320×200 and the terminal scales it to the
  window (`native:2,swap`); `--picture` (or `CAULDRON_PICTURE`) chooses otherwise.

### Added

* `--mute` (or `CAULDRON_MUTE=1`): no sound.


### Changed

* `mix monkey_xland` refuses a directory without the Special Edition's `Monkey1.pak`,
  `audio/MusicOriginal.xwb`, `audio/SFXOriginal.xwb`, `audio/Speech.xwb` and
  `audio/speech.info`, naming the files missing (`Install.load/1` returns
  `{:error, {:not_installed, missing}}`).
* `World` groups the walk-box state as `boxes` (`flags`, `scales`, `routes`,
  `scale_slots`, `drawn`), the transition as `effect` (`kind`, `pending`), and keeps
  the shake in `screen` (`MonkeyXland.Shake`). Saves are version 3; earlier saves are
  not read.
* Hex package metadata: the GitHub link and the packaged files; the libraries are the
  sibling checkouts when present, else their Hex releases (`PLUMB_HEX` forces Hex).
  `gamepad` comes through `cauldron_2d_drafter`.

### Added

* The Secret of Monkey Island played from the owner's Special Edition install in the
  terminal: rooms, objects, actors and costumes, walking, verbs and sentences, text and
  the voices, the CD music, sound effects and Roland music, palette cycling, the camera,
  cutscenes and skipping them, the screen shaking, and saving and loading.
