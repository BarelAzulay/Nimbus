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
--   theme_fontof_measure_label (server world, pure; U1 review) the engine's rule, mirrored by the mock: a face with no Enum
--                             twin (Nunito ExtraBold / Bold Italic) reads .Font = Enum.Font.Unknown, which GetTextSize
--                             refuses; Theme.FontOf(obj) = the Enum font to measure with (its .Font, else its stamped role's
--                             fallback, else Body's); Theme.MeasureLabel(obj[, text, size, width]) = Theme.Measure for a face
--                             role, GetTextSize with its font otherwise
--   theme_texton              (server world, pure) Theme.TextOn(surface): brown #3B2412 on stone (and any light fill),
--                             white on navy and on today's dark panels; Theme.Sign = the pitch palette (decision 5);
--                             Theme.Radius = { None = 0, S = 4, M = 8 } and Theme.Corner takes a token name
--   kitb_text_stroke_or_panel (client) a walk over every text object in PlayerGui after the client run: labels with both a
--                             classic stroke and an outline, and outlined labels on an opaque panel. U1 reports the counts
--                             as a warning; U6 drives them to zero and makes this a failure
--   kitb_fit_measures_face_label (client; U1 review) the side hint (a Toast label, Nunito ExtraBold) sizes its pill from
--                             Theme.MeasureLabel, not the 300 px it fell back to while .Font read Unknown
--   U2 (SignKit, PixelIcon, Credits on the kit; findings 5, 7):
--   signkit_parts_shape       (server world, pure) every SignKit part by name, colour and size: the flat awning roof (a
--                             fixed offset size whatever its parent, no UIScale; the Credits gable as Shape = "Gable"), the
--                             navy header with its LuckiestGuy gold title, the wood frame, the stone body with its lip, the
--                             plank, the rope, the notice; each part stamps its kind (attribute SignKit)
--   signkit_plank_press_moves_face (server world, pure) the plank's states: hover lifts the block 2 px, press puts it back
--                             and moves the face down onto the lip (2 px of lip left), release / leave restore it; no size
--                             changes, no UIScale, no glow; Activated runs the callback
--   signkit_blockrow_fill     (server world, pure) a row of n stone blocks (offset sizes), FillBlocks(row, k) turns the
--                             first k gold (face and lip), clamped to 0..n and floored
--   signkit_shared_only       (server world, pure) SignKit requires only Theme from Shared, PixelIcon requires nothing;
--                             neither touches a client-only service, so the loading screen (ReplicatedFirst) can use both
--   pixelicon_bitmaps_9x9     (server world, pure) every icon is 9 rows of 9 cells of "." / "#"; the pitch's 27 bitmaps
--                             are kept exactly as the owner saw them; the screens' icons exist (play, gear, scroll, star,
--                             music, speaker, monitor, shake, mouse, bulb, arrow, tick, swap, token)
--   pixelicon_run_merge_count (server world, pure) PixelIcon.New draws one Frame per merged run (at most 25 per icon), at
--                             whole-pixel offsets, covering exactly the "#" cells at 18, 27 and 36 px; an unknown name is nil
--   credits_unchanged_on_signkit (client) the Credits window (built from SignKit parts) dumps the same boxes, colours,
--                             texts and fonts as the approved window of 2026-11-13 (tools/fixtures/credits_tree_u1.txt,
--                             recorded before the move) at 1920x1080, 1280x720, 844x390 and 390x844
--   U3 (the loading screen in kit B; finding 4, sky F11; all client, each runs LoadingScreen.client.lua afresh):
--   loading_board_parts       two ropes, the flat awning roof, the navy header with NIMBUS CLIMB (Title role, gold, no
--                             outline), the 6 px wood frame round the stone body; min(0.5 W, 620 design px) wide, W - 32 px
--                             on a portrait phone; the board swings within 1.5 degrees
--   loading_progress_blocks   12 blocks: 0 %, 50 %, 100 % -> 0, 6, 12 gold, one by one; the caption follows
--   loading_no_round_corners  no UICorner on the screen
--   loading_no_neon_no_stroke no UIStroke, no classic text stroke, no gradient but the sky's, no old neon / violet colour
--   loading_tokens_match_theme the board drawn before Theme (its own token copy) wears Theme.Sign and SignKit.Sizes
--   loading_shows_before_theme the day sky, the stepped clouds and the whole board without Theme, no text; the title joins
--                             the same board once Theme arrives
--   loading_skip_is_plank     SKIP is a SignKit plank with the pixel arrow, no glyph arrow, and still finishes the screen
--   loading_images_optional   Config.Loading.Images keys unset -> no image (typed title, drawn clouds); set -> Logo,
--                             Backdrop and Mascot ImageLabels, the title and clouds off
--   loading_board_fits        (U3 review) at 768x1024, 834x1194, 640x360, 667x375, 800x360, 740x360, 720x360 and the grid
--                             sizes: the title fits its plate, the swinging board ends above the tip card and clear of
--                             SKIP, SKIP clear of the card, the board below the top bar, the blocks and caption in the body
--   U4 (the main menu Signboard): menu_* (see each scenario)
--   U5 (Settings and Updates on the Signboard, finding 5; and the U2 / U3 review polish):
--   settings_on_signkit       the Settings window: flat awning, navy header SETTINGS (Title role, gold, the pixel gear),
--                             red Close plank with the pixel x, wood frame, stone body; each row its pixel icon and brown
--                             FredokaOne title; the chips planks, the selected one gold; no neon; a portrait sheet hides
--                             the title board behind it
--   settings_no_emoji         no code point above U+2000 in any text of the Settings and Updates windows
--   settings_scale_is_blockrow the 0..10 scale is a BlockRow of 10 between the - / + planks; a tap on a block sets it
--   updates_on_signkit        WHAT'S NEW: each version a navy plank in FredokaOne gold, each line Nunito brown after a
--                             6 px square bullet
--   settings_hidden_under_credits the DEV panel (Restart / Skip tutorial) and a menu window are never open together
--   loading_tip_clear_of_bulb (g) the tip's text starts 12 px or more right of the pixel bulb at every size
--   menu_plank_labels_fit     (U5 review) PLAY / SETTINGS / UPDATES: the auto-sized label beside its icon never truncates,
--                             and text + icon + gap fits the face at 1920x1080, 1280x720, 844x390 and 390x844; a label
--                             that just fits a bare face steps down once its icon is laid beside it
--   (server world, pure) signkit_plank_press_sinks (a), signkit_plank_off_disabled (b), signkit_plank_label_fits (c),
--   signkit_style_tokens (d), signkit_header_rim_matches_frame (e), pixelicon_clamp_and_warn (f),
--   credits_record_needs_flag (h)
-- Plain Lua 5.1 syntax only.

local T = SmokeCommon.T
local guarded = SmokeCommon.guarded

local fmt = string.format

