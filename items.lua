-- items.lua
-- Module returning starting items for weapons and armor.
-- Each entry may include an "img" path pointing at a PNG in ./assets

local M = {}

M.weapons = {
  { id = "stick", name = "Stick", atk = 2, def = 0, desc = "+2 ATK", img = "assets/items/stick.png" },
  { id = "sword", name = "Sword", atk = 5, def = 0, desc = "+5 ATK", img = "assets/items/sword.png" },
  { id = "scimitar", name = "Scimitar", atk = 5, def = 0, desc = "+5 ATK", img = "assets/items/scimitar.png" },
  { id = "axe", name = "Axe", atk = 15, def = 0, desc = "+5 ATK", img = "assets/items/axe.png" },
}

M.armors = {
  { id = "cloth", name = "Cloth", atk = 0, def = 1, desc = "+1 DEF", img = "assets/armor/cloth.png" },
  { id = "chain", name = "Chain", atk = 0, def = 3, desc = "+3 DEF", img = "assets/armor/chain.png" },
}

return M