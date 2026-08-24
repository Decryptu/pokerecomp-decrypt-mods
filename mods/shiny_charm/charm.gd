extends RefCounted

## The charm's number and what holding it is worth. One file owns both facts,
## because the item row, the roll policy and the gift all name them.

## Past `Gen2ContentOverlay.FIRST_MOD_NUMBER`, and one above the LINKING CORD's
## 256, because two mods claiming one item number is refused by the overlay and
## both of those mods are ours.
const NUMBER: int = 257

## Three rolls at the DV word, the first shiny one kept. That is the later
## games' own charm rather than a multiplier invented here, and over the
## hardware's 1-in-8192 it lands within a hundredth of a percent of three times
## the chance: the odds are small enough that three tries barely overlap.
const ROLLS: int = 3

## What every wild rolls without it, which is also what a host with no policy
## registered does.
const VANILLA_ROLLS: int = 1

## `pack.asm`'s own two lines for a key item, at the eighteen characters the
## description box draws, hyphenated across the break the way `EGG TICKET` and
## `SILVER WING` are.
const DESCRIPTION: String = "Makes shiny POKé-\nMON appear more."