-- record mode of credits_unchanged_on_signkit (rewrite tools/fixtures/credits_tree_u1.txt from this run): only smoke.py's
-- explicit --record-credits-tree flag (U5 review: an environment variable left set must never rewrite the owner's look)
local function creditsRecord()
	return type(ARGS) == "table" and ARGS.record_credits_tree == true
end

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
		-- (review) in Roblox a Nunito ExtraBold label reads .Font = Enum.Font.Unknown; its stamped role gives the Enum fallback
		T.check(body.FontFace == Theme.Faces.Body and body:GetAttribute("FontRole") == "Body" and Theme.FontOf(body) == Theme.Fonts.Body,
			"kitb stroke: a Body label carries the Nunito ExtraBold face, its role stamp and (Theme.FontOf) the Enum fallback", tostring(body.Font))
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
		T.check(label.FontFace == Theme.Faces.Body and label:GetAttribute("FontRole") == "Body" and Theme.FontOf(label) == Theme.Fonts.Body,
			"kitb setrole: SetRole(Body) = the Nunito face, the role stamp and (Theme.FontOf) the Enum fallback", tostring(label.Font))
		T.check(sameColor(label.TextColor3, Color3.fromRGB(200, 10, 10)) and label.TextSize == 31 and math.abs(label.TextStrokeTransparency - 0.7) < 1e-6, "kitb setrole: SetRole leaves colour, size and stroke alone")
		Theme.SetRole(label, "Title")
		T.check(label.Font == Theme.Fonts.Title and label.FontFace ~= Theme.Faces.Body and tostring(label.FontFace.Family):find("LuckiestGuy") ~= nil and label:GetAttribute("FontRole") == "Title",
			"kitb setrole: SetRole(Title) after Body clears the Nunito face (the Title font is the face)", tostring(label.Font) .. " " .. faceText(label.FontFace))
		Theme.SetRole(label, "NoSuchRole")
		T.check(label.FontFace == Theme.Faces.Body and Theme.FontOf(label) == Theme.Fonts.Body and label:GetAttribute("FontRole") == "Body", "kitb setrole: an unknown role is Body")
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

	S.theme_fontof_measure_label = guarded("theme_fontof_measure_label", function()
		local Theme = theme()
		if not Theme then
			return
		end
		if not T.check(type(Theme.FontOf) == "function" and type(Theme.MeasureLabel) == "function", "kitb fontof: Theme.FontOf and Theme.MeasureLabel exist") then
			return
		end
		local TS = game:GetService("TextService")
		-- the engine (probed in Studio): a face with no Enum twin reads .Font = Unknown, GetTextSize refuses Unknown, and
		-- writing Unknown to .Font is ignored
		local body = Theme.Label("Nimbus Climb", "Body", { Size = 20 })
		T.check(body.Font == Enum.Font.Unknown, "kitb fontof: a Nunito ExtraBold label reads .Font = Enum.Font.Unknown (as in Roblox)", tostring(body.Font))
		T.check(not pcall(function()
			return TS:GetTextSize("x", 20, body.Font, Vector2.new(1000, 1000))
		end), "kitb fontof: GetTextSize refuses Enum.Font.Unknown (as in Roblox)")
		local plain = Instance.new("TextLabel")
		plain.Font = Enum.Font.FredokaOne
		plain.Font = Enum.Font.Unknown
		T.check(plain.Font == Enum.Font.FredokaOne, "kitb fontof: writing Enum.Font.Unknown to .Font is ignored (as in Roblox)", tostring(plain.Font))
		-- Theme.FontOf: the Enum font to measure with
		T.check(Theme.FontOf(body) == Theme.Fonts.Body, "kitb fontof: a Body label measures with the Body Enum fallback", tostring(Theme.FontOf(body)))
		for _, role in ipairs({ "Label", "Toast", "Script" }) do
			local l = Theme.Label("x", role)
			T.check(Theme.FontOf(l) == Theme.Fonts[role], "kitb fontof: a " .. role .. " label measures with its Enum fallback", tostring(Theme.FontOf(l)))
			l:Destroy()
		end
		local heading = Theme.Label("Nimbus Climb", "Heading", { Size = 20 })
		T.check(Theme.FontOf(heading) == Theme.Fonts.Heading and heading.Font == Theme.Fonts.Heading, "kitb fontof: a Heading label is its own .Font")
		T.check(Theme.FontOf(plain) == Enum.Font.FredokaOne, "kitb fontof: a label never styled by Theme answers its own .Font")
		heading.Font = Theme.Fonts.Display
		T.check(Theme.FontOf(heading) == Theme.Fonts.Display, "kitb fontof: a later .Font write wins over the stamped role")
		local loose = Instance.new("TextLabel")
		loose.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
		T.check(Theme.FontOf(loose) == Theme.Fonts.Body, "kitb fontof: an unstamped face with no Enum twin measures as Body", tostring(Theme.FontOf(loose)))
		T.check(Theme.FontOf(nil) == Theme.Fonts.Body, "kitb fontof: nil measures as Body")
		-- Theme.MeasureLabel: a face role goes through Theme.Measure (its spare), an Enum font 1:1
		local mb = Theme.MeasureLabel(body)
		local want = Theme.Measure("Nimbus Climb", "Body", 20)
		T.check(typeof(mb) == "Vector2" and mb.X == want.X and mb.Y == want.Y, "kitb fontof: MeasureLabel(Body label) = Theme.Measure(its text, Body, its size)", tostring(mb) .. " vs " .. tostring(want))
		local mh = Theme.MeasureLabel(heading, "Nimbus Climb", 20)
		local raw = TS:GetTextSize("Nimbus Climb", 20, Theme.Fonts.Display, Vector2.new(100000, 100000))
		T.check(mh.X == raw.X and mh.Y == raw.Y, "kitb fontof: MeasureLabel(an Enum-font label) = GetTextSize with its font", tostring(mh) .. " vs " .. tostring(raw))
		local m30 = Theme.MeasureLabel(body, "Hi", 30)
		T.check(m30.X == Theme.Measure("Hi", "Body", 30).X, "kitb fontof: MeasureLabel's text and size arguments override the label's")
		for _, l in ipairs({ body, plain, heading, loose }) do
			l:Destroy()
		end
		K.flushErrors("theme_fontof_measure_label")
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

	----------------------------------------------------------------------
	-- U2: SignKit, PixelIcon
	----------------------------------------------------------------------
	local function shared(name)
		local inst = K.moduleInstance("shared/" .. name)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		if not T.check(ok and type(mod) == "table", "kitb u2: shared/" .. name .. " loads", tostring(mod)) then
			return nil
		end
		return mod
	end

	local function hasScale(obj)
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("UIScale") then
				return true
			end
		end
		return obj:IsA("UIScale")
	end

	local function holder(w, h)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromOffset(w, h)
		return f
	end

	S.signkit_parts_shape = guarded("signkit_parts_shape", function()
		local Theme, SK = theme(), shared("SignKit")
		if not (Theme and SK) then
			return
		end
		local Sg, Z = Theme.Sign, SK.Sizes
		T.check(type(Z) == "table" and Z.RoofW > 0 and Z.RoofH > 0 and Z.Lip > 0 and Z.Edge > 0, "signkit: SignKit.Sizes holds the kit's design px")
		for _, key in ipairs({ "RoofEdge", "RoofLip", "GoldLip", "NavyLip", "GrassLip", "RedLip", "Tile", "Post" }) do
			T.check(typeof(Sg[key]) == "Color3", "signkit: Theme.Sign." .. key .. " (the pitch's lip / edge tokens)")
		end

		-- the awning: one fixed-size piece, the same whatever the window under it
		local small, wide = holder(400, 300), holder(1400, 900)
		local r1, r2 = SK.Roof(small), SK.Roof(wide)
		T.check(r1.Name == "Roof" and r1:GetAttribute("SignKit") == "Roof", "signkit roof: a Frame named Roof, stamped SignKit = Roof")
		T.check(r1.Size.X.Scale == 0 and r1.Size.Y.Scale == 0 and r1.Size.X.Offset == Z.RoofW and r1.Size.Y.Offset == Z.RoofH,
			"signkit roof: offset size only, the kit's RoofW x RoofH", tostring(r1.Size))
		T.check(r1.Size == r2.Size, "signkit roof: the roof never scales with the window (same size under 400 and 1400 px)", tostring(r1.Size) .. " / " .. tostring(r2.Size))
		T.check(not hasScale(r1), "signkit roof: no UIScale inside the roof")
		local face, lip = r1:FindFirstChild("Face"), r1:FindFirstChild("Face") and r1.Face:FindFirstChild("Lip")
		T.check(sameColor(r1.BackgroundColor3, Sg.RoofEdge) and r1.BackgroundTransparency == 0, "signkit roof: the dark roof edge", hex(r1.BackgroundColor3))
		T.check(face ~= nil and sameColor(face.BackgroundColor3, Sg.Roof), "signkit roof: the pink face (#EE6FA6)", face and hex(face.BackgroundColor3) or "none")
		T.check(lip ~= nil and sameColor(lip.BackgroundColor3, Sg.RoofLip) and lip.Size.Y.Offset == Z.RoofLip and lip.AnchorPoint.Y == 1,
			"signkit roof: a darker lip along the face's bottom", lip and (hex(lip.BackgroundColor3) .. " " .. tostring(lip.Size)) or "none")
		local r3 = SK.Roof(small, { Width = 520 })
		T.check(r3.Size.X.Offset == 520 and r3.Size.X.Scale == 0, "signkit roof: a caller's width is still a fixed offset")
		local g = SK.Roof(small, { Shape = "Gable", Width = 300, Height = 44, Slope = 52, Fascia = 9 })
		T.check(g:FindFirstChild("SlopeL") and g:FindFirstChild("SlopeR") and g:FindFirstChild("Fascia") and g:FindFirstChild("Vent"),
			"signkit roof: Shape = 'Gable' builds the Credits gable (two slopes, fascia, vent)")
		T.check(g.Size == UDim2.fromOffset(300, 44) and not hasScale(g), "signkit roof: the gable is fixed-size too")

		-- the header: navy plank, gold LuckiestGuy title, no stroke
		local win = holder(600, 400)
		local head, plate = SK.Header(win, { Title = "PETS" })
		T.check(head and head.Name == "Head" and head:GetAttribute("SignKit") == "Header" and plate and plate.Name == "Plate", "signkit header: Head + Plate")
		if head and plate then
			T.check(sameColor(plate.BackgroundColor3, Sg.Navy) and sameColor(head.BackgroundColor3, Sg.Wood), "signkit header: a navy plate in a wood rim",
				hex(plate.BackgroundColor3) .. " in " .. hex(head.BackgroundColor3))
			T.check(head.Size.X.Scale == 1 and head.Size.Y.Offset == Z.HeadH, "signkit header: full width, HeadH tall", tostring(head.Size))
			local title = plate:FindFirstChild("Title")
			T.check(title and title.Text == "PETS" and title.Font == Enum.Font.LuckiestGuy and sameColor(title.TextColor3, Sg.Gold),
				"signkit header: the title is LuckiestGuy gold", title and (tostring(title.Font) .. " " .. hex(title.TextColor3)) or "none")
			T.check(title and title.TextStrokeTransparency == 1 and #textStrokes(title) == 0, "signkit header: the title has no stroke (gold on navy, 9:1)")
			T.check(plate:FindFirstChild("TitleDrop") == nil, "signkit header: no drop line unless asked")
		end
		local _, plate2 = SK.Header(win, { Title = "X", Drop = Color3.fromRGB(11, 19, 48), IconSlot = true })
		T.check(plate2 and plate2:FindFirstChild("TitleDrop") and plate2:FindFirstChild("IconSlot"), "signkit header: Drop adds the drop line, IconSlot the gold icon square")

		-- frame (wood) and body (stone with its lip)
		local wood = SK.Frame(win, { Y = 60, Height = 300 })
		T.check(wood.Name == "Wood" and wood:GetAttribute("SignKit") == "Frame" and sameColor(wood.BackgroundColor3, Sg.Wood) and wood.Position.Y.Offset == 60 and wood.Size.Y.Offset == 300,
			"signkit frame: the wood frame at Y, Height tall", tostring(wood.Position) .. " " .. tostring(wood.Size))
		local body = SK.Body(wood)
		T.check(body.Name == "Body" and body:GetAttribute("SignKit") == "Body" and sameColor(body.BackgroundColor3, Sg.Stone), "signkit body: stone")
		T.check(body.Position == UDim2.fromOffset(Z.Frame, Z.Frame) and body.Size == UDim2.new(1, -2 * Z.Frame, 1, -2 * Z.Frame), "signkit body: inset by the frame's width", tostring(body.Position))
		local blip = body:FindFirstChild("Lip")
		T.check(blip and sameColor(blip.BackgroundColor3, Sg.StoneLip) and blip.Size.Y.Offset == Z.Lip and blip.AnchorPoint.Y == 1 and blip.Position.Y.Scale == 1,
			"signkit body: the stone lip along the bottom", blip and tostring(blip.Size) or "none")
		local flat = SK.Body(SK.Frame(win), { Lip = 0, Line = { Inset = 5, Thickness = 3, Color = Sg.StoneLip } })
		T.check(flat:FindFirstChild("Lip") == nil and flat:FindFirstChild("Line") and flat.Line:FindFirstChildOfClass("UIStroke"), "signkit body: Lip = 0 has none; Line draws the inner line")

		-- the plank (a button), rope and notice
		local plank = SK.Plank(win, { Text = "Put in team", Style = "Grass", Width = 180 })
		T.check(plank:IsA("TextButton") and plank.Name == "Plank" and plank:GetAttribute("SignKit") == "Plank" and plank.AutoButtonColor == false and plank.BackgroundTransparency == 1,
			"signkit plank: a transparent TextButton hit box, no auto colour")
		local block = plank:FindFirstChild("Block")
		local pface = block and block:FindFirstChild("Face")
		local plip = block and block:FindFirstChild("Lip")
		local plabel = pface and pface:FindFirstChild("Label")
		T.check(block and pface and plip and plabel, "signkit plank: Block (edge) > Lip + Face > Label")
		if block and pface and plip and plabel then
			T.check(sameColor(pface.BackgroundColor3, Sg.Grass) and sameColor(plip.BackgroundColor3, Sg.GrassLip), "signkit plank: Style Grass = grass face, grass lip")
			T.check(plabel.Text == "Put in team" and plabel.Font == Enum.Font.FredokaOne and plabel.TextStrokeTransparency == 1, "signkit plank: the label is FredokaOne, no stroke")
			local faceH = pface.Size.Y.Scale * Z.PlankH + pface.Size.Y.Offset -- the block fills the plank
			T.check(faceH == Z.PlankH - 2 * Z.Edge - Z.Lip and plank.Size == UDim2.fromOffset(180, Z.PlankH), "signkit plank: the face leaves the lip showing", tostring(pface.Size))
			T.check(not hasScale(plank) and plank:FindFirstChildWhichIsA("UIStroke", true) == nil, "signkit plank: no UIScale, no stroke glow")
		end
		local rope = SK.Rope(win, { Length = 90 })
		T.check(rope.Name == "Rope" and rope:GetAttribute("SignKit") == "Rope" and rope.Size == UDim2.fromOffset(Z.RopeW, 90) and sameColor(rope.BackgroundColor3, Sg.Post),
			"signkit rope: RopeW wide, Length long, the post colour", tostring(rope.Size))
		local notice, nface = SK.Notice(win, { Width = 300, Height = 60, Text = "Tip: hold Space" })
		T.check(notice.Name == "Notice" and notice:GetAttribute("SignKit") == "Notice" and sameColor(notice.BackgroundColor3, Sg.Wood) and nface and sameColor(nface.BackgroundColor3, Sg.Stone),
			"signkit notice: a wood-framed stone card")
		local ntext = nface and nface:FindFirstChild("Text")
		T.check(ntext and sameColor(ntext.TextColor3, Sg.Text) and ntext.TextStrokeTransparency == 1, "signkit notice: brown text on stone, no stroke")
		win:Destroy()
		small:Destroy()
		wide:Destroy()
		K.flushErrors("signkit_parts_shape")
	end)

	S.signkit_plank_press_moves_face = guarded("signkit_plank_press_moves_face", function()
		local SK = shared("SignKit")
		if not SK then
			return
		end
		local Z = SK.Sizes
		local clicks = 0
		local plank = SK.Plank(holder(400, 200), { Text = "Feed", Callback = function()
			clicks = clicks + 1
		end })
		local block, face = plank.Block, plank.Block.Face
		local size0, face0, block0 = plank.Size, face.Size, block.Size
		local function at(state)
			return string.format("%s: block y %d, face y %d", state, block.Position.Y.Offset, face.Position.Y.Offset)
		end
		T.check(block.Position.Y.Offset == 0 and face.Position.Y.Offset == Z.Edge and plank:GetAttribute("PlankState") == "Rest", "plank: at rest the face sits on the full lip", at("rest"))
		Mock.FireSignal(plank, "MouseEnter")
		T.check(block.Position.Y.Offset == -Z.Hover and face.Position.Y.Offset == Z.Edge and plank:GetAttribute("PlankState") == "Hover", "plank: hover lifts the block 2 px", at("hover"))
		Mock.FireSignal(plank, "MouseButton1Down")
		-- (U5) the pressed look itself (the block sinks, the lip shrinks): signkit_plank_press_sinks
		T.check(plank:GetAttribute("PlankState") == "Press", "plank: press = the Press state", at("press"))
		T.check(plank.Size == size0 and block.Size == block0, "plank: pressing changes no plank or block size (no scale bounce)")
		Mock.FireSignal(plank, "MouseButton1Up")
		T.check(face.Position.Y.Offset == Z.Edge and block.Position.Y.Offset == -Z.Hover, "plank: release lifts the face back (still hovered)", at("release"))
		Mock.FireSignal(plank, "MouseLeave")
		T.check(face.Position.Y.Offset == Z.Edge and block.Position.Y.Offset == 0 and plank:GetAttribute("PlankState") == "Rest", "plank: leave = rest", at("leave"))
		SK.PlankState(plank, "Press")
		T.check(plank:GetAttribute("PlankState") == "Press" and block.Position.Y.Offset > 0, "plank: SignKit.PlankState sets a state directly")
		SK.PlankState(plank, "Rest")
		Mock.Click(plank)
		T.check(clicks == 1, "plank: Activated runs the callback once", tostring(clicks))
		T.check(not hasScale(plank) and plank:FindFirstChildWhichIsA("UIStroke", true) == nil, "plank: no UIScale, no glow stroke after the presses")
		-- touch: a finger that lifts never produces MouseLeave
		local function rest()
			return block.Position.Y.Offset == 0 and face.Position.Y.Offset == Z.Edge and plank:GetAttribute("PlankState") == "Rest"
		end
		SK.PlankState(plank, "Rest")
		Mock.FireSignal(plank, "MouseEnter")
		Mock.FireSignal(plank, "MouseButton1Down")
		Mock.FireSignal(plank, "MouseButton1Up")
		Mock.FireSignal(plank, "InputEnded", Mock.NewInput("Unknown", "Touch", "End"), false)
		T.check(rest(), "plank: a touch tap ends at rest, not stuck hovered", at("tap"))
		Mock.FireSignal(plank, "MouseEnter")
		Mock.FireSignal(plank, "MouseButton1Down")
		Mock.FireSignal(plank, "InputEnded", Mock.NewInput("Unknown", "Touch", "End"), false)
		T.check(rest(), "plank: press, slide off and lift ends at rest, not stuck pressed", at("slide off"))
		Mock.FireSignal(plank, "MouseEnter")
		Mock.FireSignal(plank, "InputEnded", Mock.NewInput("Unknown", "MouseButton1", "End"), false)
		T.check(plank:GetAttribute("PlankState") == "Hover", "plank: a mouse InputEnded keeps the hover", at("mouse end"))
		SK.PlankState(plank, "Rest")
		local off = SK.Plank(holder(400, 200), { Text = "Locked", Style = "Off" })
		Mock.FireSignal(off, "MouseEnter")
		Mock.FireSignal(off, "MouseButton1Down")
		T.check(off.Block.Position.Y.Offset == 0 and off.Block.Face.Position.Y.Offset == Z.Edge, "plank: a disabled (Off) plank does not move")
		K.flushErrors("signkit_plank_press_moves_face")
	end)

	S.signkit_blockrow_fill = guarded("signkit_blockrow_fill", function()
		local Theme, SK = theme(), shared("SignKit")
		if not (Theme and SK) then
			return
		end
		local Sg = Theme.Sign
		local row = SK.BlockRow(holder(800, 100), { Count = 12, BlockW = 30, BlockH = 24, Gap = 4 })
		T.check(row.Name == "BlockRow" and row:GetAttribute("SignKit") == "BlockRow" and row.Size == UDim2.fromOffset(12 * 30 + 11 * 4, 24),
			"blockrow: 12 blocks of 30 with 4 px gaps, offset size", tostring(row.Size))
		local blocks = {}
		for i = 1, 12 do
			blocks[i] = row:FindFirstChild("Block" .. i)
		end
		T.check(#blocks == 12 and row:FindFirstChild("Block13") == nil, "blockrow: Block1 .. Block12")
		if #blocks < 12 then
			return
		end
		T.check(blocks[2].Position.X.Offset == 34 and blocks[12].Position.X.Offset == 11 * 34, "blockrow: blocks step by width + gap")
		local function gold(b)
			return sameColor(b.Face.BackgroundColor3, Sg.Gold) and sameColor(b.Face.Lip.BackgroundColor3, Sg.GoldLip)
		end
		local function stone(b)
			return sameColor(b.Face.BackgroundColor3, Sg.Stone) and sameColor(b.Face.Lip.BackgroundColor3, Sg.StoneLip)
		end
		local function pattern()
			local s = ""
			for i = 1, 12 do
				s = s .. (gold(blocks[i]) and "G" or (stone(blocks[i]) and "s" or "?"))
			end
			return s
		end
		T.check(pattern() == "ssssssssssss", "blockrow: all stone (with a darker lip) at first", pattern())
		T.eq(SK.FillBlocks(row, 5), 5, "blockrow: FillBlocks returns the filled count")
		T.check(pattern() == "GGGGGsssssss" and row:GetAttribute("Filled") == 5, "blockrow: 5 filled = the first 5 gold (face and lip)", pattern())
		SK.FillBlocks(row, 99)
		T.check(pattern() == "GGGGGGGGGGGG", "blockrow: over the count = all gold", pattern())
		SK.FillBlocks(row, 4.7)
		T.check(pattern() == "GGGGssssssss", "blockrow: a fraction of a block floors", pattern())
		SK.FillBlocks(row, -3)
		T.check(pattern() == "ssssssssssss" and row:GetAttribute("Filled") == 0, "blockrow: below 0 = none", pattern())
		K.flushErrors("signkit_blockrow_fill")
	end)

	S.signkit_shared_only = guarded("signkit_shared_only", function()
		local SK, PI = shared("SignKit"), shared("PixelIcon")
		if not (SK and PI) then
			return
		end
		local function code(name)
			local inst = K.moduleInstance("shared/" .. name)
			local src = tostring(inst and inst.Source or "")
			local lines = {}
			for line in (src .. "\n"):gmatch("([^\n]*)\n") do
				lines[#lines + 1] = (line:gsub("%-%-.*$", ""))
			end
			return table.concat(lines, "\n")
		end
		for name, allowed in pairs({ SignKit = { Theme = true }, PixelIcon = {} }) do
			local src = code(name)
			T.check(src ~= "", "shared only: " .. name .. " has source")
			local bad = {}
			for arg in src:gmatch("require%s*(%b())") do
				local sib = arg:match('^%(%s*script%.Parent:WaitForChild%("(%w+)"%)%s*%)$') or arg:match("^%(%s*script%.Parent%.(%w+)%s*%)$")
				if not (sib and allowed[sib]) then
					bad[#bad + 1] = arg
				end
			end
			T.check(#bad == 0, "shared only: " .. name .. " requires only " .. (next(allowed) and "Theme (a sibling in Shared)" or "nothing"), table.concat(bad, ", "))
			local client = {}
			for _, word in ipairs({ "LocalPlayer", "PlayerGui", "UserInputService", "StarterPlayer", "ReplicatedFirst", "GetService%(\"Players\"%)", "Controllers", "client/" }) do
				if src:find(word) then
					client[#client + 1] = word
				end
			end
			T.check(#client == 0, "shared only: " .. name .. " touches no client-only service or folder", table.concat(client, ", "))
		end
		K.flushErrors("signkit_shared_only")
	end)

	-- the pitch's bitmaps, exactly as kit_pitch_mockups.html:523-550 drew them for the owner
	local PITCH_ICONS = {
		paw = "..##.##../..##.##../##.....##/##.###.##/..#####../.#######./.#######./..##.##../.........",
		book = "........./###...###/####.####/####.####/####.####/####.####/####.####/.###.###./.........",
		house = "....#..../...###.../..#####../.#######./#########/.#######./.##...##./.##...##./.##...##.",
		stats = "........./......##./......##./...##.##./...##.##./##.##.##./##.##.##./##.##.##./.........",
		bag = "...###.../..#...#../.#######./#########/#########/#########/#########/#########/.#######.",
		arrow = "........./....#..../....##.../#######../########./#######../....##.../....#..../.........",
		gear = "...###.../.#.###.#./.#######./###...###/###...###/###...###/.#######./.#.###.#./...###...",
		heart = "........./.##...##./####.####/#########/#########/.#######./..#####../...###.../....#....",
		bolt = ".....###./....###../...###.../..######./....###../...###.../..###..../.##....../.........",
		note = "........./........./#########/#.......#/#..###..#/#..###..#/#.......#/#########/.........",
		coin = "..#####../.#######./####.####/####.####/####.####/####.####/####.####/.#######./..#####..",
		gem = "........./.#######./#########/#########/.#######./..#####../...###.../....#..../.........",
		gift = ".##...##./#..#.#..#/.#######./#########/#########/.###.###./.###.###./.###.###./.###.###.",
		check = "........./........#/.......##/#.....##./##...##../.##.##.../..###..../...#...../.........",
		x = "........./.##...##./.###.###./..#####../...###.../..#####../.###.###./.##...##./.........",
		sword = "......###/.....####/....####./...####../#.####.../.####..../..##...../.#.##..../#...#....",
		star = "....#..../....#..../...###.../#########/.#######./..#####../..#####../.##...##./.#.....#.",
		flame = "....#..../...##..../...###.../.#.####../.#######./#########/###...###/.##...##./..#####..",
		flake = "....#..../.#..#..#./..#.#.#../...###.../#########/...###.../..#.#.#../.#..#..#./....#....",
		moon = "...####../..###..../.###...../.###...../.###...../.###...../.####...#/..######./...####..",
		cloud = "........./...##..../..####.#./.#######./#########/#########/.#######./........./.........",
		apple = ".....##../....#..../.###.###./#########/#########/#########/#########/.#######./..##.##..",
		bell = "........./........./##.....##/##.....##/#########/##.....##/##.....##/........./.........",
		sprout = "........./###...###/####.####/.###.###./...###.../....#..../....#..../..#####../.#######.",
		plus = "...###.../...###.../...###.../#########/#########/#########/...###.../...###.../...###...",
		dash = "........./##..##.../.##..##../..##..##./...##..##/..##..##./.##..##../##..##.../.........",
		down = "........./........./##.....##/###...###/.###.###./..#####../...###.../....#..../.........",
	}
	-- the icons the loading screen, menu, settings and credits need beyond the pitch's (BUILD_PLAN U2)
	local SCREEN_ICONS = { "play", "gear", "scroll", "star", "music", "speaker", "monitor", "shake", "mouse", "bulb", "arrow", "tick", "swap", "token" }

	S.pixelicon_bitmaps_9x9 = guarded("pixelicon_bitmaps_9x9", function()
		local PI = shared("PixelIcon")
		if not PI then
			return
		end
		local B = PI.Bitmaps
		if not T.check(type(B) == "table", "pixelicon: PixelIcon.Bitmaps is a table") then
			return
		end
		local bad, empty, count = {}, {}, 0
		for name, bmp in pairs(B) do
			count = count + 1
			local rows = {}
			for row in (tostring(bmp) .. "/"):gmatch("([^/]*)/") do
				rows[#rows + 1] = row
			end
			local ok = #rows == 9
			for _, row in ipairs(rows) do
				if #row ~= 9 or row:find("[^%.#]") then
					ok = false
				end
			end
			if not ok then
				bad[#bad + 1] = name
			end
			if not tostring(bmp):find("#", 1, true) then
				empty[#empty + 1] = name
			end
		end
		table.sort(bad)
		table.sort(empty)
		T.check(#bad == 0, "pixelicon: every icon is 9 rows of 9 cells of '.' / '#' (" .. count .. " icons)", table.concat(bad, ", "))
		T.check(#empty == 0, "pixelicon: no icon is blank", table.concat(empty, ", "))
		local changed = {}
		for name, want in pairs(PITCH_ICONS) do
			if B[name] ~= want then
				changed[#changed + 1] = name
			end
		end
		table.sort(changed)
		T.check(#changed == 0, "pixelicon: the pitch's 27 icons are ported exactly as the owner saw them", table.concat(changed, ", "))
		local missing = {}
		for _, name in ipairs(SCREEN_ICONS) do
			if not B[name] then
				missing[#missing + 1] = name
			end
		end
		T.check(#missing == 0, "pixelicon: the screens' icons exist (play, gear, scroll, star, music, speaker, monitor, shake, mouse, bulb, arrow, tick, swap, token)", table.concat(missing, ", "))
		T.check(B.tick == B.check, "pixelicon: tick is the pitch's check")
		T.check(B.token ~= B.coin, "pixelicon: the cloud token has its own coin (not the plain coin)")
		K.flushErrors("pixelicon_bitmaps_9x9")
	end)

	S.pixelicon_run_merge_count = guarded("pixelicon_run_merge_count", function()
		local PI = shared("PixelIcon")
		if not (PI and type(PI.New) == "function" and type(PI.Bitmaps) == "table") then
			T.check(false, "pixelicon: PixelIcon.New exists")
			return
		end
		local parent = holder(200, 200)
		local over, gaps, offgrid, worst, worstName = {}, {}, {}, 0, ""
		local red = Color3.fromRGB(200, 30, 40)
		for name, bmp in pairs(PI.Bitmaps) do
			local rows = {}
			for row in (bmp .. "/"):gmatch("([^/]*)/") do
				rows[#rows + 1] = row
			end
			for _, px in ipairs({ 18, 27, 36 }) do
				local icon = PI.New(parent, name, px, red)
				local cell = px / 9
				local frames = {}
				for _, c in ipairs(icon:GetChildren()) do
					if c:IsA("Frame") then
						frames[#frames + 1] = c
					end
				end
				if #frames > 25 then
					over[#over + 1] = name .. "@" .. px .. " " .. #frames
				end
				if #frames > worst then
					worst, worstName = #frames, name
				end
				-- paint the frames back onto a 9 x 9 grid: every "#" once, nothing else
				local grid = {}
				local ok = icon.Size == UDim2.fromOffset(px, px) and icon.BackgroundTransparency == 1 and icon:GetAttribute("PixelIcon") == name
				for _, f in ipairs(frames) do
					local x, y, w, h = f.Position.X.Offset, f.Position.Y.Offset, f.Size.X.Offset, f.Size.Y.Offset
					if x % 1 ~= 0 or y % 1 ~= 0 or w % 1 ~= 0 or h % 1 ~= 0 or f.Position.X.Scale ~= 0 or f.Size.X.Scale ~= 0 then
						offgrid[#offgrid + 1] = name .. "@" .. px
					end
					if not sameColor(f.BackgroundColor3, red) or f.BackgroundTransparency ~= 0 or f.BorderSizePixel ~= 0 then
						ok = false
					end
					for gy = y / cell, (y + h) / cell - 1 do
						for gx = x / cell, (x + w) / cell - 1 do
							local k = gy * 9 + gx
							if grid[k] then
								ok = false
							end
							grid[k] = true
						end
					end
				end
				for gy = 0, 8 do
					for gx = 0, 8 do
						if (rows[gy + 1]:sub(gx + 1, gx + 1) == "#") ~= (grid[gy * 9 + gx] == true) then
							ok = false
						end
					end
				end
				if not ok then
					gaps[#gaps + 1] = name .. "@" .. px
				end
				icon:Destroy()
			end
		end
		table.sort(over)
		table.sort(gaps)
		T.check(#over == 0, "pixelicon: no icon over 25 Frames (the worst: " .. worstName .. " " .. worst .. ")", table.concat(over, ", "))
		T.check(#gaps == 0, "pixelicon: the Frames cover exactly the '#' cells, once each, in the icon's colour, at 18 / 27 / 36 px", table.concat(gaps, ", ", 1, math.min(#gaps, 8)))
		T.check(#offgrid == 0, "pixelicon: every Frame sits on whole pixels (offsets only)", table.concat(offgrid, ", ", 1, math.min(#offgrid, 8)))
		local odd = PI.New(parent, "paw", 20, red)
		T.check(odd and odd.Size == UDim2.fromOffset(20, 20), "pixelicon: a size that is not a multiple of 9 keeps its box ...")
		local snapped = true
		for _, f in ipairs(odd and odd:GetChildren() or {}) do
			if f:IsA("Frame") and (f.Size.Y.Offset % 2 ~= 0 or f.Position.X.Offset % 1 ~= 0) then
				snapped = false
			end
		end
		T.check(snapped, "pixelicon: ... and draws whole 2 px cells, centred")
		T.check(PI.New(parent, "no_such_icon", 18, red) == nil, "pixelicon: an unknown icon name is nil (no error)")
		parent:Destroy()
		-- the 20 px icon above warns on purpose: take that warn here, so a later scenario's flush does not report it
		K.flushWarnings("pixelicon_run_merge_count", { "[PixelIcon] 20 px is not a multiple of 9" })
		K.flushErrors("pixelicon_run_merge_count")
	end)

	----------------------------------------------------------------------
	-- U5 polish of U2 / U3 (the review's items a-f, h)
	----------------------------------------------------------------------

	-- (a) the pitch's pressed look (.dn: translateY 4px, lip 2px): the whole block sinks Sizes.Sink px and the lip shrinks to
	-- PressLip px (the face grows down over it); hover and rest give both back; no plank or block size changes
	S.signkit_plank_press_sinks = guarded("signkit_plank_press_sinks", function()
		local SK = shared("SignKit")
		if not SK then
			return
		end
		local Z = SK.Sizes
		T.eq(Z.Sink, 4, "plank press: Sizes.Sink = 4 (the pitch's translateY 4px)")
		T.eq(Z.PressLip, 2, "plank press: Sizes.PressLip = 2 (the pitch's lip 2px)")
		for _, lipPx in ipairs({ Z.Lip, 6 }) do
			local plank = SK.Plank(holder(400, 200), { Text = "Feed", Width = 160, LipPx = lipPx })
			local block, face = plank.Block, plank.Block.Face
			local plankSize, blockSize = plank.Size, block.Size
			local function lipShown()
				return -(face.Size.Y.Offset + 2 * Z.Edge) -- the face's height is the block's less 2 edges and the lip
			end
			local tag = "lip " .. lipPx
			T.check(block.Position.Y.Offset == 0 and face.Position.Y.Offset == Z.Edge and lipShown() == lipPx, "plank press: at rest the full lip shows (" .. tag .. ")",
				fmt("block %d face %d lip %d", block.Position.Y.Offset, face.Position.Y.Offset, lipShown()))
			SK.PlankState(plank, "Press")
			T.check(block.Position.Y.Offset == Z.Sink, "plank press: the whole block sinks " .. Z.Sink .. " px (" .. tag .. ")", tostring(block.Position.Y.Offset))
			T.check(face.Position.Y.Offset == Z.Edge, "plank press: the face stays on the block's top edge, it does not slide over the lip (" .. tag .. ")",
				tostring(face.Position.Y.Offset))
			T.check(lipShown() == Z.PressLip, "plank press: the lip shrinks to " .. Z.PressLip .. " px (" .. tag .. ")", tostring(lipShown()))
			T.check(plank.Size == plankSize and block.Size == blockSize, "plank press: the plank and the block keep their size (no scale bounce) (" .. tag .. ")")
			SK.PlankState(plank, "Hover")
			T.check(block.Position.Y.Offset == -Z.Hover and lipShown() == lipPx, "plank press: hover lifts it with the full lip back (" .. tag .. ")")
			SK.PlankState(plank, "Rest")
			T.check(block.Position.Y.Offset == 0 and lipShown() == lipPx and face.Position.Y.Offset == Z.Edge, "plank press: rest restores it (" .. tag .. ")")
		end
		K.flushErrors("signkit_plank_press_sinks")
	end)

	-- (b) Style Off is a real disabled plank: not Active, not Selectable, no Activated callback, never moves
	S.signkit_plank_off_disabled = guarded("signkit_plank_off_disabled", function()
		local SK = shared("SignKit")
		if not SK then
			return
		end
		local clicks = 0
		local off = SK.Plank(holder(400, 200), { Text = "Locked", Style = "Off", Callback = function()
			clicks = clicks + 1
		end })
		T.check(off.Active == false, "plank off: Active = false", tostring(off.Active))
		T.check(off.Selectable == false, "plank off: Selectable = false (a gamepad never lands on it)", tostring(off.Selectable))
		Mock.Click(off)
		T.eq(clicks, 0, "plank off: a click runs no callback")
		Mock.FireSignal(off, "MouseEnter")
		Mock.FireSignal(off, "MouseButton1Down")
		T.check(off.Block.Position.Y.Offset == 0 and off:GetAttribute("PlankState") == "Rest", "plank off: it does not move")
		local on = SK.Plank(holder(400, 200), { Text = "Feed" })
		T.check(on.Active == true and on.Selectable == true, "plank off: a normal plank stays Active and Selectable")
		K.flushErrors("signkit_plank_off_disabled")
	end)

	-- (c) a plank's label fits its face: it shrinks (Theme.Measure, Button role) down to 14 px, then truncates at the end
	S.signkit_plank_label_fits = guarded("signkit_plank_label_fits", function()
		local Theme, SK = theme(), shared("SignKit")
		if not (Theme and SK) then
			return
		end
		local Z = SK.Sizes
		for _, c in ipairs({ { "Mouse lock (recommended)", 150, false }, { "SETTINGS", 120, true }, { "A much longer label than any plank should carry", 100, false }, { "OK", 160, false } }) do
			local plank = SK.Plank(holder(600, 200), { Text = c[1], Width = c[2], IconSlot = c[3] })
			local label = plank.Block.Face.Label
			local room = c[2] - 2 * Z.Edge - label.Position.X.Offset - 2 * Z.LabelPad
			local w = Theme.Measure(c[1], "Button", label.TextSize).X
			local tag = fmt("%q in %d", c[1], c[2])
			T.check(label.TextTruncate == Enum.TextTruncate.AtEnd, "plank fit: the label truncates at the end as a last resort (" .. tag .. ")")
			T.check(w <= room or label.TextSize == 14, "plank fit: the label is measured to its face, or at the 14 px floor (" .. tag .. ")",
				fmt("%d px text in %d px at %d", w, room, label.TextSize))
			T.check(label.TextSize >= 14, "plank fit: never under 14 px (" .. tag .. ")", tostring(label.TextSize))
		end
		local wide = SK.Plank(holder(600, 200), { Text = "OK", Width = 160, TextSize = 22 })
		T.eq(wide.Block.Face.Label.TextSize, 22, "plank fit: a label that fits keeps its size")
		K.flushErrors("signkit_plank_label_fits")
	end)

	-- (d) the pitch's tokens: the navy plank's edge is the gold lip (--signEdge #C99A1E), text on grass is dark green
	-- (--onPri #16321A)
	S.signkit_style_tokens = guarded("signkit_style_tokens", function()
		local Theme, SK = theme(), shared("SignKit")
		if not (Theme and SK) then
			return
		end
		local Sg = Theme.Sign
		T.check(sameColor(SK.Styles.Navy.Edge, Sg.GoldLip), "plank tokens: Navy's edge is Theme.Sign.GoldLip", hex(SK.Styles.Navy.Edge))
		T.check(typeof(Sg.OnGrass) == "Color3" and hex(Sg.OnGrass) == "#16321A", "plank tokens: Theme.Sign.OnGrass = #16321A", hex(Sg.OnGrass))
		T.check(sameColor(SK.Styles.Grass.Text, Sg.OnGrass), "plank tokens: Grass's label is the dark green", hex(SK.Styles.Grass.Text))
		local plank = SK.Plank(holder(400, 200), { Text = "Put in team", Style = "Grass" })
		T.check(sameColor(plank.Block.Face.Label.TextColor3, Sg.OnGrass), "plank tokens: a Grass plank's label draws dark green")
		local navy = SK.Plank(holder(400, 200), { Text = "v6", Style = "Navy" })
		T.check(sameColor(navy.Block.BackgroundColor3, Sg.GoldLip), "plank tokens: a Navy plank's edge draws gold lip")
		K.flushErrors("signkit_style_tokens")
	end)

	-- (e) the header's rim is the frame's thickness, so the wood edge runs straight from the header down the frame
	S.signkit_header_rim_matches_frame = guarded("signkit_header_rim_matches_frame", function()
		local SK = shared("SignKit")
		if not SK then
			return
		end
		local Z = SK.Sizes
		T.eq(Z.Rim, Z.Frame, "header rim: Sizes.Rim = Sizes.Frame")
		local win = holder(500, 400)
		local _, plate = SK.Header(win, { Title = "SETTINGS" })
		local body = SK.Body(SK.Frame(win, { Y = Z.HeadH }))
		T.check(plate.Position.X.Offset == body.Position.X.Offset and plate.Size.X.Offset == body.Size.X.Offset,
			"header rim: the navy plate and the stone body have the same left and right edges", fmt("plate %d,%d body %d,%d", plate.Position.X.Offset, plate.Size.X.Offset, body.Position.X.Offset, body.Size.X.Offset))
		local inst = K.moduleInstance("first/LoadingScreen") or K.moduleInstance("first/LoadingScreen.client")
		local src = tostring(inst and inst.Source or "")
		if src == "" then
			local fh = io.open("src/first/LoadingScreen.client.lua", "r")
			src = fh and fh:read("*a") or ""
			if fh then
				fh:close()
			end
		end
		local rim, frameW = tonumber(src:match("\n%s*RIM = (%d+),")), tonumber(src:match("\n%s*FRAME = (%d+),"))
		T.check(rim ~= nil and rim == Z.Rim and frameW == Z.Frame, "header rim: the loading screen's copy keeps RIM = FRAME = SignKit's", fmt("RIM %s FRAME %s", tostring(rim), tostring(frameW)))
		K.flushErrors("signkit_header_rim_matches_frame")
	end)

	-- (f) PixelIcon: a size under 9 px clamps to 9 (one px a cell); a size between multiples of 9 warns once per size
	S.pixelicon_clamp_and_warn = guarded("pixelicon_clamp_and_warn", function()
		local PI = shared("PixelIcon")
		if not PI then
			return
		end
		local parent = holder(100, 100)
		local tiny = PI.New(parent, "paw", 5)
		T.check(tiny and tiny.Size == UDim2.fromOffset(9, 9), "pixelicon clamp: 5 px draws at 9 x 9", tiny and tostring(tiny.Size) or "nil")
		local covered = 0
		for _, f in ipairs(tiny and tiny:GetChildren() or {}) do
			if f:IsA("Frame") then
				covered = covered + f.Size.X.Offset * f.Size.Y.Offset
			end
		end
		T.eq(covered, 42, "pixelicon clamp: one px a cell (paw has 42 cells)")
		T.check(type(PI.Warned) == "table", "pixelicon warn: PixelIcon.Warned records the sizes warned about")
		local warned = PI.Warned or {}
		for k in pairs(warned) do
			warned[k] = nil
		end
		PI.New(parent, "paw", 18)
		PI.New(parent, "paw", 27)
		T.check(next(warned) == nil, "pixelicon warn: multiples of 9 never warn")
		PI.New(parent, "paw", 20)
		PI.New(parent, "gear", 20)
		PI.New(parent, "paw", 22)
		local n = 0
		for _ in pairs(warned) do
			n = n + 1
		end
		T.check(warned[20] == 1 and warned[22] == 1 and n == 2, "pixelicon warn: 20 and 22 px warn once each (20 asked twice)",
			fmt("20: %s, 22: %s, %d sizes", tostring(warned[20]), tostring(warned[22]), n))
		parent:Destroy()
		-- the 20 and 22 px warns are the ones asked for above: take them here (see pixelicon_run_merge_count)
		K.flushWarnings("pixelicon_clamp_and_warn", { "[PixelIcon] 20 px is not a multiple of 9", "[PixelIcon] 22 px is not a multiple of 9" })
		K.flushErrors("pixelicon_clamp_and_warn")
	end)

	-- (h) the Credits baseline (tools/fixtures/credits_tree_u1.txt) is rewritten only with smoke.py's explicit
	-- --record-credits-tree flag, never because NC_RECORD_CREDITS_TREE happens to be set during a normal run
	S.credits_record_needs_flag = guarded("credits_record_needs_flag", function()
		local getenv = os.getenv
		local had = ARGS.record_credits_tree
		local ok, err = pcall(function()
			os.getenv = function(name)
				if name == "NC_RECORD_CREDITS_TREE" then
					return "1"
				end
				return getenv(name)
			end
			ARGS.record_credits_tree = nil
			T.eq(creditsRecord(), false, "credits record: the env var alone never records (a normal run keeps the baseline)")
			ARGS.record_credits_tree = true
			T.eq(creditsRecord(), true, "credits record: smoke.py --record-credits-tree records")
		end)
		os.getenv = getenv
		ARGS.record_credits_tree = had
		T.check(ok, "credits record: the scenario ran", tostring(err))
		local fh = io.open("tools/smoke.py", "r")
		local py = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		T.check(py:find("--record-credits-tree", 1, true) ~= nil and py:find("record_credits_tree", 1, true) ~= nil, "credits record: smoke.py has the --record-credits-tree flag and passes it on")
		K.flushErrors("credits_record_needs_flag")
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

	-- (review) a fit helper on a Nunito label really measures it: the side hint (a Toast label) sizes its pill from the text,
	-- where a read of .Font (Unknown) made GetTextSize throw inside its pcall and left the pill at its 300 px maximum
	S.kitb_fit_measures_face_label = guarded("kitb_fit_measures_face_label", function()
		local KC = _G.KC
		local MC = KC and KC.M and KC.M.MenuController
		local inst = Mock.GetPath(ROOTS.shared .. "/Theme")
		local okT, Theme = false, nil
		if inst then
			okT, Theme = pcall(require, inst)
		end
		if not T.check(MC ~= nil and type(MC.Hint) == "function" and okT and type(Theme) == "table", "kitb fit: MenuController and Theme load") then
			return
		end
		local text = "kit B fit"
		MC.Hint(text, "info")
		KC.advance(0.1)
		local pg = game:GetService("Players").LocalPlayer.PlayerGui
		local label = nil
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == text then
				label = d
			end
		end
		if not T.check(label ~= nil, "kitb fit: the side hint shows the text") then
			return
		end
		local want = math.ceil(Theme.MeasureLabel(label).X) + 6
		T.check(label:GetAttribute("FontRole") == "Toast" and label.Font == Enum.Font.Unknown, "kitb fit: the hint is a Toast (Nunito ExtraBold) label", tostring(label.Font))
		T.check(label.Size.X.Offset == want and want < 300, "kitb fit: the hint pill is measured to its text (not the 300 px fallback)", fmt("%d px (want %d)", label.Size.X.Offset, want))
		KC.flushErrors("kitb_fit_measures_face_label")
	end)

	-- U2: the Credits window built from SignKit parts dumps exactly what the approved window dumped. The baseline was
	-- recorded from the window as it stood before the move (smoke.py --record-credits-tree rewrites it; never do that to
	-- make this pass: the file IS the owner's approved look)
	local CREDITS_TREE = "tools/fixtures/credits_tree_u1.txt"
	local CREDITS_SIZES = { { 1920, 1080, false }, { 1280, 720, false }, { 844, 390, true }, { 390, 844, true } }

	local function num(v)
		return fmt("%.1f", tonumber(v) or 0)
	end
	local function udim2(u)
		return fmt("{%s,%d,%s,%d}", num(u.X.Scale), u.X.Offset, num(u.Y.Scale), u.Y.Offset)
	end
	local function faceOf(obj)
		local ok, f = pcall(function()
			return obj.FontFace
		end)
		if ok and typeof(f) == "Font" then
			return tostring(f.Family):match("([%w]+)%.json") .. "/" .. tostring(f.Weight):match("[%w]+$") .. "/" .. tostring(f.Style):match("[%w]+$")
		end
		return "-"
	end
	-- one line per instance: its path (names; "#n" for a repeated name among siblings) and the properties that make the
	-- look: boxes, colours, texts, fonts, strokes, corners, gradients
	local function creditsLines(root)
		local lines = {}
		local function visit(obj, path)
			local seen = {}
			for _, c in ipairs(obj:GetChildren()) do
				seen[c.Name] = (seen[c.Name] or 0) + 1
				local p = path .. "/" .. c.Name .. (seen[c.Name] > 1 and ("#" .. seen[c.Name]) or "")
				local f = { p, c.ClassName }
				if c:IsA("GuiObject") then
					local ap, as = c.AbsolutePosition, c.AbsoluteSize
					f[#f + 1] = fmt("abs %s,%s %sx%s pos %s size %s anchor %s,%s rot %s z %d vis %s bg %s %s", num(ap.X), num(ap.Y), num(as.X), num(as.Y),
						udim2(c.Position), udim2(c.Size), num(c.AnchorPoint.X), num(c.AnchorPoint.Y), num(c.Rotation), c.ZIndex, tostring(c.Visible),
						hex(c.BackgroundColor3), fmt("%.2f", c.BackgroundTransparency))
				end
				if c:IsA("TextLabel") or c:IsA("TextButton") then
					f[#f + 1] = fmt("text %q %s %s face %s col %s stroke %s %s/%s wrap %s", c.Text, num(c.TextSize), tostring(c.Font), faceOf(c), hex(c.TextColor3),
						fmt("%.2f", c.TextStrokeTransparency), tostring(c.TextXAlignment), tostring(c.TextYAlignment), tostring(c.TextWrapped))
				end
				if c:IsA("ImageLabel") or c:IsA("ImageButton") then
					f[#f + 1] = fmt("image %q %s", c.Image, tostring(c.ScaleType))
				end
				if c:IsA("UICorner") then
					f[#f + 1] = fmt("radius %s,%d", num(c.CornerRadius.Scale), c.CornerRadius.Offset)
				elseif c:IsA("UIStroke") then
					f[#f + 1] = fmt("%s %s %s %s %s", hex(c.Color), num(c.Thickness), tostring(c.ApplyStrokeMode), tostring(c.LineJoinMode), fmt("%.2f", c.Transparency))
				elseif c:IsA("UIGradient") then
					local keys = {}
					for _, k in ipairs(c.Color.Keypoints) do
						keys[#keys + 1] = num(k.Time) .. "=" .. hex(k.Value)
					end
					f[#f + 1] = table.concat(keys, " ") .. " rot " .. num(c.Rotation)
				elseif c:IsA("UIAspectRatioConstraint") then
					f[#f + 1] = "ratio " .. fmt("%.3f", c.AspectRatio)
				end
				lines[#lines + 1] = table.concat(f, " | ")
				visit(c, p)
			end
		end
		visit(root, "")
		return lines
	end

	S.credits_unchanged_on_signkit = guarded("credits_unchanged_on_signkit", function()
		local MMC = require(Mock.GetPath(ROOTS["client"] .. "/Controllers/MainMenuController"))
		local UIS = game:GetService("UserInputService")
		local vp0 = Mock.Viewport
		local old = { UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		local all, kitParts = {}, {}
		for _, s in ipairs(CREDITS_SIZES) do
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = s[3], not s[3], not s[3]
			Mock.SetViewport(s[1], s[2])
			KC.advance(0.2)
			MMC.CloseWindows()
			MMC.OpenCredits()
			KC.advance(0.3)
			local holder = MMC.Window()
			if not T.check(holder ~= nil, "credits on signkit: the window opens at " .. s[1] .. "x" .. s[2]) then
				break
			end
			all[#all + 1] = fmt("== %dx%d", s[1], s[2])
			for _, line in ipairs(creditsLines(holder)) do
				all[#all + 1] = line
			end
			-- built from the kit: the roof, header, frame and body are SignKit parts
			for _, pair in ipairs({ { "Roof", "Roof" }, { "Head", "Header" }, { "Wood", "Frame" }, { "Body", "Body" } }) do
				local part = holder:FindFirstChild(pair[1], true)
				if not (part and part:GetAttribute("SignKit") == pair[2]) then
					kitParts[#kitParts + 1] = s[1] .. "x" .. s[2] .. " " .. pair[1]
				end
			end
		end
		MMC.CloseWindows()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[1], old[2], old[3]
		Mock.SetViewport(vp0.X, vp0.Y)
		KC.advance(0.2)
		local text = table.concat(all, "\n") .. "\n"
		if creditsRecord() then
			local fh = io.open(CREDITS_TREE, "w")
			if fh then
				fh:write(text)
				fh:close()
			end
			T.info("*credits on signkit: recorded " .. CREDITS_TREE .. " (" .. #all .. " lines)")
		end
		local fh = io.open(CREDITS_TREE, "r")
		local want = fh and fh:read("*a") or nil
		if fh then
			fh:close()
		end
		if T.check(want ~= nil, "credits on signkit: the approved window's dump exists (" .. CREDITS_TREE .. ")") then
			local got, exp = {}, {}
			for line in text:gmatch("([^\n]*)\n") do
				got[#got + 1] = line
			end
			for line in want:gsub("\r", ""):gmatch("([^\n]*)\n") do
				exp[#exp + 1] = line
			end
			local diffs = {}
			for i = 1, math.max(#got, #exp) do
				if got[i] ~= exp[i] then
					diffs[#diffs + 1] = fmt("line %d: want [%s] got [%s]", i, tostring(exp[i]), tostring(got[i]))
				end
			end
			T.check(#diffs == 0, fmt("credits on signkit: the window dumps the same boxes, colours, texts and fonts as the approved one (%d lines, 4 screens)", #exp),
				fmt("%d differ; %s", #diffs, table.concat(diffs, " || ", 1, math.min(#diffs, 3))))
		end
		table.sort(kitParts)
		T.check(#kitParts == 0, "credits on signkit: the roof, header, wood frame and body are SignKit parts (attribute SignKit)", table.concat(kitParts, ", "))
		KC.flushErrors("credits_unchanged_on_signkit")
	end)

	------------------------------------------------------------------------------------------------
	-- U3: the loading screen in kit B. Each scenario runs src/first/LoadingScreen.client.lua afresh (Mock.RunScript) and
	-- reads the NEW NimbusLoading it builds; the profile is held back (no Done) while it looks, then let go so the screen
	-- fades away before the next one.
	local LKC = _G.KC
	local LoadingH = {}

	function LoadingH.shared(name)
		local inst = Mock.GetPath(ROOTS.shared .. "/" .. name)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		return ok and mod or nil
	end
	function LoadingH.attr()
		local Config = LoadingH.shared("Config")
		return (Config and Config.Attr and Config.Attr.ProfileLoaded) or "ProfileLoaded"
	end
	-- runs the script once and returns the new NimbusLoading (nil when none was built); `opts.HideTheme` takes
	-- Shared.Theme away for the run (the caller puts it back with LoadingH.restoreTheme)
	function LoadingH.run(opts)
		opts = opts or {}
		local Players = game:GetService("Players")
		local lp = Players.LocalPlayer
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		local folder = ROOTS["first"] and Mock.GetPath(ROOTS["first"]) or nil
		local script = folder and folder:FindFirstChild("LoadingScreen") or nil
		if not script then
			return nil
		end
		if opts.Size then
			Mock.SetViewport(opts.Size[1], opts.Size[2])
			LKC.advance(0.1)
		end
		local before = {}
		for _, g in ipairs(pg:GetChildren()) do
			before[g] = true
		end
		lp:SetAttribute(LoadingH.attr(), nil)
		if opts.HideTheme then
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
			LoadingH.theme = shared and shared:FindFirstChild("Theme")
			LoadingH.sharedFolder = shared
			if LoadingH.theme then
				LoadingH.theme.Parent = nil
			end
		end
		Mock.RunScript(script)
		LKC.advance(opts.Wait or 0.6)
		for _, g in ipairs(pg:GetChildren()) do
			if not before[g] and g.Name == "NimbusLoading" then
				return g
			end
		end
		return nil
	end
	function LoadingH.restoreTheme()
		if LoadingH.theme and LoadingH.sharedFolder then
			LoadingH.theme.Parent = LoadingH.sharedFolder
		end
		LoadingH.theme = nil
	end
	-- lets the profile load so every loading screen finishes and fades away; the viewport goes back to 1920x1080
	function LoadingH.cleanup()
		LoadingH.restoreTheme()
		game:GetService("Players").LocalPlayer:SetAttribute(LoadingH.attr(), true)
		LKC.advance(4)
		Mock.SetViewport(1920, 1080)
		LKC.advance(0.1)
	end
	function LoadingH.texts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
				out[#out + 1] = d
			end
		end
		return out
	end
	function LoadingH.gold(row, Sign)
		local n = 0
		for i = 1, 12 do
			local b = row:FindFirstChild("Block" .. i)
			local face = b and b:FindFirstChild("Face")
			if face and sameColor(face.BackgroundColor3, Sign.Gold) then
				n = n + 1
			end
		end
		return n
	end

	-- the board of the pitch: two ropes, the flat awning roof, the navy header with NIMBUS CLIMB in LuckiestGuy (gold on
	-- navy, no outline), the 6 px wood frame round the stone body; width min(0.5 W, 620 design px) on a wide screen and the
	-- screen less a 16 px gutter on each side on a portrait phone; the board swings (its Swing turns, within 1.5 degrees)
	S.loading_board_parts = guarded("loading_board_parts", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme and Theme.Sign
		if not T.check(Sign ~= nil, "loading board: (setup) Theme.Sign loads") then
			return
		end
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 390, 844 } }) do
				local tag = s[1] .. "x" .. s[2]
				local gui = LoadingH.run({ Size = s })
				if not T.check(gui ~= nil, "loading board: the screen is built at " .. tag) then
					return
				end
				local board = gui:FindFirstChild("Board", true)
				local swing = gui:FindFirstChild("Swing", true)
				if not T.check(board ~= nil and swing ~= nil and board:IsDescendantOf(swing), "loading board: a Board hangs in a Swing at " .. tag) then
					return
				end
				local ropes, roof, head, wood = 0, nil, nil, nil
				for _, d in ipairs(swing:GetDescendants()) do
					local kind = d:GetAttribute("SignKit")
					if kind == "Rope" then
						ropes = ropes + 1
					elseif kind == "Roof" then
						roof = d
					elseif kind == "Header" then
						head = d
					elseif kind == "Frame" then
						wood = d
					end
				end
				T.eq(ropes, 2, "loading board: two ropes at " .. tag)
				local face = roof and roof:FindFirstChild("Face")
				T.check(roof ~= nil and face ~= nil and sameColor(face.BackgroundColor3, Sign.Roof) and roof.Size.X.Scale == 0 and roof.Size.Y.Offset == 18,
					"loading board: the flat awning roof (pink face, 18 px, a fixed offset width) at " .. tag, roof and tostring(roof.Size) or "missing")
				local plate = head and head:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				T.check(plate ~= nil and sameColor(plate.BackgroundColor3, Sign.Navy), "loading board: the navy header plank at " .. tag)
				if T.check(title ~= nil and title.Text == "NIMBUS CLIMB", "loading board: the header reads NIMBUS CLIMB at " .. tag, title and title.Text or "missing") then
					T.check(title:GetAttribute("FontRole") == "Title" and title.Font == Theme.Fonts.Title, "loading board: the title is the Title role (LuckiestGuy)", tostring(title.Font))
					T.check(sameColor(title.TextColor3, Sign.Gold) and title.TextStrokeTransparency >= 1 and #textStrokes(title) == 0,
						"loading board: gold on navy with no outline and no stroke", hex(title.TextColor3))
				end
				local body = wood and wood:FindFirstChild("Body")
				T.check(wood ~= nil and sameColor(wood.BackgroundColor3, Sign.Wood) and body ~= nil and body.Position.X.Offset == 6 and body.Position.Y.Offset == 6,
					"loading board: a 6 px wood frame round the body at " .. tag)
				T.check(body ~= nil and sameColor(body.BackgroundColor3, Sign.Stone), "loading board: the stone body at " .. tag)
				local want = s[1] < 700 and (s[1] - 32) or math.min(0.5 * s[1], 620 * Theme.ScreenFactor(s[2]))
				T.near(board.AbsoluteSize.X, want, 2, "loading board: the board is " .. math.floor(want) .. " px wide at " .. tag)
				-- the swing is one endless tween (the mock never applies an endless tween's goal: read its goal and info)
				local swingTween = nil
				for tw in pairs(Mock.ActiveTweens) do
					if tw.Instance == swing then
						swingTween = tw
					end
				end
				local goal = swingTween and Mock.TweenGoals(swingTween).Rotation
				local info = swingTween and swingTween.TweenInfo
				T.check(math.abs(swing.Rotation) <= 1.51 and goal ~= nil and math.abs(math.abs(goal) - 1.5) < 1e-6 and math.abs(goal - swing.Rotation) > 2.9,
					"loading board: the board swings from -1.5 to +1.5 degrees at " .. tag, fmt("%.2f -> %s", swing.Rotation, tostring(goal)))
				T.check(info ~= nil and info.RepeatCount < 0 and info.Reverses == true and info.EasingStyle == Enum.EasingStyle.Sine and math.abs(info.Time - 3.2) < 1e-6,
					"loading board: ...endlessly, back and forth, Sine, 3.2 s")
				LoadingH.cleanup()
			end
		end)
		LoadingH.cleanup()
		T.check(ok, "loading board: the scenario ran", tostring(err))
		LKC.flushErrors("loading_board_parts")
	end)

	-- 12 stone blocks that turn gold one by one: 0 %, 50 %, 100 % -> 0, 6, 12 gold, the caption follows, and a jump of
	-- several blocks is not drawn at once
	S.loading_progress_blocks = guarded("loading_progress_blocks", function()
		local Theme = LoadingH.shared("Theme")
		local ok, err = pcall(function()
			local gui = LoadingH.run()
			local row = gui and gui:FindFirstChild("BlockRow", true)
			if not T.check(row ~= nil and row:GetAttribute("SignKit") == "BlockRow", "loading blocks: a BlockRow is on the board") then
				return
			end
			local blocks = 0
			for _, c in ipairs(row:GetChildren()) do
				if c.Name:match("^Block%d+$") then
					blocks = blocks + 1
				end
			end
			T.eq(blocks, 12, "loading blocks: 12 blocks")
			local caption = gui:FindFirstChild("Caption", true)
			for _, p in ipairs({ { 0, 0 }, { 0.5, 6 }, { 1, 12 } }) do
				gui:SetAttribute("Progress", p[1])
				if p[2] > 0 then
					LKC.advance(0.05)
					T.check(LoadingH.gold(row, Theme.Sign) < p[2], "loading blocks: the blocks turn gold one by one (not all at once) towards " .. p[2])
				end
				LKC.advance(2)
				T.eq(LoadingH.gold(row, Theme.Sign), p[2], fmt("loading blocks: %d%% -> %d gold blocks", p[1] * 100, p[2]))
				T.check(caption ~= nil and caption.Text:find(math.floor(p[1] * 100) .. "%", 1, true) ~= nil, fmt("loading blocks: the caption says %d%%", p[1] * 100), caption and caption.Text or "missing")
			end
		end)
		LoadingH.cleanup()
		T.check(ok, "loading blocks: the scenario ran", tostring(err))
		LKC.flushErrors("loading_progress_blocks")
	end)

	-- no UICorner anywhere on the screen (the kit is square blocks; the round puffs and dot sparkles are gone)
	S.loading_no_round_corners = guarded("loading_no_round_corners", function()
		local ok, err = pcall(function()
			local gui = LoadingH.run({ Wait = 6.6 })
			if not T.check(gui ~= nil, "loading corners: (setup) the screen is built") then
				return
			end
			local round = {}
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("UICorner") then
					round[#round + 1] = d.Parent and d.Parent.Name or "?"
				end
			end
			T.check(#round == 0, "loading corners: no UICorner on the loading screen", table.concat(round, ", "))
		end)
		LoadingH.cleanup()
		T.check(ok, "loading corners: the scenario ran", tostring(err))
		LKC.flushErrors("loading_no_round_corners")
	end)

	-- no neon: no UIStroke, no glow, no classic text stroke, no gradient but the sky's, none of the old neon colours
	S.loading_no_neon_no_stroke = guarded("loading_no_neon_no_stroke", function()
		local NEON = { "#40E2EC", "#B068FF", "#3C3296", "#BE6EC8", "#96F6FF" }
		local ok, err = pcall(function()
			local gui = LoadingH.run({ Wait = 6.6 })
			if not T.check(gui ~= nil, "loading neon: (setup) the screen is built") then
				return
			end
			local strokes, grads, classic, neon = {}, {}, {}, {}
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("UIStroke") then
					strokes[#strokes + 1] = d.Parent and d.Parent.Name or "?"
				elseif d:IsA("UIGradient") and not (d.Parent and d.Parent.Name == "Sky") then
					grads[#grads + 1] = d.Parent and d.Parent.Name or "?"
				end
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextStrokeTransparency < 1 then
					classic[#classic + 1] = d.Name
				end
				if d:IsA("GuiObject") and d.BackgroundTransparency < 1 then
					for _, h in ipairs(NEON) do
						if hex(d.BackgroundColor3) == h then
							neon[#neon + 1] = d.Name .. " " .. h
						end
					end
				end
			end
			T.check(#strokes == 0, "loading neon: no UIStroke (no neon edge, no glow ring, no outline)", table.concat(strokes, ", "))
			T.check(#grads == 0, "loading neon: no gradient but the sky's", table.concat(grads, ", "))
			T.check(#classic == 0, "loading neon: no classic text stroke", table.concat(classic, ", "))
			T.check(#neon == 0, "loading neon: none of the old neon / violet colours", table.concat(neon, ", "))
		end)
		LoadingH.cleanup()
		T.check(ok, "loading neon: the scenario ran", tostring(err))
		LKC.flushErrors("loading_no_neon_no_stroke")
	end)

	-- the screen's own copy of the kit tokens (drawn before Theme exists) equals Theme.Sign, and its sizes SignKit.Sizes
	S.loading_tokens_match_theme = guarded("loading_tokens_match_theme", function()
		local Theme = LoadingH.shared("Theme")
		local SignKit = LoadingH.shared("SignKit")
		if not T.check(Theme ~= nil and SignKit ~= nil, "loading tokens: (setup) Theme and SignKit load") then
			return
		end
		local Sign, Z = Theme.Sign, SignKit.Sizes
		local ok, err = pcall(function()
			local gui = LoadingH.run({ HideTheme = true })
			local board = gui and gui:FindFirstChild("Board", true)
			if not T.check(board ~= nil, "loading tokens: (setup) the board is drawn before Theme") then
				return
			end
			local bad = {}
			local function want(obj, key, what)
				if not (obj and sameColor(obj.BackgroundColor3, Sign[key])) then
					bad[#bad + 1] = what .. " ~= Theme.Sign." .. key .. " (" .. (obj and hex(obj.BackgroundColor3) or "missing") .. ")"
				end
			end
			local roof = board:FindFirstChild("Roof")
			want(roof, "RoofEdge", "roof edge")
			want(roof and roof:FindFirstChild("Face"), "Roof", "roof face")
			want(roof and roof:FindFirstChild("Face") and roof.Face:FindFirstChild("Lip"), "RoofLip", "roof lip")
			local head = board:FindFirstChild("Head")
			want(head, "Wood", "header rim")
			want(head and head:FindFirstChild("Plate"), "Navy", "header plate")
			local wood = board:FindFirstChild("Wood")
			want(wood, "Wood", "frame")
			local body = wood and wood:FindFirstChild("Body")
			want(body, "Stone", "body")
			want(body and body:FindFirstChild("Lip"), "StoneLip", "body lip")
			-- the blocks already follow the progress before Theme: back to 0 % to read an empty block
			gui:SetAttribute("Progress", 0)
			LKC.advance(0.1)
			local row = board:FindFirstChild("BlockRow", true)
			local b1 = row and row:FindFirstChild("Block1")
			want(b1, "Wood", "block edge")
			want(b1 and b1:FindFirstChild("Face"), "Stone", "empty block")
			want(b1 and b1:FindFirstChild("Face") and b1.Face:FindFirstChild("Lip"), "StoneLip", "empty block lip")
			local rope = nil
			for _, d in ipairs(gui:GetDescendants()) do
				if d:GetAttribute("SignKit") == "Rope" then
					rope = d
				end
			end
			want(rope, "Post", "rope")
			want(rope and rope:FindFirstChild("Shade"), "Wood", "rope shade")
			gui:SetAttribute("Progress", 1)
			LKC.advance(2)
			want(b1 and b1:FindFirstChild("Face"), "Gold", "gold block")
			want(b1 and b1:FindFirstChild("Face") and b1.Face:FindFirstChild("Lip"), "GoldLip", "gold block lip")
			T.check(#bad == 0, "loading tokens: every colour of the board drawn before Theme equals Theme.Sign", table.concat(bad, "; "))
			local sizes = {}
			if not (roof and roof.Size.Y.Offset == Z.RoofH) then
				sizes[#sizes + 1] = "roof height"
			end
			if not (rope and rope.Size.X.Offset == Z.RopeW) then
				sizes[#sizes + 1] = "rope width"
			end
			if not (body and body.Position.X.Offset == Z.Frame) then
				sizes[#sizes + 1] = "frame"
			end
			local f1 = b1 and b1:FindFirstChild("Face")
			if not (f1 and f1.Position.X.Offset == Z.BlockEdge and f1:FindFirstChild("Lip") and f1.Lip.Size.Y.Offset == Z.BlockLip) then
				sizes[#sizes + 1] = "block edge / lip"
			end
			T.check(#sizes == 0, "loading tokens: the board's sizes equal SignKit.Sizes", table.concat(sizes, ", "))
		end)
		LoadingH.cleanup()
		T.check(ok, "loading tokens: the scenario ran", tostring(err))
		LKC.flushErrors("loading_tokens_match_theme")
	end)

	-- before Shared.Theme replicates: the sky (127,196,242) -> (207,234,252), its stepped cloud rows (3-4 Frames a puff,
	-- each row 12 px narrower on each side than the one under it) and the whole board are there; no text yet (fonts only
	-- through Theme roles)
	S.loading_shows_before_theme = guarded("loading_shows_before_theme", function()
		local ok, err = pcall(function()
			local gui = LoadingH.run({ HideTheme = true })
			if not T.check(gui ~= nil, "loading before theme: the screen is built without Theme") then
				return
			end
			local sky = gui:FindFirstChild("Sky")
			local grad = sky and sky:FindFirstChildOfClass("UIGradient")
			local keys = grad and grad.Color.Keypoints or {}
			T.check(#keys >= 2 and hex(keys[1].Value) == "#7FC4F2" and hex(keys[#keys].Value) == "#CFEAFC",
				"loading before theme: the day sky runs (127,196,242) -> (207,234,252)", #keys > 0 and (hex(keys[1].Value) .. " -> " .. hex(keys[#keys].Value)) or "no gradient")
			local clouds = sky and sky:FindFirstChild("Clouds")
			local puffs, badPuffs = 0, {}
			for _, puff in ipairs(clouds and clouds:GetChildren() or {}) do
				if puff:IsA("Frame") then
					puffs = puffs + 1
					local rows = {}
					for _, r in ipairs(puff:GetChildren()) do
						local n = tonumber(r.Name:match("^Row(%d+)$"))
						if n then
							rows[n] = r
						end
					end
					local okRows = #rows >= 3 and #rows <= 4
					for i = 2, #rows do
						okRows = okRows and (rows[i - 1].Size.X.Offset - rows[i].Size.X.Offset == 24)
					end
					if not okRows then
						badPuffs[#badPuffs + 1] = puff.Name
					end
				end
			end
			T.check(puffs >= 4, "loading before theme: stepped cloud puffs in the sky", tostring(puffs))
			T.check(#badPuffs == 0, "loading before theme: every puff is 3-4 rows, each 12 px narrower on each side", table.concat(badPuffs, ", "))
			local parts = {}
			for _, name in ipairs({ "Swing", "Board", "Roof", "Head", "Wood", "BlockRow" }) do
				local p = gui:FindFirstChild(name, true)
				if not (p and p.Visible) then
					parts[#parts + 1] = name
				end
			end
			T.check(#parts == 0, "loading before theme: the board (ropes, roof, header, frame, body, blocks) shows before Theme", table.concat(parts, ", "))
			T.eq(#LoadingH.texts(gui), 0, "loading before theme: no text yet")
			LoadingH.restoreTheme()
			LKC.advance(0.6)
			local title = gui:FindFirstChild("Title", true)
			T.check(title ~= nil and title.Text == "NIMBUS CLIMB", "loading before theme: the title appears once Theme arrives")
			local boards = 0
			for _, d in ipairs(gui:GetDescendants()) do
				if d.Name == "Board" then
					boards = boards + 1
				end
			end
			T.eq(boards, 1, "loading before theme: the same board stays (no second board when Theme arrives)")
		end)
		LoadingH.cleanup()
		T.check(ok, "loading before theme: the scenario ran", tostring(err))
		LKC.flushErrors("loading_shows_before_theme")
	end)

	-- SKIP is a SignKit plank with the pixel arrow (no "▶" glyph) and still finishes the screen
	S.loading_skip_is_plank = guarded("loading_skip_is_plank", function()
		local ok, err = pcall(function()
			local gui = LoadingH.run({ Wait = 6.6 })
			local skip = gui and gui:FindFirstChild("Skip", true)
			if not T.check(skip ~= nil and skip.Visible, "loading skip: SKIP shows after SkipAfter") then
				return
			end
			T.check(skip:IsA("TextButton") and skip:GetAttribute("SignKit") == "Plank", "loading skip: SKIP is a SignKit plank", skip.ClassName)
			local arrow, label = false, nil
			for _, d in ipairs(skip:GetDescendants()) do
				if d:GetAttribute("PixelIcon") == "arrow" then
					arrow = true
				end
				if d:IsA("TextLabel") and d.Text ~= "" then
					label = d
				end
			end
			T.check(arrow, "loading skip: the plank carries the pixel arrow")
			T.check(label ~= nil and label.Text == "SKIP", "loading skip: the plank reads SKIP", label and label.Text or "no label")
			local glyph = {}
			for _, t in ipairs(LoadingH.texts(gui)) do
				if t.Text:find("\226\150\182", 1, true) then
					glyph[#glyph + 1] = t.Name
				end
			end
			T.check(#glyph == 0, "loading skip: no text glyph arrow anywhere on the screen", table.concat(glyph, ", "))
			Mock.Click(skip)
			LKC.advance(0.3)
			T.eq(gui:GetAttribute("Done"), true, "loading skip: the plank finishes the loading screen")
		end)
		LoadingH.cleanup()
		T.check(ok, "loading skip: the scenario ran", tostring(err))
		LKC.flushErrors("loading_skip_is_plank")
	end)

	-- the owner's picks (logo, lobby render, mascot) are TextureIds keys named in Config.Loading.Images; none set -> no
	-- image at all (the typed title, the flat sky and its clouds); each set -> its ImageLabel, the fallback it replaces off
	S.loading_images_optional = guarded("loading_images_optional", function()
		local Config = LoadingH.shared("Config")
		local ids = LoadingH.shared("TextureIds")
		local keys = Config and Config.Loading and Config.Loading.Images
		if not T.check(type(ids) == "table" and type(keys) == "table" and type(keys.Logo) == "string" and type(keys.Backdrop) == "string" and type(keys.Mascot) == "string",
			"loading images: (setup) Config.Loading.Images names the Logo, Backdrop and Mascot keys") then
			return
		end
		local saved = { ids[keys.Logo], ids[keys.Backdrop], ids[keys.Mascot] }
		local ok, err = pcall(function()
			T.check((tonumber(ids[keys.Logo]) or 0) == 0 and (tonumber(ids[keys.Backdrop]) or 0) == 0 and (tonumber(ids[keys.Mascot]) or 0) == 0,
				"loading images: tonight no image id is set (the morning picks)")
			local gui = LoadingH.run()
			if not T.check(gui ~= nil, "loading images: (setup) the screen is built") then
				return
			end
			local images = {}
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then
					images[#images + 1] = d.Name
				end
			end
			T.check(#images == 0, "loading images: ids 0 -> no image on the screen", table.concat(images, ", "))
			local title = gui:FindFirstChild("Title", true)
			local clouds = gui:FindFirstChild("Clouds", true)
			T.check(title ~= nil and title.Visible and clouds ~= nil and clouds.Visible, "loading images: ids 0 -> the typed title and the cloud sky")
			LoadingH.cleanup()
			ids[keys.Logo], ids[keys.Backdrop], ids[keys.Mascot] = 101, 202, 303
			local g2 = LoadingH.run()
			if not T.check(g2 ~= nil, "loading images: (setup) the screen is built with the ids set") then
				return
			end
			local logo = g2:FindFirstChild("Logo", true)
			local back = g2:FindFirstChild("Backdrop", true)
			local mascot = g2:FindFirstChild("Mascot", true)
			T.check(logo ~= nil and logo:IsA("ImageLabel") and logo.Image == "rbxassetid://101", "loading images: the logo id -> a Logo image in the header", logo and logo.Image or "missing")
			local t2 = g2:FindFirstChild("Title", true)
			T.check(t2 == nil or t2.Visible == false, "loading images: ...and the typed title is off")
			T.check(back ~= nil and back:IsA("ImageLabel") and back.Image == "rbxassetid://202", "loading images: the lobby render id -> a Backdrop image", back and back.Image or "missing")
			local c2 = g2:FindFirstChild("Clouds", true)
			T.check(c2 == nil or c2.Visible == false, "loading images: ...and the drawn clouds are off")
			T.check(mascot ~= nil and mascot:IsA("ImageLabel") and mascot.Image == "rbxassetid://303", "loading images: the mascot id -> a Mascot image on the blocks", mascot and mascot.Image or "missing")
		end)
		ids[keys.Logo], ids[keys.Backdrop], ids[keys.Mascot] = saved[1], saved[2], saved[3]
		LoadingH.cleanup()
		T.check(ok, "loading images: the scenario ran", tostring(err))
		LKC.flushErrors("loading_images_optional")
	end)

	-- (U3 review) the board fits every screen: portrait tablets, landscape phones (360-375 px tall) and the grid sizes.
	-- The title stays on the plate with 12 design px each side, the board (plus the swing's droop: half its width times
	-- sin 1.5 degrees, the mock does not turn it) ends above the tip card and clear of SKIP, SKIP clear of the tip card,
	-- the board below Roblox's top bar, the blocks and the caption inside the stone body
	S.loading_board_fits = guarded("loading_board_fits", function()
		local Theme = LoadingH.shared("Theme")
		if not T.check(Theme ~= nil and Theme.Measure ~= nil, "loading fit: (setup) Theme.Measure loads") then
			return
		end
		local function rect(obj)
			local p, s = obj.AbsolutePosition, obj.AbsoluteSize
			return { X = p.X, Y = p.Y, R = p.X + s.X, B = p.Y + s.Y }
		end
		local function overlap(a, b)
			return a.X < b.R and b.X < a.R and a.Y < b.B and b.Y < a.B
		end
		local function show(r)
			return fmt("%d,%d..%d,%d", r.X, r.Y, r.R, r.B)
		end
		local ok, err = pcall(function()
			local sizes = { { 768, 1024 }, { 834, 1194 }, { 640, 360 }, { 667, 375 }, { 800, 360 }, { 740, 360 }, { 720, 360 },
				{ 844, 390 }, { 390, 844 }, { 1920, 1080 }, { 1280, 720 } }
			for _, s in ipairs(sizes) do
				local tag = s[1] .. "x" .. s[2]
				local f = Theme.ScreenFactor(s[2])
				local gui = LoadingH.run({ Size = s })
				local board = gui and gui:FindFirstChild("Board", true)
				local plate = gui and gui:FindFirstChild("Plate", true)
				local title = plate and plate:FindFirstChild("Title")
				local tip = gui and gui:FindFirstChild("TipCard", true)
				local skip = gui and gui:FindFirstChild("Skip", true)
				local body = gui and gui:FindFirstChild("Body", true)
				local row = gui and gui:FindFirstChild("BlockRow", true)
				local caption = gui and gui:FindFirstChild("Caption", true)
				if not T.check(board and plate and title and tip and skip and body and row and caption, "loading fit: (setup) the board, tip card and SKIP at " .. tag) then
					return
				end
				local width = Theme.Measure(title.Text, "Title", title.TextSize).X
				local room = plate.AbsoluteSize.X / f - 24
				T.check(width <= room, "loading fit: the title stays on the plate with 12 px each side at " .. tag,
					fmt("title %d at %d px, plate room %.0f", width, title.TextSize, room))
				local b, t, k = rect(board), rect(tip), rect(skip)
				local droop = math.ceil(0.5 * board.AbsoluteSize.X * math.sin(math.rad(1.5)))
				local swung = { X = b.X, Y = b.Y, R = b.R, B = b.B + droop }
				T.check(swung.B <= t.Y, "loading fit: the swinging board ends above the tip card at " .. tag, show(swung) .. " vs tip " .. show(t))
				T.check(not overlap(swung, k), "loading fit: the swinging board is clear of SKIP at " .. tag, show(swung) .. " vs skip " .. show(k))
				T.check(not overlap(k, t), "loading fit: SKIP is clear of the tip card at " .. tag, show(k) .. " vs tip " .. show(t))
				T.check(b.Y >= Mock.TopInset, "loading fit: the board hangs below Roblox's top bar at " .. tag, show(b))
				local inside = rect(body)
				local r, c = rect(row), rect(caption)
				T.check(r.Y >= inside.Y and c.B <= inside.B and r.X >= inside.X and r.R <= inside.R,
					"loading fit: the blocks and the caption sit inside the stone body at " .. tag, show(r) .. " / " .. show(c) .. " in " .. show(inside))
				LoadingH.cleanup()
			end
		end)
		LoadingH.cleanup()
		T.check(ok, "loading fit: the scenario ran", tostring(err))
		LKC.flushErrors("loading_board_fits")
	end)

	------------------------------------------------------------------------------------------------
	-- U4: the main menu Signboard. Each scenario opens the title screen afresh at its size and input (MenuH.open: MenuPlay
	-- counts as sent, so PLAY never spawns anything), reads it after the entrance, and closes it with PLAY (MenuH.close).
	local MenuH = {}

	function MenuH.mmc()
		return require(Mock.GetPath(ROOTS["client"] .. "/Controllers/MainMenuController"))
	end
	-- opts: Size = { w, h }, Input = "Keyboard" | "Touch" | "Gamepad", Wait (seconds after Open; default 1.8, the entrance done)
	function MenuH.open(opts)
		opts = opts or {}
		local UIS = game:GetService("UserInputService")
		MenuH.old = MenuH.old or { Mock.Viewport, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, UIS.GamepadEnabled }
		local input = opts.Input or "Keyboard"
		UIS.TouchEnabled = input == "Touch"
		UIS.KeyboardEnabled = input == "Keyboard"
		UIS.MouseEnabled = input == "Keyboard"
		UIS.GamepadEnabled = input == "Gamepad"
		local size = opts.Size or { 1920, 1080 }
		Mock.SetViewport(size[1], size[2])
		LKC.advance(0.1)
		local Config = LoadingH.shared("Config")
		Config.MainMenu.Enabled = true
		local MMC = MenuH.mmc()
		MMC._M.SentPlay = true -- PLAY closes the screen without a MenuPlay (no character dance in these scenarios)
		MMC.Open()
		LKC.advance(opts.Wait or 1.8)
		local pg = game:GetService("Players").LocalPlayer.PlayerGui
		local gui = pg:FindFirstChild("NimbusMainMenu")
		return gui and gui:FindFirstChild("Menu"), MMC
	end
	function MenuH.close()
		local MMC = MenuH.mmc()
		if MMC.IsOpen() then
			MMC.CloseWindows()
			MMC.Play()
			LKC.advance(1.5)
		end
		local Config = LoadingH.shared("Config")
		Config.MainMenu.Enabled = false
		local old = MenuH.old
		if old then
			local UIS = game:GetService("UserInputService")
			Mock.SetViewport(old[1].X, old[1].Y)
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled, UIS.GamepadEnabled = old[2], old[3], old[4], old[5]
			LKC.advance(0.1)
		end
		MenuH.old = nil
	end
	function MenuH.rect(obj)
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return { X = p.X, Y = p.Y, R = p.X + s.X, B = p.Y + s.Y }
	end
	function MenuH.overlap(a, b)
		return a.X < b.R - 0.5 and b.X < a.R - 0.5 and a.Y < b.B - 0.5 and b.Y < a.B - 0.5
	end
	function MenuH.show(r)
		return fmt("%d,%d..%d,%d", r.X, r.Y, r.R, r.B)
	end
	-- visible: the object and every GuiObject above it inside the menu
	function MenuH.shown(obj)
		local o = obj
		while o and not o:IsA("LayerCollector") do
			if o:IsA("GuiObject") and not o.Visible then
				return false
			end
			o = o.Parent
		end
		return true
	end
	function MenuH.kinds(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			local kind = d:GetAttribute("SignKit")
			if kind then
				out[kind] = out[kind] or {}
				table.insert(out[kind], d)
			end
		end
		return out
	end
	function MenuH.find(root, name)
		return root and root:FindFirstChild(name, true) or nil
	end

	-- the board of the pitch on the title screen: two ropes, the flat awning, the navy header with Config.MainMenu.Header
	-- ("NIMBUS CLIMB", Title role, gold, no outline), the wood frame and the stone body; 60 design px from the left, 440 wide
	S.menu_board_parts = guarded("menu_board_parts", function()
		local Theme = LoadingH.shared("Theme")
		local Config = LoadingH.shared("Config")
		local Sign = Theme and Theme.Sign
		local ok, err = pcall(function()
			T.eq(Config.MainMenu.Header, "NIMBUS CLIMB", "menu board: Config.MainMenu.Header is NIMBUS CLIMB (the greeting is a one-line change there)")
			for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 } }) do
				local tag = s[1] .. "x" .. s[2]
				local f = Theme.ScreenFactor(s[2])
				local menu = MenuH.open({ Size = s })
				local board = MenuH.find(menu, "Board")
				local swing = MenuH.find(menu, "Swing")
				if not T.check(board ~= nil and swing ~= nil and board:IsDescendantOf(swing), "menu board: a Board hangs in a Swing at " .. tag) then
					return
				end
				local kinds = MenuH.kinds(swing)
				T.eq(#(kinds.Rope or {}), 2, "menu board: two ropes at " .. tag)
				local roof = (kinds.Roof or {})[1]
				local face = roof and roof:FindFirstChild("Face")
				T.check(roof ~= nil and face ~= nil and sameColor(face.BackgroundColor3, Sign.Roof) and roof.Size.X.Scale == 0,
					"menu board: the flat awning roof (pink face, a fixed offset width) at " .. tag, roof and tostring(roof.Size) or "missing")
				local head = (kinds.Header or {})[1]
				local plate = head and head:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				T.check(plate ~= nil and sameColor(plate.BackgroundColor3, Sign.Navy), "menu board: the navy header plank at " .. tag)
				if T.check(title ~= nil and title.Text == "NIMBUS CLIMB", "menu board: the header reads NIMBUS CLIMB at " .. tag, title and title.Text or "missing") then
					T.check(title:GetAttribute("FontRole") == "Title" and title.Font == Theme.Fonts.Title, "menu board: the title is the Title role (LuckiestGuy)", tostring(title.Font))
					T.check(sameColor(title.TextColor3, Sign.Gold) and title.TextStrokeTransparency >= 1 and #textStrokes(title) == 0,
						"menu board: gold on navy with no outline and no stroke", hex(title.TextColor3))
				end
				local wood = (kinds.Frame or {})[1]
				local body = (kinds.Body or {})[1]
				T.check(wood ~= nil and sameColor(wood.BackgroundColor3, Sign.Wood), "menu board: the wood frame at " .. tag)
				T.check(body ~= nil and sameColor(body.BackgroundColor3, Sign.Stone), "menu board: the stone body at " .. tag)
				local r = MenuH.rect(board)
				T.near(r.X, 60 * f, 2, "menu board: the board stands 60 design px from the left at " .. tag, MenuH.show(r))
				T.near(r.R - r.X, 440 * f, 2, "menu board: the board is 440 design px wide at " .. tag, MenuH.show(r))
				T.check(r.Y >= Mock.TopInset and r.B <= s[2] - 8, "menu board: the board is on screen below Roblox's top bar at " .. tag, MenuH.show(r))
				MenuH.close()
			end
		end)
		MenuH.close()
		T.check(ok, "menu board: the scenario ran", tostring(err))
		LKC.flushErrors("menu_board_parts")
	end)

	-- no shade over the world: no Shade frame, and nothing on the screen paints half of it (the portrait board is a third)
	S.menu_no_shade = guarded("menu_no_shade", function()
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 390, 844, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local menu = MenuH.open({ Size = s, Input = s[3] })
				if not T.check(menu ~= nil, "menu shade: the menu is built at " .. tag) then
					return
				end
				T.check(menu:FindFirstChild("Shade") == nil, "menu shade: no Shade frame over the screen at " .. tag)
				local big = {}
				for _, d in ipairs({ menu, unpack(menu:GetDescendants()) }) do
					if d:IsA("GuiObject") and d.BackgroundTransparency < 0.99 and MenuH.shown(d) then
						local a = d.AbsoluteSize
						if a.X * a.Y > 0.5 * s[1] * s[2] then
							big[#big + 1] = d.Name
						end
					end
				end
				T.check(#big == 0, "menu shade: nothing paints over half the screen at " .. tag, table.concat(big, ", "))
				MenuH.close()
			end
		end)
		MenuH.close()
		T.check(ok, "menu shade: the scenario ran", tostring(err))
		LKC.flushErrors("menu_no_shade")
	end)

	-- PLAY: a green SignKit plank 72 design px tall, a 6 px darker lip, FredokaOne 40, the pixel triangle; the only green on
	-- the screen; SETTINGS and UPDATES are half-width stone planks 52 tall with the pixel gear and scroll
	S.menu_play_is_green_plank_only = guarded("menu_play_is_green_plank_only", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		local ok, err = pcall(function()
			local menu = MenuH.open()
			local play = MenuH.find(menu, "PlayButton")
			if not T.check(play ~= nil and play:GetAttribute("SignKit") == "Plank", "menu play: PLAY is a SignKit plank") then
				return
			end
			T.near(play.AbsoluteSize.Y, 72, 0.6, "menu play: PLAY is 72 tall")
			T.eq(play:GetAttribute("LipPx"), 6, "menu play: PLAY's lip is 6 px")
			local face = MenuH.find(play, "Face")
			local lip = MenuH.find(play, "Lip")
			T.check(face and sameColor(face.BackgroundColor3, Sign.Grass), "menu play: the face is grass green #6FCF6A", face and hex(face.BackgroundColor3) or "missing")
			T.check(lip and sameColor(lip.BackgroundColor3, Sign.GrassLip), "menu play: the lip is the darker green", lip and hex(lip.BackgroundColor3) or "missing")
			local label = MenuH.find(play, "Label")
			T.check(label and label.Text == "PLAY" and label:GetAttribute("FontRole") == "Button" and label.Font == Theme.Fonts.Button and label.TextSize == 40,
				"menu play: PLAY in FredokaOne 40 (Button role), no glyph", label and fmt("%q %s %s", label.Text, tostring(label.Font), tostring(label.TextSize)) or "missing")
			local icon = nil
			for _, d in ipairs(play:GetDescendants()) do
				if d:GetAttribute("PixelIcon") == "play" then
					icon = d
				end
			end
			T.check(icon ~= nil, "menu play: the pixel play triangle is on PLAY")
			-- one green action: every green fill on the screen is inside PLAY
			local greens = {}
			for _, d in ipairs(menu:GetDescendants()) do
				if d:IsA("GuiObject") and d.BackgroundTransparency < 0.99 and MenuH.shown(d) and not d:IsDescendantOf(play) then
					local c = d.BackgroundColor3
					if sameColor(c, Sign.Grass) or sameColor(c, Sign.GrassLip) or (c.G > c.R + 0.25 and c.G > c.B + 0.25) then
						greens[#greens + 1] = d:GetFullName()
					end
				end
			end
			T.check(#greens == 0, "menu play: PLAY is the only green action on the screen", table.concat(greens, ", "))
			for _, pair in ipairs({ { "SettingsButton", "gear" }, { "UpdatesButton", "scroll" } }) do
				local b = MenuH.find(menu, pair[1])
				local bf = b and MenuH.find(b, "Face")
				local hasIcon = false
				for _, d in ipairs(b and b:GetDescendants() or {}) do
					hasIcon = hasIcon or d:GetAttribute("PixelIcon") == pair[2]
				end
				T.check(b ~= nil and b:GetAttribute("SignKit") == "Plank" and bf and sameColor(bf.BackgroundColor3, Sign.Tile), "menu play: " .. pair[1] .. " is a stone plank")
				T.near(b and b.AbsoluteSize.Y or 0, 52, 0.6, "menu play: " .. pair[1] .. " is 52 tall")
				T.check(b and math.abs(b.AbsoluteSize.X - (play.AbsoluteSize.X - 12) / 2) <= 1.5, "menu play: " .. pair[1] .. " is half of PLAY's width (12 px gap)",
					b and tostring(b.AbsoluteSize.X) or "")
				T.check(hasIcon, "menu play: " .. pair[1] .. " carries the pixel " .. pair[2])
			end
		end)
		MenuH.close()
		T.check(ok, "menu play: the scenario ran", tostring(err))
		LKC.flushErrors("menu_play_is_green_plank_only")
	end)

	-- (U5 review) PLAY, SETTINGS and UPDATES: the label beside its pixel icon is auto-sized (Menu.plankIcon), so it never
	-- truncates (a 1 px auto-size shortfall under the board's UIScale would draw "PLA..."), and the text was fitted to
	-- the face less the icon and the gap: text + icon + gap fits the face's room, in design px, at every screen size
	S.menu_plank_labels_fit = guarded("menu_plank_labels_fit", function()
		local Theme = LoadingH.shared("Theme")
		local SK = LoadingH.shared("SignKit")
		local Z = SK.Sizes
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 1280, 720, "Keyboard" }, { 844, 390, "Touch" }, { 390, 844, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local menu = MenuH.open({ Size = s, Input = s[3] })
				for _, name in ipairs({ "PlayButton", "SettingsButton", "UpdatesButton" }) do
					local plank = MenuH.find(menu, name)
					local label = plank and MenuH.find(plank, "Label")
					local group = label and label.Parent
					local layout = group and group:FindFirstChildOfClass("UIListLayout")
					local icon = nil
					for _, c in ipairs(group and group:GetChildren() or {}) do
						if c:GetAttribute("PixelIcon") then
							icon = c
						end
					end
					if T.check(label ~= nil and icon ~= nil and layout ~= nil, "menu labels: " .. name .. " has its label and icon in a row at " .. tag) then
						T.check(label.TextTruncate == Enum.TextTruncate.None, "menu labels: " .. name .. "'s auto-sized label never truncates at " .. tag, tostring(label.TextTruncate))
						local w = Theme.Measure(label.Text, "Button", label.TextSize).X
						local room = plank.Size.X.Offset - 2 * Z.Edge - 2 * Z.LabelPad
						local used = w + icon.Size.X.Offset + layout.Padding.Offset
						T.check(used <= room or label.TextSize == 14, "menu labels: " .. name .. " text + icon + gap fits its face at " .. tag,
							fmt("%d + %d + %d px in %d at %d", w, icon.Size.X.Offset, layout.Padding.Offset, room, label.TextSize))
					end
				end
				MenuH.close()
			end
			-- today's three labels leave 60 px or more spare, so a label that just fits a bare face (5 px spare) proves the
			-- icon and the gap are taken off before the size steps down
			local MMC = MenuH.mmc()
			local text = "SETTINGS AND MORE"
			local width = Theme.Measure(text, "Button", 22).X + 2 * Z.Edge + 2 * Z.LabelPad + 5
			local plank = SK.Plank(Instance.new("Frame"), { Text = text, Width = width, TextSize = 22 })
			local icon = MMC._PlankIcon and MMC._PlankIcon(plank, "gear", 18, Theme.Sign.Text)
			local label = MenuH.find(plank, "Label")
			local layout = label and label.Parent:FindFirstChildOfClass("UIListLayout")
			if T.check(icon ~= nil and layout ~= nil, "menu labels: (tight) the icon row is built (MainMenuController._PlankIcon)") then
				local w = Theme.Measure(text, "Button", label.TextSize).X
				local used = w + icon.Size.X.Offset + layout.Padding.Offset
				T.check(used <= width - 2 * Z.Edge - 2 * Z.LabelPad and label.TextSize < 22, "menu labels: (tight) the label steps down to fit beside its icon",
					fmt("%d + %d + %d px in %d at %d", w, icon.Size.X.Offset, layout.Padding.Offset, width - 2 * Z.Edge - 2 * Z.LabelPad, label.TextSize))
			end
		end)
		MenuH.close()
		T.check(ok, "menu labels: the scenario ran", tostring(err))
		LKC.flushErrors("menu_plank_labels_fit")
	end)

	-- no neon kit on the title screen: no gradient, no rounded corner, no glow ring, no classic text stroke, no neon colour
	S.menu_no_neon_cards = guarded("menu_no_neon_cards", function()
		local Theme = LoadingH.shared("Theme")
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 844, 390, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local menu = MenuH.open({ Size = s, Input = s[3] })
				local bad = {}
				for _, d in ipairs(menu:GetDescendants()) do
					if d:IsA("UIGradient") or d:IsA("UICorner") then
						bad[#bad + 1] = d.ClassName .. " in " .. d.Parent.Name
					elseif d:IsA("UIStroke") and d.ApplyStrokeMode ~= Enum.ApplyStrokeMode.Contextual then
						bad[#bad + 1] = "a border ring on " .. d.Parent.Name
					elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextStrokeTransparency < 0.95 then
						bad[#bad + 1] = "a classic stroke on " .. d.Name
					elseif d:IsA("GuiObject") and d.BackgroundTransparency < 0.99 then
						for name, c in pairs(Theme.Neon) do
							if sameColor(d.BackgroundColor3, c) then
								bad[#bad + 1] = "neon " .. name .. " on " .. d.Name
							end
						end
					end
				end
				T.check(#bad == 0, "menu neon: no gradient, corner, glow ring, classic stroke or neon colour at " .. tag, table.concat(bad, "; ", 1, math.min(#bad, 8)))
				MenuH.close()
			end
		end)
		MenuH.close()
		T.check(ok, "menu neon: the scenario ran", tostring(err))
		LKC.flushErrors("menu_no_neon_cards")
	end)

	-- one NEW marker (the pixel star on UPDATES, while UpdateNotes.Latest > SeenNotes), no NEW pill, no ribbon
	S.menu_single_new_marker = guarded("menu_single_new_marker", function()
		local ok, err = pcall(function()
			local notes = LoadingH.shared("UpdateNotes")
			local CS = require(Mock.GetPath(ROOTS["client"] .. "/ClientSettings"))
			local want = (notes and notes.Latest or 0) > (tonumber(CS.Get("SeenNotes")) or 0)
			local menu = MenuH.open()
			local updates = MenuH.find(menu, "UpdatesButton")
			local badge = MenuH.find(menu, "NewBadge")
			T.check(badge ~= nil and badge:GetAttribute("PixelIcon") == "star" and updates and badge:IsDescendantOf(updates),
				"menu new: the NEW marker is the pixel star on UPDATES")
			local markers, newTexts = 0, {}
			for _, d in ipairs(menu:GetDescendants()) do
				if d:GetAttribute("PixelIcon") == "star" and MenuH.shown(d) then
					markers = markers + 1
				end
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(string.upper(d.Text), "NEW", 1, true) and MenuH.shown(d) then
					newTexts[#newTexts + 1] = d.Name
				end
			end
			T.eq(markers, want and 1 or 0, "menu new: exactly one NEW marker while there are unseen notes (" .. tostring(want) .. ")")
			T.check(#newTexts == 0, "menu new: no typed NEW pill or tag", table.concat(newTexts, ", "))
			T.check(MenuH.find(menu, "Ribbon") == nil, "menu new: the NEW ribbon is gone (one marker, not two)")
		end)
		MenuH.close()
		T.check(ok, "menu new: the scenario ran", tostring(err))
		LKC.flushErrors("menu_single_new_marker")
	end)

	-- the version: one Nunito line on the board "v6 · The Cute Blocks Update" that opens UPDATES; "v6" beside CREDITS (no
	-- made-up ".0"); CREDITS is a small wood tag on a rope
	S.menu_version_text = guarded("menu_version_text", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		local ok, err = pcall(function()
			local notes = LoadingH.shared("UpdateNotes")
			local latest = tostring(notes.Latest)
			local menu, MMC = MenuH.open()
			local line = MenuH.find(menu, "VersionLine")
			local board = MenuH.find(menu, "Board")
			if T.check(line ~= nil and (line:IsA("TextButton") or line:IsA("TextLabel")), "menu version: the version line exists") then
				T.eq(line.Text, "v" .. latest .. " \194\183 " .. notes.Notes[1].Title, "menu version: it reads 'v" .. latest .. " \194\183 " .. notes.Notes[1].Title .. "'")
				T.check(line:GetAttribute("FontRole") == "Body" or line:GetAttribute("FontRole") == "Label", "menu version: in Nunito (Body / Label role)", tostring(line:GetAttribute("FontRole")))
				T.check(board ~= nil and line:IsDescendantOf(board), "menu version: on the board")
				T.check(line:IsA("TextButton"), "menu version: it is a button")
				if line:IsA("TextButton") then
					Mock.Click(line)
					LKC.advance(0.3)
					T.eq(MMC._M.Win.Name, "Updates", "menu version: a click opens UPDATES")
					MMC.CloseWindows()
					LKC.advance(0.2)
				end
			end
			local version = MenuH.find(menu, "Version")
			T.eq(version and version.Text, "v" .. latest, "menu version: 'v" .. latest .. "' beside CREDITS, no '.0'")
			local credits = MenuH.find(menu, "CreditsButton")
			local cf = credits and MenuH.find(credits, "Face")
			T.check(credits ~= nil and credits:GetAttribute("SignKit") == "Plank" and cf and sameColor(cf.BackgroundColor3, Sign.Wood),
				"menu version: CREDITS is a wood tag (a SignKit plank in wood)")
			local tagRope = credits and credits.Parent and credits.Parent:FindFirstChild("Rope")
			T.check(tagRope ~= nil and tagRope:GetAttribute("SignKit") == "Rope", "menu version: ...on a rope")
			T.check(credits ~= nil and board ~= nil and not credits:IsDescendantOf(board), "menu version: the CREDITS tag hangs apart from the board")
			local dotted = {}
			for _, d in ipairs(menu:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(d.Text, "v%d+%.0") then
					dotted[#dotted + 1] = d.Name
				end
			end
			T.check(#dotted == 0, "menu version: no 'vN.0' anywhere", table.concat(dotted, ", "))
			if credits then
				Mock.Click(credits)
				LKC.advance(0.3)
				T.eq(MMC._M.Win.Name, "Credits", "menu version: the CREDITS tag opens Credits")
				MMC.CloseWindows()
				LKC.advance(0.2)
			end
		end)
		MenuH.close()
		T.check(ok, "menu version: the scenario ran", tostring(err))
		LKC.flushErrors("menu_version_text")
	end)

	-- the hint line on the board follows the input: keyboard, gamepad, touch
	S.menu_hint_per_input = guarded("menu_hint_per_input", function()
		local ok, err = pcall(function()
			for _, c in ipairs({ { "Keyboard", { 1920, 1080 }, "Press ENTER to play" }, { "Gamepad", { 1920, 1080 }, "Press A to play" },
				{ "Touch", { 844, 390 }, "Tap PLAY to jump in!" } }) do
				local menu = MenuH.open({ Input = c[1], Size = c[2] })
				local hint = MenuH.find(menu, "Hint")
				local board = MenuH.find(menu, "Board")
				T.eq(hint and hint.Text, c[3], "menu hint: " .. c[1] .. " reads '" .. c[3] .. "'")
				T.check(hint ~= nil and board ~= nil and hint:IsDescendantOf(board) and MenuH.shown(hint), "menu hint: shown on the board (" .. c[1] .. ")")
				MenuH.close()
			end
		end)
		MenuH.close()
		T.check(ok, "menu hint: the scenario ran", tostring(err))
		LKC.flushErrors("menu_hint_per_input")
	end)

	-- portrait: the board docks at the bottom, just above the thumbstick / jump zones, within the 16 px gutter; on every
	-- phone and tablet no button or text sits in a thumb zone or under Roblox's top-bar buttons, and nothing overlaps
	S.menu_portrait_docks_bottom = guarded("menu_portrait_docks_bottom", function()
		local ok, err = pcall(function()
			for _, s in ipairs({ { 390, 844, "Touch" }, { 360, 640, "Touch" }, { 412, 915, "Touch" }, { 768, 1024, "Touch" }, { 844, 390, "Touch" }, { 667, 375, "Touch" },
				{ 1280, 720, "Keyboard" }, { 1920, 1080, "Keyboard" } }) do
				local tag = s[1] .. "x" .. s[2]
				local W, Hh = s[1], s[2]
				local menu = MenuH.open({ Size = { W, Hh }, Input = s[3] })
				local board = MenuH.find(menu, "Board")
				if not T.check(board ~= nil, "menu dock: the board at " .. tag) then
					return
				end
				local b = MenuH.rect(board)
				local touch = s[3] == "Touch"
				local zoneW, zoneH = 0, 0
				if touch then
					if math.min(W, Hh) <= 500 then
						zoneW, zoneH = 104, 96
					else
						zoneW, zoneH = 206, 210
					end
				end
				if Hh > W then
					T.check(b.B <= Hh - zoneH - 4 and b.B >= Hh - zoneH - 48, "menu dock: the portrait board docks at the bottom, just above the thumb zones at " .. tag,
						MenuH.show(b) .. fmt(" (zones %d tall)", zoneH))
					T.check(b.X >= 15.5 and b.R <= W - 15.5, "menu dock: the board keeps the 16 px gutter at " .. tag, MenuH.show(b))
				end
				-- the thumb zones (bottom-left stick, bottom-right jump) and the top bar's button rows
				local zones = {}
				if touch then
					zones[#zones + 1] = { X = 0, Y = Hh - zoneH, R = zoneW, B = Hh, Name = "thumbstick" }
					zones[#zones + 1] = { X = W - zoneW, Y = Hh - zoneH, R = W, B = Hh, Name = "jump" }
				end
				zones[#zones + 1] = { X = 0, Y = 0, R = 120, B = Mock.TopInset, Name = "top-left buttons" }
				zones[#zones + 1] = { X = W - 70, Y = 0, R = W, B = Mock.TopInset, Name = "top-right menu" }
				local items = {}
				for _, d in ipairs(menu:GetDescendants()) do
					if MenuH.shown(d) and (d:IsA("TextButton") or ((d:IsA("TextLabel")) and d.Text ~= "")) then
						items[#items + 1] = d
					end
				end
				local hits, offs = {}, {}
				for _, d in ipairs(items) do
					local r = MenuH.rect(d)
					for _, z in ipairs(zones) do
						if MenuH.overlap(r, z) then
							hits[#hits + 1] = d.Name .. " in " .. z.Name
						end
					end
					if r.X < -0.5 or r.R > W + 0.5 or r.Y < -0.5 or r.B > Hh + 0.5 then
						offs[#offs + 1] = d.Name .. " " .. MenuH.show(r)
					end
				end
				T.check(#hits == 0, "menu dock: no button or text in a thumb zone or under the top bar at " .. tag, table.concat(hits, ", "))
				T.check(#offs == 0, "menu dock: everything on screen at " .. tag, table.concat(offs, ", "))
				local credits = MenuH.find(menu, "CreditsButton")
				if credits then
					local swing = MenuH.find(menu, "Swing")
					local droop = math.ceil(0.5 * board.AbsoluteSize.X * math.sin(math.rad(2)))
					local swung = { X = b.X - droop, Y = b.Y, R = b.R + droop, B = b.B + droop }
					T.check(swing ~= nil and not MenuH.overlap(MenuH.rect(credits), swung), "menu dock: the CREDITS tag is clear of the (swinging) board at " .. tag,
						MenuH.show(MenuH.rect(credits)) .. " vs " .. MenuH.show(swung))
				end
				-- (U4 review) the board's two ropes run from above the screen to the board: clear of Roblox's top-left buttons
				-- and of the CREDITS tag (its plank and its "vN"), so no rope crosses anything at the top of the screen
				local tagParts = {}
				for _, name in ipairs({ "CreditsButton", "Version" }) do
					local part = MenuH.find(menu, name)
					if part then
						tagParts[#tagParts + 1] = part
					end
				end
				local buttons = nil
				for _, z in ipairs(zones) do
					if z.Name == "top-left buttons" then
						buttons = z
					end
				end
				local ropes, crossed = 0, {}
				for _, d in ipairs(menu:GetDescendants()) do
					if d:GetAttribute("SignKit") == "Rope" and d.Parent and d.Parent.Name == "Swing" then
						ropes = ropes + 1
						local r = MenuH.rect(d)
						if MenuH.overlap(r, buttons) then
							crossed[#crossed + 1] = "rope " .. MenuH.show(r) .. " under the top-left buttons"
						end
						for _, part in ipairs(tagParts) do
							if MenuH.overlap(r, MenuH.rect(part)) then
								crossed[#crossed + 1] = "rope " .. MenuH.show(r) .. " behind " .. part.Name .. " " .. MenuH.show(MenuH.rect(part))
							end
						end
					end
				end
				T.eq(ropes, 2, "menu dock: (setup) the board's two ropes at " .. tag)
				T.check(#crossed == 0, "menu dock: the ropes clear the top-left buttons and the CREDITS tag at " .. tag, table.concat(crossed, ", "))
				MenuH.close()
			end
		end)
		MenuH.close()
		T.check(ok, "menu dock: the scenario ran", tostring(err))
		LKC.flushErrors("menu_portrait_docks_bottom")
	end)

	-- the entrance: the board drops in on its ropes (0.45 s, Back Out), settles with a 2 degree swing over 1.2 s, the buttons
	-- pop 60 ms apart; PLAY pulls the board up (0.3 s, Quad In) while the camera tweens to the spawn view (0.8 s, Sine
	-- InOut) and only then turns Custom
	S.menu_entrance_and_play_tweens = guarded("menu_entrance_and_play_tweens", function()
		local ok, err = pcall(function()
			local function tweensOf(inst, prop)
				local out = {}
				for tw in pairs(Mock.ActiveTweens) do
					if tw.Instance == inst and Mock.TweenGoals(tw)[prop] ~= nil then
						out[#out + 1] = tw
					end
				end
				return out
			end
			local menu, MMC = MenuH.open({ Wait = 0.05 })
			local swing = MenuH.find(menu, "Swing")
			if not T.check(swing ~= nil, "menu motion: (setup) the Swing exists") then
				return
			end
			local drop = tweensOf(swing, "Position")[1]
			local info = drop and drop.TweenInfo
			T.check(info ~= nil and math.abs(info.Time - 0.45) < 1e-6 and info.EasingStyle == Enum.EasingStyle.Back and info.EasingDirection == Enum.EasingDirection.Out,
				"menu motion: the board drops in (Position, 0.45 s, Back Out)", info and fmt("%.2f %s %s", info.Time, tostring(info.EasingStyle), tostring(info.EasingDirection)) or "no tween")
			local rest = drop and Mock.TweenGoals(drop).Position
			T.check(rest ~= nil and swing.Position.Y.Offset < rest.Y.Offset - 100, "menu motion: ...from above its rest place",
				rest and fmt("%d -> %d", swing.Position.Y.Offset, rest.Y.Offset) or "")
			local pops = {}
			for _, name in ipairs({ "PlayButton", "SettingsButton", "UpdatesButton" }) do
				local b = MenuH.find(menu, name)
				local pop = b and b:FindFirstChild("Pop")
				local tw = pop and tweensOf(pop, "Scale")[1]
				pops[#pops + 1] = tw and tw.TweenInfo.DelayTime or -1
			end
			T.check(pops[1] >= 0 and math.abs(pops[2] - pops[1] - 0.06) < 1e-6 and math.abs(pops[3] - pops[2] - 0.06) < 1e-6,
				"menu motion: PLAY, SETTINGS and UPDATES pop 60 ms apart", fmt("%.2f / %.2f / %.2f", pops[1], pops[2], pops[3]))
			LKC.advance(0.5)
			local settle = tweensOf(swing, "Rotation")[1]
			local sInfo = settle and settle.TweenInfo
			T.check(sInfo ~= nil and math.abs(sInfo.Time - 1.2) < 1e-6 and math.abs(swing.Rotation) <= 2.01 and math.abs(swing.Rotation) >= 1.99 and Mock.TweenGoals(settle).Rotation == 0,
				"menu motion: then it settles from a 2 degree swing to rest over 1.2 s", sInfo and fmt("%.2f deg, %.2f s", swing.Rotation, sInfo.Time) or "no tween")
			LKC.advance(1.4)
			T.check(swing.Rotation == 0 and rest ~= nil and swing.Position.Y.Offset == rest.Y.Offset and swing.Position.X.Offset == rest.X.Offset,
				"menu motion: at rest after the entrance")
			-- PLAY
			local camera = workspace.CurrentCamera
			MMC.Play()
			LKC.advance(0.05)
			local pull = tweensOf(swing, "Position")[1]
			local pInfo = pull and pull.TweenInfo
			local goal = pull and Mock.TweenGoals(pull).Position
			T.check(pInfo ~= nil and math.abs(pInfo.Time - 0.3) < 1e-6 and pInfo.EasingStyle == Enum.EasingStyle.Quad and pInfo.EasingDirection == Enum.EasingDirection.In,
				"menu motion: PLAY pulls the board up (Position, 0.3 s, Quad In)", pInfo and fmt("%.2f", pInfo.Time) or "no tween")
			T.check(goal ~= nil and rest ~= nil and goal.Y.Offset < rest.Y.Offset - 100, "menu motion: ...up off the screen")
			local fly = tweensOf(camera, "CFrame")[1]
			local fInfo = fly and fly.TweenInfo
			T.check(fInfo ~= nil and math.abs(fInfo.Time - 0.8) < 1e-6 and fInfo.EasingStyle == Enum.EasingStyle.Sine and fInfo.EasingDirection == Enum.EasingDirection.InOut,
				"menu motion: the camera tweens to the spawn view (CFrame, 0.8 s, Sine InOut)", fInfo and fmt("%.2f", fInfo.Time) or "no tween")
			LKC.advance(0.5)
			T.eq(camera.CameraType, Enum.CameraType.Scriptable, "menu motion: the camera stays Scriptable while it flies (0.55 s in)")
			LKC.advance(0.6)
			T.eq(camera.CameraType, Enum.CameraType.Custom, "menu motion: Custom once it has landed")
			T.eq(MMC.IsOpen(), false, "menu motion: the menu is closed after PLAY")
		end)
		MenuH.close()
		T.check(ok, "menu motion: the scenario ran", tostring(err))
		LKC.flushErrors("menu_entrance_and_play_tweens")
	end)

	-- (U4 review) a real join: the menu opens at client boot under the loading screen (NimbusLoading, no Done yet). The
	-- board waits lifted with its buttons at pop scale 0 and no tween runs; the entrance starts when Done arrives
	S.menu_entrance_waits_for_loading = guarded("menu_entrance_waits_for_loading", function()
		local lg = nil
		local ok, err = pcall(function()
			local function tweensOf(inst, prop)
				local out = {}
				for tw in pairs(Mock.ActiveTweens) do
					if tw.Instance == inst and Mock.TweenGoals(tw)[prop] ~= nil then
						out[#out + 1] = tw
					end
				end
				return out
			end
			lg = LoadingH.run()
			if not T.check(lg ~= nil and lg:GetAttribute("Done") ~= true, "menu wait: (setup) the loading screen is up, no Done") then
				return
			end
			local menu, MMC = MenuH.open({ Wait = 0.05 })
			local swing = MenuH.find(menu, "Swing")
			local rest = MMC._M.Ui and MMC._M.Ui.Rest
			if not T.check(swing ~= nil and rest ~= nil, "menu wait: (setup) the Swing exists") then
				return
			end
			local planks = {}
			for _, name in ipairs({ "PlayButton", "SettingsButton", "UpdatesButton" }) do
				planks[#planks + 1] = MenuH.find(menu, name)
			end
			-- longer than the whole entrance (0.45 s drop + 1.2 s settle) behind the loading screen
			LKC.advance(2)
			T.eq(#tweensOf(swing, "Position") + #tweensOf(swing, "Rotation"), 0, "menu wait: no drop or settle tween while the loading screen is up")
			T.check(swing.Position.Y.Offset < rest.Y.Offset - 100 and swing.Rotation == 0, "menu wait: the board waits lifted above its rest place",
				fmt("%d vs rest %d", swing.Position.Y.Offset, rest.Y.Offset))
			for _, b in ipairs(planks) do
				local pop = b:FindFirstChild("Pop")
				T.check(pop ~= nil and pop.Scale == 0 and #tweensOf(pop, "Scale") == 0, "menu wait: " .. b.Name .. " waits at pop scale 0, no tween",
					pop and tostring(pop.Scale) or "no Pop")
			end
			-- the loading screen finishes: the entrance starts with its fade
			lg:SetAttribute("Done", true)
			LKC.advance(0.05)
			local drop = tweensOf(swing, "Position")[1]
			local goal = drop and Mock.TweenGoals(drop).Position
			T.check(goal ~= nil and goal.Y.Offset == rest.Y.Offset and goal.X.Offset == rest.X.Offset, "menu wait: at Done the board drops in to its rest place")
			for _, b in ipairs(planks) do
				local pop = b:FindFirstChild("Pop")
				T.check(pop ~= nil and #tweensOf(pop, "Scale") == 1, "menu wait: at Done " .. b.Name .. " pops in")
			end
			LKC.advance(2)
			T.check(swing.Rotation == 0 and swing.Position.Y.Offset == rest.Y.Offset, "menu wait: at rest after the entrance")
			for _, b in ipairs(planks) do
				local pop = b:FindFirstChild("Pop")
				T.check(pop ~= nil and pop.Scale == 1, "menu wait: " .. b.Name .. " at full size after the entrance")
			end
			T.check(lg.Parent == nil, "menu wait: the loading screen has faded away")
		end)
		if lg and lg.Parent then
			lg:SetAttribute("Done", true)
			LKC.advance(0.6)
		end
		MenuH.close()
		LoadingH.cleanup()
		T.check(ok, "menu wait: the scenario ran", tostring(err))
		LKC.flushErrors("menu_entrance_waits_for_loading")
	end)

	-- Config.Preview.TitleShots: off (the default) keeps today's orbit and field of view; on, the camera holds Key A
	-- (landscape) or Key P (portrait) of Config.MainMenu.Shots at FOV 50, drifting sideways, and PLAY gives the FOV back
	S.menu_titleshots_off_keeps_orbit = guarded("menu_titleshots_off_keeps_orbit", function()
		local Config = LoadingH.shared("Config")
		local was = Config.Preview and Config.Preview.TitleShots
		local ok, err = pcall(function()
			T.eq(Config.Preview.TitleShots, false, "menu shots: Config.Preview.TitleShots ships false")
			local shots = Config.MainMenu.Shots
			if not T.check(type(shots) == "table" and type(shots.A) == "table" and type(shots.P) == "table" and shots.Fov == 50,
				"menu shots: Config.MainMenu.Shots holds Key A and Key P at FOV 50") then
				return
			end
			local camera = workspace.CurrentCamera
			local fov0 = camera.FieldOfView
			local lobby = Config.Lobby
			local a0 = math.rad(lobby.GateFacing)
			local dir = Vector3.new(math.cos(a0), 0, math.sin(a0))
			local centre = lobby.Origin + dir * lobby.GateArcRadius
			-- off: the orbit
			local _, MMC = MenuH.open()
			local p = camera.CFrame.Position
			local flat = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z).Magnitude
			T.near(flat, Config.MainMenu.OrbitRadius, 0.5, "menu shots: off, the camera orbits at OrbitRadius")
			T.near(p.Y - centre.Y, Config.MainMenu.OrbitHeight, 0.5, "menu shots: off, at OrbitHeight")
			T.eq(camera.FieldOfView, fov0, "menu shots: off, the field of view is untouched")
			MenuH.close()
			-- on: Key A on a wide screen, Key P on a portrait one
			Config.Preview.TitleShots = true
			local arch = lobby.Origin + dir * shots.Arch
			local right = Vector3.new(-dir.Z, 0, dir.X)
			for _, c in ipairs({ { "A", { 1920, 1080 }, "Keyboard" }, { "P", { 390, 844 }, "Touch" } }) do
				local key = shots[c[1]]
				local function at(t)
					local s = key.Drift * (0.5 - 0.5 * math.cos(math.pi * t / shots.DriftSeconds)) - key.Drift / 2
					return arch - dir * key.Back + Vector3.new(0, key.Up, 0) + right * s
				end
				local _, M2 = MenuH.open({ Size = c[2], Input = c[3], Wait = 0.05 })
				local t0 = M2._M.Orbit.T
				T.check(t0 < 0.2, "menu shots: (setup) the drift starts with the title screen", fmt("%.2f s", t0))
				local q = camera.CFrame.Position
				T.check((q - at(t0)).Magnitude < 0.5, "menu shots: on, Key " .. c[1] .. " stands " .. key.Back .. " studs before the Welcome Arch, " .. key.Up .. " up",
					fmt("%.1f,%.1f,%.1f vs %.1f,%.1f,%.1f", q.X, q.Y, q.Z, at(t0).X, at(t0).Y, at(t0).Z))
				local look = camera.CFrame.LookVector
				T.near(math.deg(math.asin(look.Y)), key.Pitch, 0.5, "menu shots: Key " .. c[1] .. " looks up " .. key.Pitch .. " degrees")
				T.check(Vector3.new(look.X, 0, look.Z).Unit:Dot(dir) > 0.999, "menu shots: Key " .. c[1] .. " looks up the avenue")
				T.eq(camera.FieldOfView, shots.Fov, "menu shots: Key " .. c[1] .. " at FOV " .. shots.Fov)
				LKC.advance(15)
				local mid = camera.CFrame.Position
				T.check((mid - at(M2._M.Orbit.T)).Magnitude < 0.5 and (mid - q).Magnitude > key.Drift * 0.3, "menu shots: Key " .. c[1] .. " drifts sideways",
					fmt("%.2f studs in 15 s", (mid - q).Magnitude))
				MenuH.close()
				T.near(camera.FieldOfView, fov0, 1e-6, "menu shots: PLAY gives the field of view back after Key " .. c[1])
			end
		end)
		Config.Preview.TitleShots = was == true
		MenuH.close()
		T.check(ok, "menu shots: the scenario ran", tostring(err))
		LKC.flushErrors("menu_titleshots_off_keeps_orbit")
	end)

	------------------------------------------------------------------------------------------------
	-- U5: Settings and Updates on the Signboard (finding 5). Each scenario opens the window by itself at its size and
	-- input (WinH.open) and closes it again (WinH.close).
	local WinH = {}

	-- opts: Size = { w, h }, Input = "Keyboard" | "Touch"; which = "Settings" | "Updates"
	function WinH.open(which, opts)
		opts = opts or {}
		local UIS = game:GetService("UserInputService")
		WinH.old = WinH.old or { Mock.Viewport, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		local input = opts.Input or "Keyboard"
		UIS.TouchEnabled = input == "Touch"
		UIS.KeyboardEnabled = input == "Keyboard"
		UIS.MouseEnabled = input == "Keyboard"
		local size = opts.Size or { 1920, 1080 }
		Mock.SetViewport(size[1], size[2])
		LKC.advance(0.1)
		local MMC = MenuH.mmc()
		MMC.CloseWindows()
		if which == "Updates" then
			MMC.OpenUpdates()
		else
			MMC.OpenSettings()
		end
		LKC.advance(0.4)
		return MMC.Window(), MMC
	end
	function WinH.close()
		MenuH.mmc().CloseWindows()
		local old = WinH.old
		if old then
			local UIS = game:GetService("UserInputService")
			Mock.SetViewport(old[1].X, old[1].Y)
			UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[2], old[3], old[4]
		end
		WinH.old = nil
		LKC.advance(0.2)
	end
	function WinH.texts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
				out[#out + 1] = d
			end
		end
		return out
	end
	function WinH.icon(root)
		for _, d in ipairs(root:GetDescendants()) do
			local name = d:GetAttribute("PixelIcon")
			if name then
				return name, d
			end
		end
		return nil
	end
	-- the code points of a UTF-8 string
	function WinH.codepoints(s)
		local out, i = {}, 1
		while i <= #s do
			local c = s:byte(i)
			local n, cp = 1, c
			if c >= 0xF0 then
				n, cp = 4, c % 0x08
			elseif c >= 0xE0 then
				n, cp = 3, c % 0x10
			elseif c >= 0xC0 then
				n, cp = 2, c % 0x20
			end
			for k = 1, n - 1 do
				cp = cp * 64 + ((s:byte(i + k) or 0x80) % 0x40)
			end
			out[#out + 1] = cp
			i = i + n
		end
		return out
	end
	-- no neon kit in a window: no corner, no gradient, no classic text stroke, no text outline, no neon colour, no CloudUI panel
	function WinH.neon(holder, Theme)
		local bad = {}
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("UIGradient") or d:IsA("UICorner") then
				bad[#bad + 1] = d.ClassName .. " in " .. d.Parent.Name
			elseif (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and (d.TextStrokeTransparency < 0.95 or #textStrokes(d) > 0) then
				bad[#bad + 1] = "a stroke on " .. d.Name
			elseif d:IsA("GuiObject") and d.BackgroundTransparency < 0.99 then
				for name, c in pairs(Theme.Neon) do
					if sameColor(d.BackgroundColor3, c) then
						bad[#bad + 1] = "neon " .. name .. " on " .. d.Name
					end
				end
			end
			if d:GetAttribute("CloudUI") or d.Name:match("Panel$") then
				bad[#bad + 1] = "a CloudUI panel " .. d.Name
			end
		end
		return bad
	end
	-- the Signboard frame of a window: the flat awning, the navy header with `title` (Title role, gold, the pixel `icon`
	-- on its gold square), the wood frame, the stone body and the red Close plank with the pixel x
	function WinH.frame(holder, title, icon, Theme, tag)
		local Sign = Theme.Sign
		local kinds = MenuH.kinds(holder)
		local roof = (kinds.Roof or {})[1]
		T.check(roof ~= nil and roof:FindFirstChild("Face") and roof:FindFirstChild("SlopeL") == nil and roof.Size.X.Scale == 0,
			"u5 window: the flat awning (a fixed-size SignKit roof) at " .. tag)
		local head = (kinds.Header or {})[1]
		local plate = head and head:FindFirstChild("Plate")
		local t = plate and plate:FindFirstChild("Title")
		T.check(plate ~= nil and sameColor(plate.BackgroundColor3, Sign.Navy), "u5 window: the navy header plank at " .. tag)
		if T.check(t ~= nil and t.Text == title, "u5 window: the header reads " .. title .. " at " .. tag, t and t.Text or "missing") then
			T.check(t:GetAttribute("FontRole") == "Title" and t.Font == Theme.Fonts.Title and sameColor(t.TextColor3, Sign.Gold),
				"u5 window: " .. title .. " in LuckiestGuy gold (Title role)", tostring(t.Font) .. " " .. hex(t.TextColor3))
		end
		local slot = plate and plate:FindFirstChild("IconSlot")
		T.check(slot ~= nil and WinH.icon(slot) == icon, "u5 window: the pixel " .. icon .. " on the header's gold square at " .. tag)
		local wood, body = (kinds.Frame or {})[1], (kinds.Body or {})[1]
		T.check(wood and sameColor(wood.BackgroundColor3, Sign.Wood) and body and sameColor(body.BackgroundColor3, Sign.Stone), "u5 window: the wood frame and the stone body at " .. tag)
		local close = MenuH.find(holder, "Close")
		local cface = close and MenuH.find(close, "Face")
		T.check(close and close:GetAttribute("SignKit") == "Plank" and cface and sameColor(cface.BackgroundColor3, Sign.Red) and WinH.icon(close) == "x",
			"u5 window: Close is a red plank with the pixel x at " .. tag)
		return close, body
	end

	S.settings_on_signkit = guarded("settings_on_signkit", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		local CS = require(Mock.GetPath(ROOTS["client"] .. "/ClientSettings"))
		local gfx0 = CS.Get("Gfx")
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 390, 844, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local holder = WinH.open("Settings", { Size = s, Input = s[3] })
				if not T.check(holder ~= nil and holder:GetAttribute("DockMode") ~= nil, "settings kit: the window opens docked at " .. tag) then
					return
				end
				WinH.frame(holder, "SETTINGS", "gear", Theme, tag)
				local bad = WinH.neon(holder, Theme)
				T.check(#bad == 0, "settings kit: no corner, gradient, stroke, neon colour or CloudUI panel at " .. tag, table.concat(bad, "; ", 1, math.min(#bad, 6)))
				local rows = { { "Music", "music" }, { "Sfx", "speaker" }, { "Gfx", "monitor" }, { "Shake", "shake" } }
				if s[3] == "Keyboard" then
					rows[#rows + 1] = { "MouseLock", "mouse" }
				end
				for _, r in ipairs(rows) do
					local row = MenuH.find(holder, "Row_" .. r[1])
					local title = row and row:FindFirstChild("Title", true)
					T.check(row ~= nil and WinH.icon(row) == r[2], "settings kit: Row_" .. r[1] .. " carries the pixel " .. r[2] .. " at " .. tag)
					T.check(title and sameColor(title.TextColor3, Theme.TextOn("Stone")) and title:GetAttribute("FontRole") == "Heading",
						"settings kit: Row_" .. r[1] .. "'s title is brown FredokaOne on the stone at " .. tag, title and hex(title.TextColor3) or "missing")
				end
				-- chips are planks; the selected one is gold with its lip (the pitch's .bt.sel), the others stone
				local function chips()
					local out = {}
					for _, name in ipairs({ "Chip_AUTO", "Chip_LOW", "Chip_HIGH" }) do
						out[#out + 1] = MenuH.find(holder, name)
					end
					return out
				end
				local function look()
					local sel, str = 0, ""
					for _, c in ipairs(chips()) do
						local face = MenuH.find(c, "Face")
						local lip = MenuH.find(c, "Lip")
						local gold = face and sameColor(face.BackgroundColor3, Sign.Gold) and lip and sameColor(lip.BackgroundColor3, Sign.GoldLip)
						local stone = face and sameColor(face.BackgroundColor3, Sign.Tile)
						if c:GetAttribute("Selected") then
							sel = sel + 1
							str = str .. (gold and "G" or "?")
						else
							str = str .. (stone and "s" or "?")
						end
					end
					return sel, str
				end
				local list = chips()
				T.check(#list == 3 and list[1]:GetAttribute("SignKit") == "Plank" and list[2]:GetAttribute("SignKit") == "Plank", "settings kit: the Graphics chips are SignKit planks at " .. tag)
				Mock.Click(MenuH.find(holder, "Chip_LOW"))
				LKC.advance(0.2)
				local sel, str = look()
				T.check(sel == 1 and str == "sGs", "settings kit: LOW picked = the one gold plank, the others stone at " .. tag, str)
				Mock.Click(MenuH.find(holder, "Chip_AUTO"))
				LKC.advance(0.2)
				sel, str = look()
				T.check(sel == 1 and str == "Gss", "settings kit: AUTO picked moves the gold at " .. tag, str)
				local close = MenuH.find(holder, "Close")
				Mock.Click(close)
				LKC.advance(0.2)
				T.check(MenuH.mmc().Window() == nil, "settings kit: the Close plank closes the window at " .. tag)
				WinH.close()
			end
		end)
		CS.Set("Gfx", gfx0)
		WinH.close()
		T.check(ok, "settings kit: the scenario ran", tostring(err))
		-- over the title screen on a portrait phone the sheet hides the docked board (its awning's ends peeked out at the
		-- sides); closing the window brings it back
		local ok2, err2 = pcall(function()
			local menu, MMC = MenuH.open({ Size = { 390, 844 }, Input = "Touch" })
			local swing = MenuH.find(menu, "Swing")
			MMC.OpenSettings()
			LKC.advance(0.3)
			T.check(swing ~= nil and swing.Visible == false, "settings kit: a portrait sheet hides the title board behind it")
			MMC.CloseWindows()
			LKC.advance(0.1)
			T.check(swing ~= nil and swing.Visible == true, "settings kit: closing the window shows the board again")
		end)
		MenuH.close()
		T.check(ok2, "settings kit: the board scenario ran", tostring(err2))
		LKC.flushErrors("settings_on_signkit")
	end)

	-- no emoji: no code point above U+2000 in any text of the two windows (desktop: every row)
	S.settings_no_emoji = guarded("settings_no_emoji", function()
		local ok, err = pcall(function()
			for _, which in ipairs({ "Settings", "Updates" }) do
				local holder = WinH.open(which)
				local bad, n = {}, 0
				for _, t in ipairs(WinH.texts(holder)) do
					n = n + 1
					for _, cp in ipairs(WinH.codepoints(t.Text)) do
						if cp > 0x2000 then
							bad[#bad + 1] = fmt("%s U+%04X", t.Name, cp)
							break
						end
					end
				end
				T.check(n > 3, "settings emoji: (setup) the " .. which .. " window has texts", tostring(n))
				T.check(#bad == 0, "settings emoji: no code point above U+2000 in the " .. which .. " window", table.concat(bad, ", ", 1, math.min(#bad, 8)))
				WinH.close()
			end
		end)
		WinH.close()
		T.check(ok, "settings emoji: the scenario ran", tostring(err))
		LKC.flushErrors("settings_no_emoji")
	end)

	-- the 0-10 scale is a SignKit BlockRow of 10: the first <value> blocks gold; - / + and a tap on a block move it
	S.settings_scale_is_blockrow = guarded("settings_scale_is_blockrow", function()
		local CS = require(Mock.GetPath(ROOTS["client"] .. "/ClientSettings"))
		local music0 = CS.Get("Music")
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 390, 844, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local holder = WinH.open("Settings", { Size = s, Input = s[3] })
				CS.Set("Music", 4)
				LKC.advance(0.1)
				local row = MenuH.find(holder, "Row_Music")
				local blocks = nil
				for _, d in ipairs(row and row:GetDescendants() or {}) do
					if d:GetAttribute("SignKit") == "BlockRow" then
						blocks = d
					end
				end
				if not T.check(blocks ~= nil and blocks:GetAttribute("Count") == 10, "settings scale: Row_Music's scale is a SignKit BlockRow of 10 at " .. tag) then
					return
				end
				T.eq(blocks:GetAttribute("Filled"), 4, "settings scale: Music 4 = 4 gold blocks at " .. tag)
				local plus, minus = MenuH.find(row, "Plus"), MenuH.find(row, "Minus")
				T.check(plus and minus and plus:GetAttribute("SignKit") == "Plank" and minus:GetAttribute("SignKit") == "Plank", "settings scale: - and + are planks at " .. tag)
				T.check(WinH.icon(plus) == "plus" and WinH.icon(minus) == "minus", "settings scale: - and + carry the pixel minus / plus at " .. tag)
				Mock.Click(plus)
				LKC.advance(0.1)
				T.eq(blocks:GetAttribute("Filled"), 5, "settings scale: + fills the next block at " .. tag)
				local step = MenuH.find(row, "Step8")
				if T.check(step ~= nil and step:IsA("TextButton"), "settings scale: each block is a tap target (Step1..Step10) at " .. tag) then
					Mock.Click(step)
					LKC.advance(0.1)
					T.check(CS.Get("Music") == 8 and blocks:GetAttribute("Filled") == 8, "settings scale: a tap on block 8 sets 8 at " .. tag, tostring(CS.Get("Music")))
				end
				for _ = 1, 12 do
					Mock.Click(minus)
				end
				LKC.advance(0.1)
				local value = MenuH.find(row, "Value")
				T.check(blocks:GetAttribute("Filled") == 0 and value and value.Text == "OFF", "settings scale: 0 = no gold block and the value reads OFF at " .. tag)
				-- the row fits the window: the strip (- blocks +) inside the stone body
				local body = holder:FindFirstChild("Body", true)
				local b, r = MenuH.rect(body), MenuH.rect(blocks)
				local p, m = MenuH.rect(plus), MenuH.rect(minus)
				T.check(m.X >= b.X and p.R <= b.R and r.X >= m.R and r.R <= p.X, "settings scale: - blocks + sit in order inside the body at " .. tag,
					MenuH.show(m) .. " " .. MenuH.show(r) .. " " .. MenuH.show(p) .. " in " .. MenuH.show(b))
				WinH.close()
			end
		end)
		CS.Set("Music", music0)
		WinH.close()
		T.check(ok, "settings scale: the scenario ran", tostring(err))
		LKC.flushErrors("settings_scale_is_blockrow")
	end)

	-- Updates: WHAT'S NEW; each version head a navy plank (gold-lip edge, navy lip) in FredokaOne gold, newest first; each
	-- line Nunito brown on the stone after a 6 px square bullet (no glyph)
	S.updates_on_signkit = guarded("updates_on_signkit", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		local notes = LoadingH.shared("UpdateNotes")
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080, "Keyboard" }, { 390, 844, "Touch" } }) do
				local tag = s[1] .. "x" .. s[2]
				local holder = WinH.open("Updates", { Size = s, Input = s[3] })
				if not T.check(holder ~= nil, "updates kit: the window opens at " .. tag) then
					return
				end
				WinH.frame(holder, "WHAT'S NEW", "scroll", Theme, tag)
				local bad = WinH.neon(holder, Theme)
				T.check(#bad == 0, "updates kit: no corner, gradient, stroke, neon colour or CloudUI panel at " .. tag, table.concat(bad, "; ", 1, math.min(#bad, 6)))
				local heads, lines, wrong = 0, 0, {}
				local lastOrder = -1
				for o, note in ipairs(notes.Notes) do
					local head = MenuH.find(holder, "Head" .. o)
					local block = head and head:FindFirstChild("Block")
					local face = block and block:FindFirstChild("Face")
					local lip = block and block:FindFirstChild("Lip")
					local label = face and face:FindFirstChild("Label")
					if block and face and lip and label and sameColor(face.BackgroundColor3, Sign.Navy) and sameColor(block.BackgroundColor3, Sign.GoldLip)
						and sameColor(lip.BackgroundColor3, Sign.NavyLip) and label.Font == Enum.Font.FredokaOne and sameColor(label.TextColor3, Sign.Gold)
						and label.Text:find("v" .. note.Version, 1, true) == 1 and head.LayoutOrder > lastOrder then
						heads = heads + 1
						lastOrder = head.LayoutOrder
					else
						wrong[#wrong + 1] = "Head" .. o
					end
					for i, text in ipairs(note.Lines or {}) do
						local line = MenuH.find(holder, "Line" .. o .. "_" .. i)
						local bullet = line and line:FindFirstChild("Bullet")
						local t = line and line:FindFirstChild("Text")
						if bullet and t and bullet.Size == UDim2.fromOffset(6, 6) and bullet.BackgroundTransparency == 0 and bullet:FindFirstChildOfClass("UICorner") == nil
							and t.Text == text and t:GetAttribute("FontRole") == "Body" and sameColor(t.TextColor3, Theme.TextOn("Stone")) then
							lines = lines + 1
						elseif #wrong < 6 then
							wrong[#wrong + 1] = "Line" .. o .. "_" .. i
						end
					end
				end
				local want = 0
				for _, note in ipairs(notes.Notes) do
					want = want + #(note.Lines or {})
				end
				T.check(heads == #notes.Notes, "updates kit: every version head is a navy plank in FredokaOne gold, newest first at " .. tag, table.concat(wrong, ", "))
				T.check(lines == want, "updates kit: every line is Nunito brown after a 6 px square bullet at " .. tag, fmt("%d of %d; %s", lines, want, table.concat(wrong, ", ")))
				WinH.close()
			end
		end)
		WinH.close()
		T.check(ok, "updates kit: the scenario ran", tostring(err))
		LKC.flushErrors("updates_on_signkit")
	end)

	-- the bug of 2026-11-13: the DEV panel's Restart / Skip tutorial buttons peeked out under the Credits window. Opening a
	-- window closes the DEV panel; a window replaces the one before it; opening the DEV panel closes a menu window, so the
	-- two are never open together
	S.settings_hidden_under_credits = guarded("settings_hidden_under_credits", function()
		local pg = game:GetService("Players").LocalPlayer.PlayerGui
		local Dev = require(Mock.GetPath(ROOTS["client"] .. "/Controllers/DevController"))
		local MMC = MenuH.mmc()
		local ok, err = pcall(function()
			pg:SetAttribute("NC_Dev", true)
			LKC.advance(1)
			Dev.Open()
			LKC.advance(0.5)
			if not T.check(Dev.IsOpen() == true, "under credits: (setup) the DEV panel is open") then
				return
			end
			MMC.OpenSettings()
			LKC.advance(0.3)
			T.check(Dev.IsOpen() == false, "under credits: opening Settings closes the DEV panel")
			MMC.OpenCredits()
			LKC.advance(0.3)
			local _, name = MMC.Window()
			local gui = pg:FindFirstChild("NimbusMainMenu")
			T.check(name == "Credits" and gui and gui:FindFirstChild("Window_Settings") == nil, "under credits: Credits replaces Settings (nothing of Settings left under it)", tostring(name))
			Dev.Open()
			LKC.advance(0.5)
			local holder = MMC.Window()
			T.check(not (Dev.IsOpen() and holder ~= nil), "under credits: the DEV panel and a menu window are never open together (its Restart / Skip tutorial rows would peek out)",
				fmt("dev %s, window %s", tostring(Dev.IsOpen()), tostring(holder and holder.Name)))
			T.check(Dev.IsOpen() == true and holder == nil, "under credits: opening the DEV panel closes the menu window (the owner asked for the panel)")
		end)
		pcall(Dev.Close)
		MMC.CloseWindows()
		pg:SetAttribute("NC_Dev", nil)
		LKC.advance(0.5)
		T.check(ok, "under credits: the scenario ran", tostring(err))
		LKC.flushErrors("settings_hidden_under_credits")
	end)

	-- (g) the loading tip keeps its text clear of the pixel bulb at every size: the text starts >= 12 screen px right of
	-- the bulb's gold square, the bulb sits inside its square
	S.loading_tip_clear_of_bulb = guarded("loading_tip_clear_of_bulb", function()
		local ok, err = pcall(function()
			for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 390, 844 }, { 844, 390 }, { 360, 640 } }) do
				local tag = s[1] .. "x" .. s[2]
				local gui = LoadingH.run({ Size = s })
				local card = gui and gui:FindFirstChild("TipCard", true)
				local slot = card and card:FindFirstChild("IconSlot", true)
				local tip = card and card:FindFirstChild("Tip", true)
				local _, bulb = WinH.icon(slot or card or gui)
				if T.check(card and slot and tip and bulb, "loading tip: the card, its bulb and its text at " .. tag) then
					local sr, br, tr = MenuH.rect(slot), MenuH.rect(bulb), MenuH.rect(tip)
					T.check(tr.X >= sr.R + 12 and tr.X >= br.R + 12, "loading tip: the text starts 12 px or more right of the bulb at " .. tag,
						fmt("text x %d, bulb right %d, square right %d", tr.X, br.R, sr.R))
					T.check(br.X >= sr.X - 0.5 and br.R <= sr.R + 0.5 and br.Y >= sr.Y - 0.5 and br.B <= sr.B + 0.5, "loading tip: the bulb sits inside its gold square at " .. tag,
						MenuH.show(br) .. " in " .. MenuH.show(sr))
				end
				LoadingH.cleanup()
			end
		end)
		LoadingH.cleanup()
		T.check(ok, "loading tip: the scenario ran", tostring(err))
		LKC.flushErrors("loading_tip_clear_of_bulb")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
