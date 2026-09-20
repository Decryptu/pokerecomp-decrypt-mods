extends RefCounted

## Which generation's profile a cartridge takes. Tileset numbers overlap between
## the two, so every tileset-keyed table lives under `gen1/` or `gen2/`.

const GEN1: GDScript = preload("gen1/profile.gd")
const GEN2: GDScript = preload("gen2/profile.gd")


static func of(data: GameData) -> GDScript:
	return GEN1 if data != null and data.generation == RomRegistry.GEN1 else GEN2


static func of_generation(generation: int) -> GDScript:
	return GEN1 if generation == RomRegistry.GEN1 else GEN2
