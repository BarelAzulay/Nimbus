-- StoreController (client; lobby-shop Task 21, spec 16.3 "Who owns it"): a thin forwarder kept for old callers (the top
-- bar's PillButton_Shop, tests). The Robux Store moved into the one Shop window, client/Controllers/ShopController;
-- every call here goes there.
--
--   StoreController.Init()          nothing (ShopController boots on its own)
--   StoreController.Open(args) -> bool, Close(), IsOpen() -> bool, Cards(), Palette(key), RobuxGlyph(), Portrait()
--   StoreController.Layout() -> "PC" | "Phone"   (the Shop's Compact counts as PC, its Portrait as Phone: the Store's words)
--
-- Plain Lua 5.1-compatible syntax only.

local StoreController = {}

local function shop()
	return require(script.Parent:WaitForChild("ShopController"))
end

function StoreController.Init() end

function StoreController.Open(args)
	return shop().Open(args)
end

function StoreController.Close()
	return shop().Close()
end

function StoreController.IsOpen()
	return shop().IsOpen()
end

function StoreController.Cards()
	return shop().Cards()
end

function StoreController.Palette(key)
	return shop().Palette(key)
end

function StoreController.RobuxGlyph()
	return shop().RobuxGlyph()
end

function StoreController.Portrait()
	return shop().Portrait()
end

function StoreController.Layout()
	local layout = shop().Layout()
	if layout == "Compact" then
		return "PC"
	elseif layout == "Portrait" then
		return "Phone"
	end
	return layout
end

return StoreController
