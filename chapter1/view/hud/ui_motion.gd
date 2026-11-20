extends RefCounted
## One table of motion lengths for every screen (A10 1.10), in seconds. A screen reads these; it does not write its own.
## Moved here from the grace screen (grace_parts.gd INTRO_*, growth_choice.gd LOCK). Presentation only.

## ---- Scene (full-screen) ----
const SCENE_IN := 0.45             ## the normal intro of a scene (the cards can be picked after this)
const SCENE_IN_LONG := 1.8         ## the first grace of a run, the first screen
const SCENE_IN_LONG_MIN := 1.6
const SCENE_IN_LONG_MAX := 1.9
const SCENE_IN_JACKPOT_MAX := 2.0  ## a jackpot reveal: 2.0 or less
const SCENE_OUT := 0.46            ## the pick: press 0.06, fly 0.30, the rest falls away; one cut at the end (grace confirm_len)

## ---- Window ----
const WINDOW_IN := 0.18            ## alpha 0 -> 1, height 0.97 -> 1.00
const WINDOW_OUT := 0.12

## ---- Reactions ----
const FOCUS := 0.08                ## focus: 1.03 x and brightness
const PRESS := 0.06                ## press: 6 px
const FLY := 0.30                  ## a chosen thing flies and is set into its slot (grace pick, gear equip)
const PICK_LOCK := 0.25            ## after a scene settles, a pick is refused for this long (Input48; Space is never a confirm key)

## ---- Notices ----
const NOTICE_IN := 0.18
const NOTICE_HOLD_BAND := 2.5
const NOTICE_HOLD_CARD := 3.2
const NOTICE_HOLD_CARD_BEST := 9.0
const NOTICE_OUT := 0.4
const BIG_BAND_IN := 0.25
const BIG_BAND_HOLD := 1.6
const BIG_BAND_OUT := 0.3
