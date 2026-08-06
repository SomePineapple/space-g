class_name ShipDebris
extends DriftingHexPiece

## Cosmetic-only wreckage: a hex module severed from its parent ship's
## connectivity graph (see HullDamageModel._detach_module). Drifts under its own
## momentum, has no collision, and fades out before freeing itself — all of
## which is DriftingHexPiece's behavior unchanged. This subclass exists only
## to name that case and to carry the shorter default lifetime; a piece worth
## recovering is a CapturedTechPart instead.
