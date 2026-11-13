-- smoke_kitb_ui.lua: the kit-b UI lane (U1-U9 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-ui). Loaded by
-- tools/smoke.py in both worlds, ARGS.context picks the half. Each wave adds its scenarios here and their names on the
-- UI line of tools/smoke.py (that line only).
--   U1 (Theme: roles, stroke rule, tokens; fonts audit F1, F2, F5, F6, F11, F12, rejects audit 8; the owner: "all fonts in
--   the game and gui ... cool unique style and fonts, good looking gui matching what we pitched"):
--   theme_roles_kitb          (server world, pure) the pitch's role map: Title / Sign / Accent LuckiestGuy; Heading / Button /
--                             Tag / Nameplate / Display FredokaOne; Body / Label / Toast Nunito ExtraBold through
--                             Theme.Faces; Script Nunito Bold Italic; Signature PermanentMarker; GothamBlack and Fondamento
--                             gone from every role; a default size for the new roles
--   theme_style_no_default_stroke (server world, pure) Theme.Style / Theme.Label give no classic stroke and no outline
--                             unless asked, for every role; a FontFace role gets its face; a numeric Outline is one
--                             UIStroke with no classic stroke under it
--   theme_world_outline_single (server world, pure) Outline = "World" (text over the 3D world, no plate): one Contextual
--                             UIStroke and no classic stroke, even when the caller also passes a Stroke
--   theme_setrole_and_measure (server world, pure) Theme.SetRole(obj, role) swaps only the face (the last face written wins,
--                             as in Roblox); Theme.Measure(text, role, size[, width]) = TextService:GetTextSize with the
--                             role's Enum font, widened by the role's spare factor (TextService does not know FontFace)
--   theme_texton              (server world, pure) Theme.TextOn(surface): brown #3B2412 on stone (and any light fill),
--                             white on navy and on today's dark panels; Theme.Sign = the pitch palette (decision 5);
--                             Theme.Radius = { None = 0, S = 4, M = 8 } and Theme.Corner takes a token name
--   kitb_text_stroke_or_panel (client) a walk over every text object in PlayerGui after the client run: labels with both a
--                             classic stroke and an outline, and outlined labels on an opaque panel. U1 reports the counts
--                             as a warning; U6 drives them to zero and makes this a failure
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format

local function hex(c)
	if typeof(c) ~= "Color3" then
		return tostring(c)
	end
	return fmt("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function sameColor(a, b)
	return typeof(a) == "Color3" and typeof(b) == "Color3" and hex(a) == hex(b)
end

-- the outline Theme.TextOutline puts on a text object (Contextual UIStrokes only; a Border stroke outlines the box)
local function textStrokes(obj)
	local out = {}
	for _, c in ipairs(obj:GetChildren()) do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and c.Enabled ~= false and (tonumber(c.Thickness) or 0) > 0 and (tonumber(c.Transparency) or 0) < 0.95 then
			out[#out + 1] = c
		end
	end
	return out
end

local function serverScenarios()
	local S = {}
	local K = _G.K

	local function theme()
		local inst = K.moduleInstance("shared/Theme")
		local ok, Theme = false, nil
		if inst then
			ok, Theme = pcall(require, inst)
		end
		if not T.check(ok and type(Theme) == "table", "kitb ui: shared/Theme loads", tostring(Theme)) then
			return nil
		end
		return Theme
	end

	local function faceIs(f, family, weight, style)
		return typeof(f) == "Font" and tostring(f.Family):find("families/" .. family .. "%.json") ~= nil and f.Weight == Enum.FontWeight[weight] and f.Style == Enum.FontStyle[style]
	end

	local function faceText(f)
		if typeof(f) ~= "Font" then
			return tostring(f)
		end
		return tostring(f.Family) .. " " .. tostring(f.Weight) .. " " .. tostring(f.Style)
	end

	S.theme_roles_kitb = guarded("theme_roles_kitb", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local F = Theme.Fonts
		local want = {
			Title = "LuckiestGuy", Sign = "LuckiestGuy", Accent = "LuckiestGuy",
			Heading = "FredokaOne", Button = "FredokaOne", Tag = "FredokaOne", Nameplate = "FredokaOne", Display = "FredokaOne",
			Signature = "PermanentMarker",
		}
		for role, name in pairs(want) do
			T.check(F[role] == Enum.Font[name], "kitb roles: Theme.Fonts." .. role .. " = " .. name, tostring(F[role]))
		end
		local gone = {}
		for role, f in pairs(F) do
			if f == Enum.Font.GothamBlack or f == Enum.Font.Fondamento then
				gone[#gone + 1] = role .. " = " .. tostring(f)
			end
		end
		table.sort(gone)
		T.check(#gone == 0, "kitb roles: no role is GothamBlack or Fondamento any more", table.concat(gone, ", "))
		local Fa = Theme.Faces or {}
		for _, role in ipairs({ "Body", "Label", "Toast" }) do
			T.check(faceIs(Fa[role], "Nunito", "ExtraBold", "Normal"), "kitb roles: Theme.Faces." .. role .. " = Nunito ExtraBold", faceText(Fa[role]))
			T.check(F[role] ~= nil, "kitb roles: " .. role .. " keeps an Enum fallback font (engines without Font.new)", tostring(F[role]))
		end
		T.check(faceIs(Fa.Script, "Nunito", "Bold", "Italic"), "kitb roles: Theme.Faces.Script = Nunito Bold Italic (Fondamento retired)", faceText(Fa.Script))
		T.check(faceIs(Fa.Thanks, "Nunito", "Bold", "Italic") and faceIs(Fa.Caps, "Nunito", "Heavy", "Normal"), "kitb roles: the credits faces (Caps, Thanks) are kept")
		for _, role in ipairs({ "Title", "Heading", "Button", "Tag", "Nameplate", "Accent", "Sign", "Signature", "Display" }) do
			T.check(Fa[role] == nil, "kitb roles: " .. role .. " has no FontFace (one weight; the Enum font is the face)", faceText(Fa[role]))
		end
		for _, role in ipairs({ "Tag", "Nameplate" }) do
			local px = Theme.Sizes and Theme.Sizes[role]
			T.check(type(px) == "number" and px >= Theme.Readability.Caption, "kitb roles: Theme.Sizes." .. role .. " >= the caption floor", tostring(px))
		end
		K.flushErrors("theme_roles_kitb")
	end)

	S.theme_style_no_default_stroke = guarded("theme_style_no_default_stroke", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local stroked, outlined, faceless = {}, {}, {}
		for role in pairs(Theme.Fonts) do
			local label = Theme.Label("Kit B", role)
			if label.TextStrokeTransparency < 1 then
				stroked[#stroked + 1] = role .. " " .. tostring(label.TextStrokeTransparency)
			end
			if #textStrokes(label) > 0 or label:FindFirstChild("TextOutline") then
				outlined[#outlined + 1] = role
			end
			local f = Theme.Faces[role]
			if f and Mock.FontOf and Mock.FontOf(label) ~= f then
				faceless[#faceless + 1] = role
			end
			label:Destroy()
		end
		table.sort(stroked)
		table.sort(outlined)
		table.sort(faceless)
		T.check(#stroked == 0, "kitb stroke: Theme.Label gives no classic text stroke by default (every role)", table.concat(stroked, ", "))
		T.check(#outlined == 0, "kitb stroke: Theme.Label gives no outline by default (every role)", table.concat(outlined, ", "))
		T.check(#faceless == 0, "kitb stroke: a FontFace role ends on its face (written after .Font)", table.concat(faceless, ", "))
		local body = Theme.Label("Body copy", "Body")
		T.check(body.FontFace == Theme.Faces.Body and body.Font == Theme.Fonts.Body, "kitb stroke: a Body label carries the Enum fallback and then the Nunito ExtraBold face")
		body:Destroy()
		local onLight = Theme.Label("Dark on pale", "Body", { OnLight = true })
		T.check(onLight.TextStrokeTransparency == 1, "kitb stroke: OnLight no longer adds a stroke (contrast comes from Theme.TextOn)", tostring(onLight.TextStrokeTransparency))
		onLight:Destroy()
		local asked = Theme.Label("Asked for", "Body", { Stroke = 0.3 })
		T.check(math.abs(asked.TextStrokeTransparency - 0.3) < 1e-6, "kitb stroke: an explicit Stroke is still honoured (U6 removes the callers)", tostring(asked.TextStrokeTransparency))
		asked:Destroy()
		local ringed = Theme.Label("Outlined", "Heading", { Outline = 2 })
		local rings = textStrokes(ringed)
		T.check(#rings == 1 and rings[1].Thickness == 2 and ringed.TextStrokeTransparency == 1, "kitb stroke: Outline = 2 is one 2 px UIStroke and no classic stroke under it", #rings .. " strokes, classic " .. tostring(ringed.TextStrokeTransparency))
		ringed:Destroy()
		K.flushErrors("theme_style_no_default_stroke")
	end)

	S.theme_world_outline_single = guarded("theme_world_outline_single", function()
		local Theme = theme()
		if not Theme then
			return
		end
		for _, case in ipairs({
			{ "Accent", nil },
			{ "Nameplate", nil },
			{ "Body", 0 },
			{ "Accent", 0.1 },
		}) do
			local role, stroke = case[1], case[2]
			local label = Theme.Label("123", role, { Outline = "World", Stroke = stroke })
			local rings = textStrokes(label)
			local what = role .. (stroke and (" + Stroke " .. stroke) or "")
			T.check(#rings == 1, "kitb world: Outline = 'World' on " .. what .. " is exactly one Contextual UIStroke", #rings .. " strokes")
			T.check(label.TextStrokeTransparency == 1, "kitb world: ... and no classic stroke under it (" .. what .. ")", tostring(label.TextStrokeTransparency))
			T.check(rings[1] ~= nil and rings[1].Thickness >= 2 and rings[1].Thickness <= 3, "kitb world: ... 2-3 px thick (" .. what .. ")", rings[1] and tostring(rings[1].Thickness) or "none")
			label:Destroy()
		end
		local thick = Theme.Label("999", "Accent", { Outline = "World", OutlineThickness = 3, OutlineColor = Color3.fromRGB(90, 20, 20) })
		local ring = textStrokes(thick)[1]
		T.check(ring and ring.Thickness == 3 and sameColor(ring.Color, Color3.fromRGB(90, 20, 20)), "kitb world: OutlineThickness / OutlineColor set the one outline", ring and (tostring(ring.Thickness) .. " " .. hex(ring.Color)) or "none")
		-- styling the same label again does not add a second ring
		Theme.Style(thick, "Accent", { Outline = "World" })
		T.check(#textStrokes(thick) == 1, "kitb world: re-styling reuses the one outline", tostring(#textStrokes(thick)))
		thick:Destroy()
		K.flushErrors("theme_world_outline_single")
	end)

	S.theme_setrole_and_measure = guarded("theme_setrole_and_measure", function()
		local Theme = theme()
		if not Theme then
			return
		end
		if not T.check(type(Theme.SetRole) == "function" and type(Theme.Measure) == "function", "kitb setrole: Theme.SetRole and Theme.Measure exist") then
			return
		end
		local label = Instance.new("TextLabel")
		label.TextColor3 = Color3.fromRGB(200, 10, 10)
		label.TextSize = 31
		label.TextStrokeTransparency = 0.7
		T.check(Theme.SetRole(label, "Body") == label, "kitb setrole: SetRole returns the object")
		T.check(label.Font == Theme.Fonts.Body and label.FontFace == Theme.Faces.Body, "kitb setrole: SetRole(Body) = the Enum fallback, then the Nunito face")
		T.check(sameColor(label.TextColor3, Color3.fromRGB(200, 10, 10)) and label.TextSize == 31 and math.abs(label.TextStrokeTransparency - 0.7) < 1e-6, "kitb setrole: SetRole leaves colour, size and stroke alone")
		Theme.SetRole(label, "Title")
		T.check(label.Font == Theme.Fonts.Title and (not Mock.FontOf or Mock.FontOf(label) == Theme.Fonts.Title), "kitb setrole: SetRole(Title) after Body: the Title font is the last face written", tostring(Mock.FontOf and Mock.FontOf(label)))
		Theme.SetRole(label, "NoSuchRole")
		T.check(label.Font == Theme.Fonts.Body, "kitb setrole: an unknown role is Body")
		T.check(Theme.SetRole(nil, "Body") == nil, "kitb setrole: SetRole(nil) is a no-op")
		label:Destroy()

		local TS = game:GetService("TextService")
		local raw = TS:GetTextSize("Nimbus Climb", 20, Theme.Fonts.Body, Vector2.new(100000, 100000))
		local m = Theme.Measure("Nimbus Climb", "Body", 20)
		T.check(typeof(m) == "Vector2" and m.X >= raw.X and m.Y == raw.Y, "kitb measure: Measure(Body) is GetTextSize widened by the spare factor", tostring(m) .. " vs " .. tostring(raw))
		local spare = Theme.MeasureSpare and Theme.MeasureSpare.Body or 1
		T.check(math.abs(m.X - math.ceil(raw.X * spare)) < 1e-6, "kitb measure: ... X = ceil(GetTextSize.X x MeasureSpare.Body)", fmt("%.2f vs %.2f x %.3f", m.X, raw.X, spare))
		for role, k in pairs(Theme.MeasureSpare or {}) do
			T.check(type(k) == "number" and k >= 1 and k <= 1.4, "kitb measure: MeasureSpare." .. role .. " in 1..1.4", tostring(k))
		end
		local m2 = Theme.Measure("Nimbus Climb", "Body", 40)
		T.check(m2.X >= m.X * 1.9 and m2.Y >= m.Y * 1.9, "kitb measure: twice the size measures about twice as big", tostring(m2) .. " vs " .. tostring(m))
		local short, long = Theme.Measure("Hi", "Title", 30), Theme.Measure("Hello there friend", "Title", 30)
		T.check(long.X > short.X, "kitb measure: longer text measures wider")
		T.check(Theme.Measure("", "Body", 20).X == 0, "kitb measure: empty text is 0 wide")
		local unknown = Theme.Measure("Nimbus Climb", "NoSuchRole", 20)
		T.check(unknown.X == m.X, "kitb measure: an unknown role measures as Body")
		local wrapped = Theme.Measure("Nimbus Climb", "Body", 20, 50)
		T.check(typeof(wrapped) == "Vector2", "kitb measure: a wrap width is passed through")
		K.flushErrors("theme_setrole_and_measure")
	end)

	S.theme_texton = guarded("theme_texton", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local Sg = Theme.Sign
		if not T.check(type(Sg) == "table", "kitb texton: Theme.Sign is a table") then
			return
		end
		local pitch = {
			Stone = "#FFF7E6", StoneLip = "#DCC9A0", Wood = "#8C5A2E", Navy = "#232A6E", Gold = "#FFD24A", Roof = "#EE6FA6",
			Grass = "#6FCF6A", Red = "#EE6A7F", Text = "#3B2412",
		}
		for key, want in pairs(pitch) do
			T.check(hex(Sg[key]) == want, "kitb texton: Theme.Sign." .. key .. " = " .. want, hex(Sg[key]))
		end
		if not T.check(type(Theme.TextOn) == "function", "kitb texton: Theme.TextOn exists") then
			return
		end
		local brown, white = "#3B2412", "#FFFFFF"
		T.check(hex(Theme.TextOn("Stone")) == brown, "kitb texton: brown on stone", hex(Theme.TextOn("Stone")))
		T.check(hex(Theme.TextOn("StoneLip")) == brown and hex(Theme.TextOn("Gold")) == brown, "kitb texton: brown on the stone lip and on gold")
		T.check(hex(Theme.TextOn("Navy")) == white, "kitb texton: white on navy", hex(Theme.TextOn("Navy")))
		T.check(hex(Theme.TextOn("Wood")) == white, "kitb texton: white on wood", hex(Theme.TextOn("Wood")))
		T.check(hex(Theme.TextOn("Panel")) == white and hex(Theme.TextOn("Dark")) == white, "kitb texton: white on today's dark panels")
		T.check(hex(Theme.TextOn(Theme.Colors.PanelTop)) == white and hex(Theme.TextOn(Color3.fromRGB(250, 248, 240))) == brown, "kitb texton: a Color3 surface picks by contrast")
		T.check(hex(Theme.TextOn(nil)) == white and hex(Theme.TextOn("nope")) == white, "kitb texton: nil / unknown = white (today's dark panels)")
		local R = Theme.Radius
		T.check(type(R) == "table" and R.None == 0 and R.S == 4 and R.M == 8, "kitb texton: Theme.Radius = { None = 0, S = 4, M = 8 }")
		local f = Instance.new("Frame")
		local c = Theme.Corner(f, "M")
		T.check(c and c.CornerRadius.Offset == 8 and c.CornerRadius.Scale == 0, "kitb texton: Theme.Corner(obj, 'M') = 8 px", c and tostring(c.CornerRadius) or "nil")
		local c2 = Theme.Corner(f, 4)
		T.check(c2 and c2.CornerRadius.Offset == 4, "kitb texton: Theme.Corner(obj, 4) = 4 px")
		local c3 = Theme.Corner(f, UDim.new(0, 12))
		T.check(c3 and c3.CornerRadius.Offset == 12, "kitb texton: Theme.Corner(obj, UDim) unchanged")
		f:Destroy()
		K.flushErrors("theme_texton")
	end)

	return S
end

local function clientScenarios()
	local S = {}

	S.kitb_text_stroke_or_panel = guarded("kitb_text_stroke_or_panel", function()
		local Players = game:GetService("Players")
		local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(pg ~= nil, "kitb stroke walk: PlayerGui exists") then
			return
		end
		local function shown(t)
			return tostring(t or ""):gsub("%s", "") ~= ""
		end
		-- the nearest GuiObject (the label itself first) that paints a background: is it opaque?
		local function onPanel(obj)
			local o = obj
			while o and not o:IsA("LayerCollector") do
				if o:IsA("GuiObject") then
					local bt = tonumber(o.BackgroundTransparency) or 1
					if bt < 0.99 then
						return bt < 0.3, o
					end
				end
				o = o.Parent
			end
			return false, nil
		end
		local total, doubled, panelled = 0, {}, {}
		for _, d in ipairs(pg:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and shown(d.Text) then
				total = total + 1
				local classic = (tonumber(d.TextStrokeTransparency) or 1) < 0.95
				local ring = #textStrokes(d) > 0
				local path = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
				if classic and ring then
					doubled[#doubled + 1] = path
				end
				if classic or ring then
					local opaque, panel = onPanel(d)
					if opaque then
						panelled[#panelled + 1] = path .. (panel ~= d and (" on " .. panel.Name) or " (own fill)")
					end
				end
			end
		end
		table.sort(doubled)
		table.sort(panelled)
		T.check(total > 0, "kitb stroke walk: the client run left text in PlayerGui", tostring(total))
		T.info(fmt("*kitb stroke walk: %d texts, %d with stroke + outline, %d outlined on an opaque panel", total, #doubled, #panelled))
		-- U1: a warning (the 18 helpers and the explicit Stroke callers are U6's sweep); U6 turns these into T.check
		if #doubled > 0 then
			T.warn(fmt("kitb stroke walk: %d text(s) with both a classic stroke and an outline (U6 drives to 0)", #doubled), table.concat(doubled, "; ", 1, math.min(#doubled, 8)))
		end
		if #panelled > 0 then
			T.warn(fmt("kitb stroke walk: %d outlined text(s) on an opaque panel (U6 drives to 0)", #panelled), table.concat(panelled, "; ", 1, math.min(#panelled, 8)))
		end
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
