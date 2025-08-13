-- magic.lua
-- Spells scale from totalMAG() (player base + gear magic).
-- power is a multiplier.
local magic = {
  { key="fire_bolt", name="Fire Bolt", desc="Quick flame burst.", power=1.20 },
  { key="ice_shard", name="Ice Shard", desc="Chilling shard.",   power=1.10 },
  { key="arc_blast", name="Arc Blast", desc="Crackling energy.", power=1.40 },
}
return magic
