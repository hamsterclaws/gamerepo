-- Module returning starting items for weapons and armor.
-- Each entry may include an "img" path pointing at a PNG in ./assets
-- Add optional `scale` to affect the LARGE loot popup image size (not the list icon).

local M = {}

M.weapons = {
  { id = "stick",    name = "Stick",    atk = 2,  def = 0, desc = "+2 ATK",  img = "assets/items/stick.png",    scale = 1.0 },
  { id = "sword",    name = "Sword",    atk = 5,  def = 0, desc = "+5 ATK",  img = "assets/items/sword.png",    scale = 1.1 },
  { id = "scimitar", name = "Scimitar", atk = 5,  def = 0, desc = "+5 ATK",  img = "assets/items/scimitar.png", scale = 1.3 },
  { id = "axe",      name = "Axe",      atk = 15, def = 0, desc = "+5 ATK",  img = "assets/items/axe.png",      scale = 1.4 },
  { id = "woodClub",      name = "Wooden Club",      atk = 5, def = 0, desc = "+5 ATK",  img = "assets/items/woodclub.png",      scale = 1.4 },
}

M.armors = {
  { id = "cloth",  name = "Cloth",       atk = 0, def = 1, desc = "+1 DEF",            img = "assets/armor/cloth.png",  scale = 1.0 },
  { id = "chain",  name = "Chain",       atk = 0, def = 3, desc = "+3 DEF",            img = "assets/armor/chain.png",  scale = 1.1 },
  -- NOTE: ensure the path points to a PNG file in your assets; add ".png" if needed.
  { id = "Plain T-Shirt", name = "tshirt", atk = 1, def = 3, desc = "+1 ATK, +3 DEF", img = "assets/armor/tshirt.png", scale = 1.2 },
}

return M
