extends RefCounted

## The charm's number and what holding it is worth. The item row, the roll
## policy and the gift all name these.

## Past `Gen2ContentOverlay.FIRST_MOD_NUMBER`, and one above the LINKING CORD's
## 256: the overlay refuses two mods claiming one number, and both are ours.
const NUMBER: int = 257

## Three rolls at the DV word, keeping the first shiny one, which is what the
## later games' charm does.
const ROLLS: int = 3

## What a wild rolls without it, and what a host with no policy registered does.
const VANILLA_ROLLS: int = 1

## Two lines at the eighteen characters the description box draws, hyphenated
## across the break like `EGG TICKET` and `SILVER WING`.
const DESCRIPTION: String = "Makes shiny POKé-\nMON appear more."
