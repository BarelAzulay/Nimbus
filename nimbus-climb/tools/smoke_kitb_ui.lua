-- smoke_kitb_ui.lua: the kit-b UI lane (U1-U9 of .superpowers/slop-audit/round3/BUILD_PLAN.md; branch kitb-ui). Loaded by
-- tools/smoke.py in both worlds, ARGS.context picks the half. Each wave adds its scenarios here and their names on the
-- UI line of tools/smoke.py (that line only).
--   U1 (Theme: roles, stroke rule, tokens; fonts audit F1, F2, F5, F6, F11, F12, rejects audit 8; the owner: "all fonts in
--   the game and gui ... cool unique style and fonts, good looking gui matching what we pitched"):
--   theme_roles_kitb          (server world, pure) the pitch's role map: Sign / Accent LuckiestGuy; Title (T0, the owner's
--                             title pick B) / Heading / Button / Tag / Nameplate / Display FredokaOne; Body / Label / Toast Nunito ExtraBold through
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
--   kitb_text_contrast        (client; U6 review) every shown text with no outline reaches 3:1 (18 px and up) or 4.5:1
--                             against the fill painted under its glyphs (SmokeCommon.Contrast; tools/fixtures/
--                             contrast_backlog.txt is counted, not failed). theme_texton also pins Theme.TextOn of a
--                             ColorSequence (its worst stop) and Theme.ReadableFace (a face moved the least until it reads)
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
--   signkit_shared_only       (server world, pure) SignKit requires only Theme from Shared, PixelIcon nothing at load
--                             (Theme only inside Lead's measure, U7b review);
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
--   T0 (the owner's title pick B: FredokaOne titles, Theme.StyleTitle): theme_style_title (server world, pure) and
--   kitb_titles_stamped (client; T0 review) the run-time walk: every Title-role Title / TitleText / Headline label in the
--   built windows is stamped Ribbon (T1) or a Theme.TitleExempt kind, and each expected window title is found Ribbon
--   U7a (icons: tiles and currency; finding 7, rejects audit 5):
--   token_glyph_sources       (server world, pure) no script outside U7b's glyph tables and world signs writes the cloud
--                             glyph (U+2601) the Cloud Token used
--   kitb_no_emoji_ui          (client) the emoji walk: after the client run and with each window U7a reworked open, no shown
--                             text carries an emoji or pictographic symbol (SmokeCommon.Emoji; tools/stroke_walk.py --emoji
--                             runs the same rule over every render scenario); tools/fixtures/emoji_backlog.txt is counted
--   token_icon_everywhere     (client) Theme.Currency names the icons (no emoji glyph), Config.Icons fills every icon id
--                             from PixelIcon, NeonKit.Icon("Tokens") draws the coin and follows TextColor3 / fade / ZIndex,
--                             PixelIcon.Lead puts it before an amount, and every token surface holds it at run time
--   U7b review:
--   pixelicon_lead_server_measure (server world, pure) Lead with TextBounds at 0 (a server) still puts the icon outside
--                             the text, every alignment, before and after, fixed and auto-sized
--   kitb_world_sign_icons     (server world) each world sign's icon by sign (machine and rarity-board coins, arena
--                             trophies, gate stars = the difficulty's Stars, a locked pad's lock placed as a server
--                             builds it, the pads' station icons, the closed bed's star, the bounce arrow)
--   arena_side_invite_fits    (client) the incoming-challenge side card: trophies, power and the clock inside the card
--   U9-6 (the battle HUD and the loss screen; U96.FAMILY, the fights from smoke_p5_battleclient's driver _G.P5BattleH):
--   battle_family_fits        (client) at the four grid sizes no text under the floor (15 / 14 px) and none TextScaled, the
--                             enemy list clear of the currency strips; on the phones every text and button whole on the
--                             screen, uncut, one-line texts fitting at real widths, nothing under the stick / jump button.
--                             kitb_no_neon_glow and kitb_no_emoji_ui walk the family's views too
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

-- (sign/logo build) the owner's two designed looks the flat-kit walks let through (2026-11-13): a window title's T1
-- ribbon (its pieces, attribute Ribbon: the gold banded letters with ONE outline, the band, the tails; the TitleHide
-- gradient that hides the label's own text under it) and the logo's letters (shared/Logo: banded faces with ONE outline)
local function designedLook(d)
	if d.Name == "TitleHide" and d.Parent and d.Parent:GetAttribute("TitleLook") == "Ribbon" then
		return true
	end
	local o = d
	while o do
		if o:GetAttribute("Ribbon") ~= nil or o:GetAttribute("Logo") ~= nil then
			return true
		end
		o = o.Parent
	end
	return false
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
			Title = "FredokaOne", Sign = "LuckiestGuy", Accent = "LuckiestGuy",
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
		-- U6 (a deliberate spec change): the classic stroke is gone from kit B, an explicit Stroke is ignored
		local asked = Theme.Label("Asked for", "Body", { Stroke = 0.3 })
		T.check(asked.TextStrokeTransparency == 1, "kitb stroke: an explicit Stroke gives no classic stroke any more (U6)", tostring(asked.TextStrokeTransparency))
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
		T.check(label.Font == Theme.Fonts.Title and label.FontFace ~= Theme.Faces.Body and tostring(label.FontFace.Family):find("FredokaOne") ~= nil and label:GetAttribute("FontRole") == "Title",
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
		-- (U6 review) a gradient fill is judged at its worst stop; a mid tone is moved the least until its ink reads
		local pale = ColorSequence.new(Color3.fromRGB(250, 248, 240), Color3.fromRGB(150, 210, 160))
		local mixed = ColorSequence.new(Color3.fromRGB(250, 248, 240), Color3.fromRGB(20, 24, 60))
		T.check(hex(Theme.TextOn(pale)) == brown, "kitb texton: a pale gradient takes brown (its worst stop still reads)", hex(Theme.TextOn(pale)))
		local mInk = Theme.TextOn(mixed)
		T.check(math.min(Theme.Contrast(mInk, Color3.fromRGB(250, 248, 240)), Theme.Contrast(mInk, Color3.fromRGB(20, 24, 60)))
			>= math.min(Theme.Contrast(hex(mInk) == white and Sg.Text or Theme.Colors.White, Color3.fromRGB(250, 248, 240)), Theme.Contrast(hex(mInk) == white and Sg.Text or Theme.Colors.White, Color3.fromRGB(20, 24, 60))),
			"kitb texton: a light-to-dark gradient takes the ink with the better worst stop", hex(mInk))
		for _, c in ipairs({ Color3.fromRGB(176, 104, 255), Color3.fromRGB(110, 128, 255), Color3.fromRGB(236, 60, 72), Color3.fromRGB(57, 147, 225), Color3.fromRGB(250, 248, 240), Color3.fromRGB(20, 24, 60) }) do
			local face, ink = Theme.ReadableFace(c, 4.5)
			T.check(Theme.Contrast(face, ink) >= 4.5, "kitb texton: Theme.ReadableFace reaches 4.5:1 on " .. hex(c), fmt("%s on %s %.2f:1", hex(ink), hex(face), Theme.Contrast(face, ink)))
			local wFace, wInk = Theme.ReadableFace(c, 4.5, true)
			T.check(hex(wInk) == white and Theme.Contrast(wFace, wInk) >= 4.5, "kitb texton: ...white only on " .. hex(c), fmt("%s on %s", hex(wInk), hex(wFace)))
		end
		local keep = Color3.fromRGB(20, 24, 60)
		T.check(hex((Theme.ReadableFace(keep, 4.5))) == hex(keep), "kitb texton: Theme.ReadableFace keeps a face that already reads")
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

		-- the header: navy plank, gold FredokaOne title (T0: the owner's title pick B) through Theme.StyleTitle, no stroke
		local win = holder(600, 400)
		local head, plate = SK.Header(win, { Title = "PETS" })
		T.check(head and head.Name == "Head" and head:GetAttribute("SignKit") == "Header" and plate and plate.Name == "Plate", "signkit header: Head + Plate")
		if head and plate then
			T.check(sameColor(plate.BackgroundColor3, Sg.Navy) and sameColor(head.BackgroundColor3, Sg.Wood), "signkit header: a navy plate in a wood rim",
				hex(plate.BackgroundColor3) .. " in " .. hex(head.BackgroundColor3))
			T.check(head.Size.X.Scale == 1 and head.Size.Y.Offset == Z.HeadH, "signkit header: full width, HeadH tall", tostring(head.Size))
			local title = plate:FindFirstChild("Title")
			T.check(title and title.Text == "PETS" and title.Font == Enum.Font.FredokaOne and sameColor(title.TextColor3, Sg.Gold),
				"signkit header: the title is FredokaOne gold", title and (tostring(title.Font) .. " " .. hex(title.TextColor3)) or "none")
			T.check(title and title:GetAttribute("TitleLook") == "Ribbon", "signkit header: the title goes through Theme.StyleTitle (TitleLook stamp)",
				title and tostring(title:GetAttribute("TitleLook")) or "none")
			T.check(title and title.TextStrokeTransparency == 1 and #textStrokes(title) == 0, "signkit header: the title has no stroke (gold on navy, 9:1)")
			T.check(plate:FindFirstChild("TitleDrop") == nil, "signkit header: no drop line unless asked")
		end
		local _, plate2 = SK.Header(win, { Title = "X", Drop = Color3.fromRGB(11, 19, 48), IconSlot = true })
		T.check(plate2 and plate2:FindFirstChild("TitleDrop") and plate2:FindFirstChild("IconSlot"), "signkit header: Drop adds the drop line, IconSlot the gold icon square")
		-- (T0) the Credits header's Sign role keeps its approved LuckiestGuy and stays out of the title treatment
		local _, plate3 = SK.Header(win, { Title = "CREDITS", TitleRole = "Sign" })
		local signTitle = plate3 and plate3:FindFirstChild("Title")
		T.check(signTitle and signTitle.Font == Enum.Font.LuckiestGuy and signTitle:GetAttribute("TitleLook") == nil,
			"signkit header: a Sign-role title stays LuckiestGuy with no title treatment",
			signTitle and (tostring(signTitle.Font) .. " " .. tostring(signTitle:GetAttribute("TitleLook"))) or "none")

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
		-- (U7b review) PixelIcon may require Theme too, but only inside a function (Lead measuring a server-built sign's
		-- text): at load it still requires nothing, so the loading screen can draw icons before Theme arrives
		for name, allowed in pairs({ SignKit = { Theme = true }, PixelIcon = { Theme = true } }) do
			local src = code(name)
			T.check(src ~= "", "shared only: " .. name .. " has source")
			local bad = {}
			for arg in src:gmatch("require%s*(%b())") do
				local sib = arg:match('^%(%s*script%.Parent:WaitForChild%("(%w+)"%)%s*%)$') or arg:match("^%(%s*script%.Parent%.(%w+)%s*%)$")
				if not (sib and allowed[sib]) then
					bad[#bad + 1] = arg
				end
			end
			T.check(#bad == 0, "shared only: " .. name .. " requires only Theme (a sibling in Shared)", table.concat(bad, ", "))
			if name == "PixelIcon" then
				local top = {}
				for line in (src .. "\n"):gmatch("([^\n]*)\n") do
					if line:match("^%S") and line:find("require%s*%(") then
						top[#top + 1] = line
					end
				end
				T.check(#top == 0, "shared only: PixelIcon requires nothing at load (Theme only inside Lead's measure)", table.concat(top, " | "))
			end
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

	-- (g) (U7a review) PixelIcon.Lead under a UIScale: Roblox's TextBounds is screen px (after every UIScale on and above
	-- the label) while Position offsets are the label's own px. At 0.8 (a phone), 1.25 (a big screen) and 1.7 (a token
	-- pop) every icon sits just outside its text, its own gap away: never over the text, never a wider gap
	S.pixelicon_lead_uiscale = guarded("pixelicon_lead_uiscale", function()
		local PI = shared("PixelIcon")
		local Mock = rawget(_G, "Mock")
		if not (PI and Mock) then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		local L, R, C = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
		local cases = { { L, false }, { L, true }, { R, false }, { R, true }, { C, false }, { C, true } }
		for _, sc in ipairs({ 0.8, 1, 1.25, 1.7 }) do
			local root = Instance.new("Frame")
			root.Size = UDim2.fromOffset(400, 400)
			local ui = Instance.new("UIScale")
			ui.Scale = sc
			ui.Parent = root
			root.Parent = gui
			-- the mock's TextBounds scales like Roblox's
			local probe = Instance.new("TextLabel")
			probe.Size = UDim2.fromOffset(200, 30)
			probe.TextSize = 20
			probe.Text = "1,250"
			probe.Parent = root
			local own = Mock.TextExtent(probe)
			T.check(math.abs(probe.TextBounds.X - own * sc) < 0.01, fmt("mock: TextBounds is screen px under a UIScale of %.2f", sc),
				fmt("%.1f, own %.1f", probe.TextBounds.X, own))
			for i, case in ipairs(cases) do
				local align, after = case[1], case[2]
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromOffset(300, 30)
				label.Position = UDim2.fromOffset(50, 40 + i * 50)
				label.TextSize = 20
				label.Text = "1,250"
				label.TextXAlignment = align
				label.Parent = root
				local box = PI.Lead(label, "token", { After = after })
				local px = PI.Snap(18)
				local gap = math.max(3, math.floor(px / 4)) * sc
				local pad = label:FindFirstChildOfClass("UIPadding")
				local ap, as = label.AbsolutePosition, label.AbsoluteSize
				local x0 = ap.X + (pad and pad.PaddingLeft.Offset or 0) * sc
				local x1 = ap.X + as.X - (pad and pad.PaddingRight.Offset or 0) * sc
				local tw = label.TextBounds.X
				local t0 = (align == L and x0) or (align == R and x1 - tw) or ((x0 + x1 - tw) / 2)
				local ip, is = box.AbsolutePosition, box.AbsoluteSize
				local space = after and (ip.X - (t0 + tw)) or (t0 - (ip.X + is.X))
				T.check(space >= gap - 0.5 and space <= gap + sc + 0.5,
					fmt("pixelicon lead: UIScale %.2f, %s, %s: the icon sits its gap outside the text", sc, align.Name, after and "after" or "before"),
					fmt("space %.1f, gap %.1f (text %.1f..%.1f, icon %.1f..%.1f)", space, gap, t0, t0 + tw, ip.X, ip.X + is.X))
			end
		end
		gui:Destroy()
		K.flushErrors("pixelicon_lead_uiscale")
	end)

	-- (g2) (U7b review) PixelIcon.Lead on the server: a Roblox server lays out no text, so TextBounds is expected to read 0
	-- there (forced here through Mock.TextExtent while Lead runs), and no client ever places a server-built icon again (the
	-- TextBounds / Text connections live on the server). The world signs Lead there: the machine and rarity-board prices,
	-- a locked pad's LockLabel, the gate card's stars. With the bounds at 0 every icon still sits its gap outside the text
	-- (as the client then lays the text out), for each alignment, before and after, on a fixed label and on an auto-sized
	-- one (tagText: AutomaticSize XY, centred)
	S.pixelicon_lead_server_measure = guarded("pixelicon_lead_server_measure", function()
		local PI = shared("PixelIcon")
		local Mock = rawget(_G, "Mock")
		if not (PI and Mock and type(Mock.TextExtent) == "function") then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		local root = Instance.new("Frame")
		root.Size = UDim2.fromOffset(600, 900)
		root.Parent = gui
		local L, R, C = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right, Enum.TextXAlignment.Center
		-- { alignment, after, auto-sized }
		local cases = { { L, false }, { L, true }, { R, false }, { R, true }, { C, false }, { C, true }, { C, false, true }, { C, true, true } }
		local realExtent = Mock.TextExtent
		for i, case in ipairs(cases) do
			local align, after, auto = case[1], case[2], case[3] == true
			local label = Instance.new("TextLabel")
			label.Position = UDim2.fromOffset(150, 20 + i * 60)
			label.Size = auto and UDim2.fromOffset(0, 26) or UDim2.fromOffset(300, 30)
			if auto then
				label.AutomaticSize = Enum.AutomaticSize.XY
			end
			label.TextSize = 22
			label.Text = "12,500"
			label.TextXAlignment = align
			label.Parent = root
			Mock.TextExtent = function()
				return 0, 0
			end
			local ok, box = pcall(PI.Lead, label, "token", { After = after })
			Mock.TextExtent = realExtent
			local tag = fmt("pixelicon lead, server: %s, %s%s", align.Name, after and "after" or "before", auto and ", auto-sized" or "")
			if T.check(ok and box ~= nil, tag .. ": Lead draws with TextBounds at 0", tostring(box)) then
				local px = PI.Snap(22 * 0.9)
				local gap = math.max(3, math.floor(px / 4))
				local pad = label:FindFirstChildOfClass("UIPadding")
				local ap, as = label.AbsolutePosition, label.AbsoluteSize
				local x0 = ap.X + (pad and pad.PaddingLeft.Offset or 0)
				local x1 = ap.X + as.X - (pad and pad.PaddingRight.Offset or 0)
				local tw = label.TextBounds.X
				local t0 = (align == L and x0) or (align == R and x1 - tw) or ((x0 + x1 - tw) / 2)
				local ip, is = box.AbsolutePosition, box.AbsoluteSize
				local space = after and (ip.X - (t0 + tw)) or (t0 - (ip.X + is.X))
				-- never over the text, and its own gap away: Theme.MeasureLabel measures this Enum-font label as the mock lays
				-- it out (a Nunito face runs a few per cent wide on a server, never short)
				T.check(tw > 0 and space >= gap - 0.5 and space <= gap + 1, tag .. ": the icon sits its gap outside the text, not over it",
					fmt("space %.1f, gap %d (text %.1f..%.1f, icon %.1f..%.1f)", space, gap, t0, t0 + tw, ip.X, ip.X + is.X))
			end
		end
		Mock.TextExtent = realExtent
		gui:Destroy()
		K.flushErrors("pixelicon_lead_server_measure")
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

	-- U6 (outline and font sweep) -------------------------------------------------------------------------------------
	-- one outline at most: an explicit Stroke never adds a classic stroke, under an Outline or alone, and restyling a label
	-- clears a classic stroke it carried
	S.theme_outline_one_ring = guarded("theme_outline_one_ring", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local both = Theme.Label("12", "Heading", { Stroke = 0.15, Outline = 2 })
		local rings = textStrokes(both)
		T.check(#rings == 1 and both.TextStrokeTransparency == 1, "kitb ring: Stroke 0.15 + Outline 2 = one 2 px outline and no classic stroke",
			#rings .. " outline(s), classic " .. tostring(both.TextStrokeTransparency))
		both:Destroy()
		for _, stroke in ipairs({ 0, 0.2, 0.5 }) do
			local l = Theme.Label("x", "Body", { Stroke = stroke })
			T.check(l.TextStrokeTransparency == 1 and #textStrokes(l) == 0, "kitb ring: Stroke " .. stroke .. " alone gives no stroke and no outline", tostring(l.TextStrokeTransparency))
			l:Destroy()
		end
		local old = Instance.new("TextLabel")
		old.TextStrokeTransparency = 0
		Theme.Style(old, "Button")
		T.check(old.TextStrokeTransparency == 1, "kitb ring: Theme.Style clears a classic stroke the label had", tostring(old.TextStrokeTransparency))
		old:Destroy()
		K.flushErrors("theme_outline_one_ring")
	end)

	-- Theme.Measure takes a role or an Enum font (the old GetTextSize helpers pass a font): an Enum font measures 1:1, an
	-- Unknown one (a Nunito face read back) as Body
	S.theme_measure_takes_font = guarded("theme_measure_takes_font", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local TS = game:GetService("TextService")
		local raw = TS:GetTextSize("Nimbus Climb", 20, Enum.Font.FredokaOne, Vector2.new(100000, 100000))
		local m = Theme.Measure("Nimbus Climb", Enum.Font.FredokaOne, 20)
		T.check(typeof(m) == "Vector2" and m.X == raw.X and m.Y == raw.Y, "kitb measure font: Theme.Measure(text, Enum font, size) = GetTextSize with that font", tostring(m) .. " vs " .. tostring(raw))
		local wrapRaw = TS:GetTextSize("Nimbus Climb is a game", 20, Enum.Font.FredokaOne, Vector2.new(60, 100000))
		local wrap = Theme.Measure("Nimbus Climb is a game", Enum.Font.FredokaOne, 20, 60)
		T.check(wrap.Y == wrapRaw.Y, "kitb measure font: an Enum font's wrap width is used as is", tostring(wrap) .. " vs " .. tostring(wrapRaw))
		local u = Theme.Measure("Nimbus Climb", Enum.Font.Unknown, 20)
		local b = Theme.Measure("Nimbus Climb", "Body", 20)
		T.check(u.X == b.X and u.Y == b.Y, "kitb measure font: Enum.Font.Unknown (a Nunito face read back) measures as Body", tostring(u) .. " vs " .. tostring(b))
		K.flushErrors("theme_measure_takes_font")
	end)

	-- the game's scripts as mounted in this world: { name = "client/Controllers/X.lua"-like path, src = text with comments out }
	local function gameSources()
		local out = {}
		for _, d in ipairs(game:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				local ok, src = pcall(function()
					return d.Source
				end)
				if ok and type(src) == "string" and src ~= "" then
					src = src:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
					out[#out + 1] = { inst = d, name = d:GetFullName(), src = src }
				end
			end
		end
		table.sort(out, function(a, b)
			return a.name < b.name
		end)
		return out
	end

	-- no script but shared/Theme sets .Font (Theme.SetRole keeps a role's FontFace) or measures with GetTextSize (Theme.Measure /
	-- Theme.MeasureLabel know the faces)
	S.kitb_no_direct_font = guarded("kitb_no_direct_font", function()
		local fonts, measures, n = {}, {}, 0
		for _, f in ipairs(gameSources()) do
			if not (f.inst.Name == "Theme" and f.inst:IsA("ModuleScript")) then
				n = n + 1
				local _, a = f.src:gsub("%.Font%s*=[^=]", "")
				local _, b = f.src:gsub("GetTextSize%s*%(", "")
				if a > 0 then
					fonts[#fonts + 1] = f.inst.Name .. " x" .. a
				end
				if b > 0 then
					measures[#measures + 1] = f.inst.Name .. " x" .. b
				end
			end
		end
		T.check(n > 20, "kitb font: the game's scripts are mounted", tostring(n))
		T.check(#fonts == 0, "kitb font: no script sets .Font directly (Theme.SetRole)", table.concat(fonts, ", "))
		T.check(#measures == 0, "kitb font: no script measures with GetTextSize (Theme.Measure / Theme.MeasureLabel)", table.concat(measures, ", "))
		K.flushErrors("kitb_no_direct_font")
	end)

	-- (U7a) the Cloud Token's cloud glyph (U+2601, as bytes or as the escape \226\152\129) is gone from every script: the
	-- currency is the PixelIcon coin (Theme.Currency.Tokens.Icon) and a sentence says "Tokens". U7a let U7b's glyph tables
	-- keep it; U7b redrew them, so no script is excused any more
	S.token_glyph_sources = guarded("token_glyph_sources", function()
		local U7B = {}
		local hits, n = {}, 0
		for _, f in ipairs(gameSources()) do
			n = n + 1
			if not U7B[f.inst.Name] and (f.src:find("\\226\\152\\129", 1, true) or f.src:find("\226\152\129", 1, true)) then
				hits[#hits + 1] = f.inst.Name
			end
		end
		T.check(n > 20, "token glyph: the game's scripts are mounted", tostring(n))
		T.check(#hits == 0, "token glyph: no script writes the cloud glyph (the token is its PixelIcon)", table.concat(hits, ", "))
		K.flushErrors("token_glyph_sources")
	end)

	-- (U7b) the emoji code points of a string (SmokeCommon.Emoji.Is), its decimal escapes (\240\159\143\134) read as the
	-- bytes they stand for; rich-text tags are NOT dropped (this reads source, where "<" is a comparison)
	local function emojiIn(s)
		local Is = SmokeCommon.Emoji.Is
		s = tostring(s or ""):gsub("\\(%d%d?%d?)", function(d)
			local b = tonumber(d)
			return b < 256 and string.char(b) or nil
		end)
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
				local b = s:byte(i + k)
				if not b or b < 0x80 or b > 0xBF then
					n, cp = 1, 0 -- not a UTF-8 sequence (a byte range in a pattern, "[\128-\255]"): one byte, no code point
					break
				end
				cp = cp * 64 + (b % 0x40)
			end
			if cp <= 0x10FFFF and Is(cp) then
				out[#out + 1] = string.format("U+%04X", cp)
			end
			i = i + n
		end
		return out
	end

	-- (U7b) the walk of U7a with zero allowed, at the source: no game script writes an emoji or pictographic code point
	-- (as UTF-8 or as escapes, comments aside): the glyph tables of the battle HUD, the arena, dungeon, train, care, fusion,
	-- index, obby, pets and picker windows, the tycoon catalog and the world signs are PixelIcons (Host / Lead) or words.
	-- Typography stays (the middle dot, the bullet, the dashes, the multiplication sign, the angle quotes)
	S.kitb_no_emoji_sources = guarded("kitb_no_emoji_sources", function()
		local hits, n = {}, 0
		for _, f in ipairs(gameSources()) do
			n = n + 1
			local cps = emojiIn(f.src)
			if #cps > 0 then
				hits[#hits + 1] = f.inst.Name .. " x" .. #cps .. " (" .. table.concat(cps, " ", 1, math.min(#cps, 4)) .. ")"
			end
		end
		T.check(n > 20, "kitb emoji sources: the game's scripts are mounted", tostring(n))
		T.check(#hits == 0, fmt("kitb emoji sources: no script writes an emoji code point (%d)", #hits), table.concat(hits, "; "))
		K.flushErrors("kitb_no_emoji_sources")
	end)

	-- (U7b) the icons U7b added and where they are named: each a 9 x 9 PixelIcon; TycoonCatalog's icons (a station's, a house
	-- tier's, the prestige pad's) are PixelIcon names, so the Home window and the pad signs draw them
	S.pixelicon_u7b_set = guarded("pixelicon_u7b_set", function()
		local PI = shared("PixelIcon")
		local TC = shared("TycoonCatalog")
		if not (PI and TC) then
			return
		end
		local missing = {}
		for _, name in ipairs({ "drop", "leaf", "target", "skull", "hourglass", "glass", "castle", "berry", "pot", "weight", "vault", "fence", "fountain", "basket", "pip", "up", "left", "shift" }) do
			if not (PI.Runs(name) and #PI.Runs(name) > 0) then
				missing[#missing + 1] = name
			end
		end
		T.check(#missing == 0, "pixelicon u7b: the battle, dungeon, train and home icons exist", table.concat(missing, ", "))
		local bad = {}
		local function want(where, icon)
			if not (type(icon) == "string" and PI.Bitmaps[icon]) then
				bad[#bad + 1] = where .. "=" .. tostring(icon)
			end
		end
		for key, icon in pairs(TC.Icons or {}) do
			want("Icons." .. key, icon)
		end
		for _, def in ipairs(TC.Stations or {}) do
			want(def.Id, def.Icon)
		end
		for _, tier in ipairs(TC.HouseTiers or {}) do
			want(tier.Id, tier.Icon)
		end
		local pp = type(TC.Get) == "function" and TC.Get("Prestige")
		want("Prestige", pp and pp.Icon)
		table.sort(bad)
		T.check(#bad == 0, "pixelicon u7b: every TycoonCatalog icon is a PixelIcon name", table.concat(bad, ", "))
		K.flushErrors("pixelicon_u7b_set")
	end)

	-- (U7b) the world signs (BillboardGui / SurfaceGui text the server builds: the lobby gates, the portals, the arena
	-- boards, the home pads, the spots' showcase tags, the courses): after the server run no text in the workspace carries
	-- an emoji code point, and the ratings and marks they had are PixelIcons there (the gates' stars at least). World
	-- signs stay still (owner 2026-11-13: only the menu and loading signs sway): an icon adds no motion
	S.kitb_no_emoji_world = guarded("kitb_no_emoji_world", function()
		local ws = game:GetService("Workspace")
		local hits, texts, icons = {}, 0, {}
		for _, d in ipairs(ws:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				texts = texts + 1
				local cps = emojiIn(d.Text)
				if #cps > 0 then
					hits[#hits + 1] = d:GetFullName() .. " '" .. tostring(d.Text) .. "'"
				end
			end
			local icon = d:GetAttribute("PixelIcon")
			if type(icon) == "string" and (d:FindFirstAncestorWhichIsA("BillboardGui") or d:FindFirstAncestorWhichIsA("SurfaceGui")) then
				icons[icon] = (icons[icon] or 0) + 1
			end
		end
		table.sort(hits)
		local names = {}
		for k, v in pairs(icons) do
			names[#names + 1] = k .. " x" .. v
		end
		table.sort(names)
		T.info(fmt("*kitb emoji world: %d texts, world sign icons: %s", texts, table.concat(names, ", ")))
		T.check(texts > 20, "kitb emoji world: the server built its signs", tostring(texts))
		T.check(#hits == 0, fmt("kitb emoji world: no world sign text carries an emoji code point (%d)", #hits), table.concat(hits, "; ", 1, math.min(#hits, 8)))
		T.check((icons.star or 0) > 0, "kitb emoji world: the gates' difficulty stars are PixelIcons on their signs")
		K.flushErrors("kitb_no_emoji_world")
	end)

	-- (U7b review) each world sign U7b redrew holds its icon, by sign: the token coin before every machine tag's price and
	-- every rarity-board price, the trophy after each arena board count, the gate card's stars (as many as its difficulty's
	-- Stars), and on a private plot built here: the lock before a locked pad's reason, the station's icon on a pad's name
	-- row, the star on a closed garden bed's sign, the up arrow on a bounce pad. The plot's signs are built the way a
	-- server builds them (TextBounds forced to 0, see pixelicon_lead_server_measure): the lock sits outside its text
	S.kitb_world_sign_icons = guarded("kitb_world_sign_icons", function()
		local IconOn = SmokeCommon.IconOn
		local Mock = rawget(_G, "Mock")
		local function mod(key)
			local inst = K.moduleInstance(key)
			local ok, m = false, nil
			if inst then
				ok, m = pcall(require, inst)
			end
			return ok and type(m) == "table" and m or nil
		end
		local Config, HB, CB, TC = mod("shared/Config"), mod("server/Services/HomeBuilder"), mod("server/Services/CourseBuilder"), mod("shared/TycoonCatalog")
		if not T.check(Config and HB and CB and TC and Mock and IconOn, "kitb world icons: Config, HomeBuilder, CourseBuilder, TycoonCatalog and SmokeCommon.IconOn load") then
			return
		end
		local ws = game:GetService("Workspace")
		local function inSurface(d)
			return d:FindFirstAncestorWhichIsA("SurfaceGui") ~= nil
		end
		local tags, boards, trophies, gates, bad = 0, 0, 0, 0, {}
		local function want(where, label, name, which, count)
			local got, n = IconOn(label, which)
			if got ~= name or (count and n ~= count) then
				bad[#bad + 1] = fmt("%s: %s x%d (want %s%s)", where, tostring(got), n, name, count and (" x" .. count) or "")
			end
		end
		local stars = {}
		for _, d in ipairs(Config.Difficulties or {}) do
			stars[tostring(d.DisplayName or d.Id)] = tonumber(d.Stars) or 1
		end
		for _, d in ipairs(ws:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Name == "PriceBillboard" then
				tags = tags + 1
				want(d:GetFullName(), d:FindFirstChild("PriceLabel", true), "token", "Lead")
			elseif d:IsA("TextLabel") and d.Name:match("^Price%d+$") and d:FindFirstAncestor("RarityBoard") then
				boards = boards + 1
				want(d:GetFullName(), d, "token", "Lead")
			elseif d:IsA("TextLabel") and d.Name == "Trophies" and d:FindFirstAncestor("LeaderGui") then
				trophies = trophies + 1
				want(d:GetFullName(), d, "trophy", "Trail")
			elseif d:IsA("TextLabel") and d.Name == "Info" and d:FindFirstAncestorWhichIsA("BillboardGui") and d:FindFirstChild("LeadIcon") then
				local diff = tostring(d.Text):match("^(.-) %- %d+/%d+ players$")
				if diff and stars[diff] then
					gates = gates + 1
					want(d:GetFullName(), d, "star", "Lead", stars[diff])
					local box = d:FindFirstChild("LeadIcon")
					local drawn = 0
					for _, c in ipairs(box:GetChildren()) do
						if c:GetAttribute("PixelIcon") == "star" then
							drawn = drawn + 1
						end
					end
					if drawn ~= stars[diff] then
						bad[#bad + 1] = fmt("%s: %d stars drawn, %s has %d", d:GetFullName(), drawn, diff, stars[diff])
					end
				end
			end
		end
		T.check(tags >= 4 and boards >= 4 and trophies == 10 and gates >= 1, "kitb world icons: the machine tags, the rarity-board prices, the arena board rows and a gate card are found",
			fmt("%d tags, %d board prices, %d trophy rows, %d gate cards", tags, boards, trophies, gates))
		-- a private plot far from the lobby, built with the server's bounds (TextBounds 0)
		local root = Instance.new("Folder")
		root.Name = "SmokeSignIcons"
		root.Parent = ws
		local spotFolder = Instance.new("Folder")
		spotFolder.Name = "Spot_97"
		spotFolder.Parent = root
		local plotCF = CFrame.new(-4000, 300, 4000)
		local spot = { Index = 97, PlotCFrame = plotCF, PlotSize = TC.PlotSize, Center = plotCF.Position, Folder = spotFolder }
		local realExtent = Mock.TextExtent
		Mock.TextExtent = function()
			return 0, 0
		end
		-- the pads as TycoonCatalog.AvailablePads lists them (each with its station's Icon)
		local function icon(id)
			local def = TC.Get(id)
			return def and def.Icon
		end
		local okPlot, err = pcall(function()
			HB.PreparePlot(spot)
			HB.SetPads(spot, {
				{ StationId = "DecorFountain", Icon = icon("DecorFountain"), NextLevel = 1, Price = 0, Level = 0, Title = "Fountain", Locked = "Unlocks at Home Level 3", LevelText = "" },
				{ StationId = "Kitchen", Icon = icon("Kitchen"), NextLevel = 2, Price = 50, Level = 1, Title = "Food Machine", LevelText = "Lv 1 -> 2" },
			})
		end)
		Mock.TextExtent = realExtent
		T.check(okPlot, "kitb world icons: a private plot takes a locked and an open pad", tostring(err))
		local lock, nameIcons = nil, 0
		for _, d in ipairs(spotFolder:GetDescendants()) do
			if d:IsA("TextLabel") and d.Name == "LockLabel" then
				lock = d
			elseif d:IsA("TextLabel") and d.Name == "Icon" and d:FindFirstAncestor("PadSign") then
				nameIcons = nameIcons + 1
				local model = d:FindFirstAncestorWhichIsA("Model")
				want(d:GetFullName(), d, icon(model and model:GetAttribute("StationId") or "") or "?")
			end
		end
		T.check(nameIcons == 2, "kitb world icons: each pad sign's name row hosts its station's icon", tostring(nameIcons))
		if T.check(lock ~= nil, "kitb world icons: the locked pad's sign has its LockLabel") then
			want(lock:GetFullName(), lock, "lock", "Lead")
			local box = lock:FindFirstChild("LeadIcon")
			if box then
				local pad = lock:FindFirstChildOfClass("UIPadding")
				local ap, as = lock.AbsolutePosition, lock.AbsoluteSize
				local x0 = ap.X + (pad and pad.PaddingLeft.Offset or 0)
				local x1 = ap.X + as.X - (pad and pad.PaddingRight.Offset or 0)
				local tw = lock.TextBounds.X
				local t0 = (lock.TextXAlignment == Enum.TextXAlignment.Left and x0) or (lock.TextXAlignment == Enum.TextXAlignment.Right and x1 - tw) or ((x0 + x1 - tw) / 2)
				local right = box.AbsolutePosition.X + box.AbsoluteSize.X
				T.check(tw > 0 and right <= t0 + 0.5, "kitb world icons: the server-built lock sits before its text, not over it",
					fmt("icon ends %.1f, text %.1f..%.1f", right, t0, t0 + tw))
			end
		end
		-- a closed garden bed's sign (the Garden at its base places, so the rest are closed)
		local okG, garden = pcall(HB.BuildStationModel, "Garden", 1, nil, 1)
		local closed = 0
		for _, d in ipairs(okG and garden and garden:GetDescendants() or {}) do
			if d:IsA("TextLabel") and d.Name == "Star" and inSurface(d) then
				closed = closed + 1
				want("Garden " .. d:GetFullName(), d, "star")
			end
		end
		T.check(closed > 0, "kitb world icons: a closed garden bed's sign is found", tostring(garden))
		if okG and garden then
			garden:Destroy()
		end
		-- a bounce pad's arrow: the first layout with a Bounce step
		local layout = nil
		for _, diff in ipairs(Config.Difficulties or {}) do
			for seed = 1, 12 do
				local okL, l = pcall(CB.GenerateLayout, diff.Id, seed)
				if okL and type(l) == "table" then
					for _, st in ipairs(l.Steps or {}) do
						if st.Kind == "Bounce" then
							layout = l
							break
						end
					end
				end
				if layout then
					break
				end
			end
			if layout then
				break
			end
		end
		local arrows = 0
		if T.check(layout ~= nil, "kitb world icons: a course layout with a bounce pad") then
			local okC, info = pcall(CB.Build, layout, Vector3.new(-30000, 900, 0), root)
			for _, d in ipairs(okC and type(info) == "table" and info.Folder and info.Folder:GetDescendants() or {}) do
				if d:IsA("TextLabel") and d:FindFirstAncestor("PadGlyph") then
					arrows = arrows + 1
					want("bounce " .. d:GetFullName(), d, "up")
				end
			end
			T.check(okC and arrows > 0, "kitb world icons: the bounce pads are built", tostring(info))
		end
		root:Destroy()
		table.sort(bad)
		T.info(fmt("*kitb world icons: %d tags, %d board prices, %d trophy rows, %d gate cards, %d pad name icons, %d closed beds, %d bounce arrows", tags, boards, trophies, gates, nameIcons, closed, arrows))
		T.check(#bad == 0, fmt("kitb world icons: every world sign holds its icon (%d wrong)", #bad), table.concat(bad, "; ", 1, math.min(#bad, 8)))
		K.flushErrors("kitb_world_sign_icons")
	end)

	-- corner radii are Theme.Radius tokens ("None", "S", "M", and "Round" for a pill or a disc) in every file U6 swept; the
	-- list is check.mjs's RADIUS_SWEPT (its radius-literal rule holds the same files), so U7 / U9 add families in one place
	S.kitb_radius_tokens = guarded("kitb_radius_tokens", function()
		local Theme = theme()
		if not Theme then
			return
		end
		local f = Instance.new("Frame")
		local round = Theme.Corner(f, "Round")
		T.check(round and round.CornerRadius.Scale == 0.5 and round.CornerRadius.Offset == 0, "kitb radius: Theme.Corner(obj, 'Round') = UDim(0.5, 0) (a pill or a disc)", round and tostring(round.CornerRadius) or "nil")
		local s = Theme.Corner(f, "S")
		T.check(s and s.CornerRadius.Offset == 4, "kitb radius: Theme.Corner(obj, 'S') = 4 px")
		f:Destroy()
		local fh = io.open("tools/check.mjs", "r")
		local js = fh and fh:read("*a") or ""
		if fh then
			fh:close()
		end
		local list = js:match("const RADIUS_SWEPT = %[(.-)%]")
		if not T.check(list ~= nil, "kitb radius: tools/check.mjs lists the swept files (RADIUS_SWEPT)") then
			return
		end
		local want = {}
		for p in list:gmatch("\"([^\"]+)\"") do
			want[p:match("([^/]+)%.lua$") or p] = p
		end
		local seen, bad = 0, {}
		for _, src in ipairs(gameSources()) do
			local key = src.inst.Name
			if want[key] then
				seen = seen + 1
				local text = src.src
				local hits = 0
				for _, pat in ipairs({
					"Theme%.Corner%([^()]-,%s*%-?%d[%d%.]*%s*%)", -- Theme.Corner(x, 12)
					"Theme%.Corner%([^()]-,%s*UDim%.new%(%s*0%s*,%s*%d[%d%.]*%s*%)%s*%)", -- Theme.Corner(x, UDim.new(0, 12))
					"Theme%.Corner%([%w_%.%[%]\"]+%)", -- Theme.Corner(x): the old 12 px default
					"CornerRadius%s*=%s*UDim%.new%(%s*0%s*,%s*%d", -- .CornerRadius = UDim.new(0, 12)
					"[^%w_%.:]corner%([^()]-,%s*%d[%d%.]*%s*[,%)]", -- a file's own corner(x, 12) helper
				}) do
					local _, c = text:gsub(pat, "")
					hits = hits + c
				end
				if hits > 0 then
					bad[#bad + 1] = key .. " x" .. hits
				end
			end
		end
		local listed = 0
		for _ in pairs(want) do
			listed = listed + 1
		end
		T.check(listed > 0 and seen >= listed, "kitb radius: every swept file is mounted", seen .. " of " .. listed)
		T.check(#bad == 0, "kitb radius: no literal corner radius in a swept file (Theme.Radius tokens)", table.concat(bad, ", "))
		K.flushErrors("kitb_radius_tokens")
	end)

	-- U6 casing (the owner saw LuckiestGuy's odd lower-case "e" in "PeTS"): Title, Sign, Accent and Tag labels read in
	-- capitals, the text they are made with and every text set later; rich text tags and entities stay as written; the
	-- reading and button roles keep their case; a label moved to a reading role keeps the case of later texts; Theme.Measure
	-- and Theme.MeasureLabel measure the capitals
	S.theme_caps_roles = guarded("theme_caps_roles", function()
		local Theme = theme()
		if not Theme then
			return
		end
		for _, role in ipairs({ "Title", "Sign", "Accent", "Tag" }) do
			local l = Theme.Label("Pets", role)
			T.check(l.Text == "PETS", "kitb caps: a " .. role .. " label reads in capitals", l.Text)
			l.Text = "Daily gift"
			T.check(l.Text == "DAILY GIFT", "kitb caps: ...and so does a text set later (" .. role .. ")", l.Text)
			l:Destroy()
		end
		local rich = Theme.Label("<font color=\"#FFD24A\">Pets</font> &amp; eggs", "Title")
		T.check(rich.Text == "<font color=\"#FFD24A\">PETS</font> &amp; EGGS", "kitb caps: rich text tags and entities stay as written", rich.Text)
		rich:Destroy()
		T.check(Theme.Caps("Lv 5 \194\183 a < b") == "LV 5 \194\183 A < B", "kitb caps: Theme.Caps keeps UTF-8 symbols and a lone '<'", Theme.Caps("Lv 5 \194\183 a < b"))
		for _, role in ipairs({ "Heading", "Button", "Body", "Label", "Display", "Script", "Toast", "Nameplate" }) do
			local l = Theme.Label("Feed", role)
			T.check(l.Text == "Feed", "kitb caps: a " .. role .. " label keeps its case", l.Text)
			l:Destroy()
		end
		local moved = Theme.Label("Pets", "Title")
		Theme.SetRole(moved, "Body")
		moved.Text = "Lucky pets"
		T.check(moved.Text == "Lucky pets", "kitb caps: a label moved to a reading role keeps the case of later texts", moved.Text)
		moved:Destroy()
		local box = Instance.new("TextBox")
		box.Text = "typed"
		Theme.Style(box, "Title")
		T.check(box.Text == "typed", "kitb caps: a TextBox keeps what the player typed", box.Text)
		box:Destroy()
		local a, b = Theme.Measure("Pets", "Title", 30), Theme.Measure("PETS", "Title", 30)
		T.check(a.X == b.X, "kitb caps: Theme.Measure measures a Title in capitals", tostring(a) .. " vs " .. tostring(b))
		local t = Theme.Label("PETS", "Title", { Size = 30 })
		local m = Theme.MeasureLabel(t, "Pets")
		T.check(m.X == b.X, "kitb caps: Theme.MeasureLabel measures a Title label's text in capitals", tostring(m) .. " vs " .. tostring(b))
		t:Destroy()
		K.flushErrors("theme_caps_roles")
	end)

	-- (T0, the owner's title pick B: FredokaOne titles) the one title helper: Theme.StyleTitle(label) is where the designed
	-- title treatment goes. (sign/logo build, the owner's pick T1 2026-11-13) it is the folded ribbon: a navy band (its
	-- highlight, lip and two brass piping lines) that overhangs the title's box, a swallowtail tail at each end, the letters
	-- in GOLD (three hard bands) with ONE brown outline over a navy shadow copy, and a gold underline that ends in three
	-- rising steps. The label's own text is hidden under the ribbon's copies (a UIGradient, so the caller's props stay as
	-- they were) and the copies follow the label (text, size, transparency). Stamps TitleLook = "Ribbon"; twice is the same
	-- as once; nil is a no-op
	S.theme_style_title = guarded("theme_style_title", function()
		local Theme = theme()
		if not Theme then
			return
		end
		if not T.check(type(Theme.StyleTitle) == "function", "kitb title: Theme.StyleTitle exists") then
			return
		end
		local Sg = Theme.Sign
		-- a ColorSequence / NumberSequence at time t
		local function colourAt(seq, t)
			local kps = seq.Keypoints
			for i = 1, #kps - 1 do
				local a, b = kps[i], kps[i + 1]
				if t >= a.Time and t <= b.Time then
					local f = b.Time > a.Time and (t - a.Time) / (b.Time - a.Time) or 0
					return a.Value:Lerp(b.Value, f)
				end
			end
			return kps[#kps].Value
		end
		local function ofKind(root, name)
			local out = {}
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == name or d:GetAttribute("Ribbon") == name then
					out[#out + 1] = d
				end
			end
			return out
		end
		local l = Theme.Label("Pets", "Title", { Size = 34, Color = Sg.Gold })
		l.Size = UDim2.fromOffset(420, 58)
		l.TextXAlignment = Enum.TextXAlignment.Left
		local font, size, colour, text = l.Font, l.TextSize, l.TextColor3, l.Text
		local before = #l:GetDescendants()
		T.check(Theme.StyleTitle(l) == l, "kitb title: StyleTitle returns the label")
		Theme.StyleTitle(l)
		-- the ribbon hangs its pieces straight under the label (no holder frame) and stays light: the hatch stage's roll
		-- look keeps a whole-screen instance budget, and its title wears the ribbon too
		T.check(#l:GetDescendants() - before <= 25, "kitb title: the ribbon adds at most 25 instances to a title", tostring(#l:GetDescendants() - before))
		T.check(l:GetAttribute("TitleLook") == "Ribbon", "kitb title: StyleTitle stamps TitleLook = Ribbon (the owner's T1)", tostring(l:GetAttribute("TitleLook")))
		T.check(l.Font == Enum.Font.FredokaOne and l.Font == font and l.TextSize == size and sameColor(l.TextColor3, colour) and l.Text == text and l.TextStrokeTransparency == 1,
			"kitb title: the caller's label keeps its font, size, colour and text (no classic stroke)", tostring(l.Font) .. " " .. tostring(l.TextSize))
		local ribbons = {}
		for _, c in ipairs(l:GetChildren()) do
			if c.Name == "RibbonBand" then
				ribbons[#ribbons + 1] = l
			end
		end
		T.eq(#ribbons, 1, "kitb title: one ribbon (one RibbonBand) under the title, twice styled too")
		local hide = l:FindFirstChild("TitleHide")
		local hidden = hide and hide:IsA("UIGradient")
		if hidden then
			for _, kp in ipairs(hide.Transparency.Keypoints) do
				hidden = hidden and kp.Value >= 0.999
			end
		end
		T.check(hidden, "kitb title: the label's own text is hidden under the ribbon's copies (a fully see-through UIGradient)")
		local rib = ribbons[1]
		if not T.check(rib ~= nil, "kitb title: (setup) the ribbon") then
			l:Destroy()
			return
		end
		local k = 34 / 20 -- the pitch drew T1 at a 20 px title
		-- the band: navy, 1.5x the text size tall, overhanging the title's box on both sides
		local band = rib:FindFirstChild("RibbonBand")
		T.check(band ~= nil and sameColor(band.BackgroundColor3, Sg.Navy) and band.BackgroundTransparency == 0, "kitb title: a navy band", band and hex(band.BackgroundColor3) or "missing")
		local tw34 = Theme.Measure("PETS", "Title", 34).X
		T.check(band ~= nil and math.abs(band.Size.Y.Offset - math.floor(30 * k + 0.5)) <= 1 and band.Size.X.Scale == 0 and band.Position.X.Scale == 0
			and band.Position.X.Offset > 0 and band.Size.X.Offset > tw34 and band.Position.X.Offset + band.Size.X.Offset < 420 / 2,
			"kitb title: the band is 1.5x the text tall and wraps the text inside the title's box (not the box's whole width)",
			band and tostring(band.Size) .. " at " .. tostring(band.Position) or "")
		-- (sign/logo review, SIGN2 renders) no overhang on the left either: it covered the Shop's egg icon and poked out of
		-- the Pets window's frame. The left tail's notch ends at the box's edge, and the letters move in onto the band
		local tailL = rib:FindFirstChild("TailL")
		local leftmost = math.huge
		if tailL then
			leftmost = tailL.Position.X.Offset
			for _, n in ipairs(tailL:GetChildren()) do
				leftmost = math.min(leftmost, tailL.Position.X.Offset + n.Position.X.Offset)
			end
		end
		T.check(tailL ~= nil and tailL.Position.X.Scale == 0 and leftmost == 0, "kitb title: a header title's ribbon starts at its box's left edge (the tail's notch too)",
			fmt("left tail starts at %s px", tostring(leftmost)))
		local faceIn = rib:FindFirstChild("TitleFace")
		T.check(faceIn ~= nil and band ~= nil and faceIn.Position.X.Offset > band.Position.X.Offset and faceIn.Size.X.Offset == -faceIn.Position.X.Offset,
			"kitb title: ...and its letters start on the band, their box narrowed to match", faceIn and (tostring(faceIn.Position) .. " " .. tostring(faceIn.Size)) or "")
		-- (SIGN2 render, 390x844 Pets) a phone's header puts the A/B/C buttons right after the title's box: the ribbon (the
		-- band and the right tail with its notch) ends inside the box on the right, never over the next control
		local tailR = rib:FindFirstChild("TailR")
		local reach = -math.huge
		if tailR then
			local x0 = tailR.Position.X.Scale * 420 + tailR.Position.X.Offset
			reach = x0 + tailR.Size.X.Offset
			for _, n in ipairs(tailR:GetChildren()) do
				reach = math.max(reach, x0 + n.Position.X.Offset + n.Size.X.Offset)
			end
			reach = reach - 420
		end
		T.check(band ~= nil and tailR ~= nil and reach <= 0 and band.Position.X.Offset + band.Size.X.Offset <= 420,
			"kitb title: a header title's ribbon ends inside its box on the right (the tail's notch too)", fmt("right tail reaches %s px past the box", tostring(reach)))
		if band then
			local hi, lip, pipes = band:FindFirstChild("Highlight"), band:FindFirstChild("Lip"), ofKind(band, "Piping")
			T.check(hi ~= nil and sameColor(hi.BackgroundColor3, Sg.NavyTop) and hi.Position.Y.Offset == 0, "kitb title: a lighter top highlight on the band")
			T.check(lip ~= nil and sameColor(lip.BackgroundColor3, Sg.NavyLip) and lip.AnchorPoint.Y == 1, "kitb title: a darker bottom lip on the band")
			local brass = 0
			for _, p in ipairs(pipes) do
				if sameColor(p.BackgroundColor3, Sg.Brass) and p.Size.X.Scale == 1 then
					brass = brass + 1
				end
			end
			T.eq(brass, 2, "kitb title: two brass piping lines along the band")
		end
		-- the tails: two, darker, behind the band, sticking out past its ends, a stepped swallowtail notch on the outer end
		local tails = ofKind(rib, "Tail")
		T.eq(#tails, 2, "kitb title: a tail at each end of the band")
		local leftOut, rightOut, notched = false, false, 0
		local function at(u)
			return u.Scale * 420 + u.Offset -- an x in the 420 px title's box
		end
		for _, t in ipairs(tails) do
			if band and t.Name == "TailL" and at(t.Position.X) < at(band.Position.X) then
				leftOut = true
			elseif band and t.Name == "TailR" and at(t.Position.X) + t.Size.X.Offset > at(band.Position.X) + at(band.Size.X) then
				rightOut = true
			end
			if #ofKind(t, "Notch") >= 2 then
				notched = notched + 1
			end
			T.check(t.ZIndex < (band and band.ZIndex or 0), "kitb title: a tail sits behind the band")
		end
		T.check(leftOut and rightOut, "kitb title: the tails stick out past both ends of the band")
		T.eq(notched, 2, "kitb title: each tail has a stepped swallowtail notch")
		-- the letters: a navy shadow copy, then the gold face with one brown outline
		local face, shadow = rib:FindFirstChild("TitleFace"), rib:FindFirstChild("TitleShadow")
		if T.check(face ~= nil and shadow ~= nil and face:IsA("TextLabel") and shadow:IsA("TextLabel"), "kitb title: a Face and a Shadow copy of the text") then
			T.check(face.Text == "PETS" and shadow.Text == "PETS" and face:GetAttribute("FontRole") == "Title" and face.Font == Enum.Font.FredokaOne and face.TextSize == 34,
				"kitb title: the copies read the title (Title role, FredokaOne, its size)", face.Text .. " " .. tostring(face.Font) .. " " .. tostring(face.TextSize))
			local g = face:FindFirstChildOfClass("UIGradient")
			T.check(sameColor(face.TextColor3, Color3.new(1, 1, 1)) and g ~= nil and g.Rotation == 90, "kitb title: the face is white under a vertical gradient")
			if g then
				T.check(sameColor(colourAt(g.Color, 0.2), Sg.GoldLight) and sameColor(colourAt(g.Color, 0.6), Sg.Gold) and sameColor(colourAt(g.Color, 0.9), Sg.GoldDeep),
					"kitb title: ...GOLD in three bands (light to 45 %, gold to 80 %, deep below)",
					hex(colourAt(g.Color, 0.2)) .. " " .. hex(colourAt(g.Color, 0.6)) .. " " .. hex(colourAt(g.Color, 0.9)))
				T.check(not sameColor(colourAt(g.Color, 0.44), colourAt(g.Color, 0.46)) and sameColor(colourAt(g.Color, 0.3), colourAt(g.Color, 0.44)),
					"kitb title: ...hard bands (no smooth blend)")
			end
			local fs = textStrokes(face)
			T.check(#fs == 1 and sameColor(fs[1].Color, Sg.Text) and fs[1].Thickness >= 2, "kitb title: ONE brown outline on the face (the U6 Title exception)",
				#fs .. " outlines" .. (fs[1] and (" " .. hex(fs[1].Color) .. " " .. tostring(fs[1].Thickness)) or ""))
			T.check(sameColor(shadow.TextColor3, Sg.NavyLip) and shadow.Position.Y.Offset >= 3 and shadow.ZIndex < face.ZIndex, "kitb title: a navy shadow copy below and behind the face",
				hex(shadow.TextColor3) .. " +" .. tostring(shadow.Position.Y.Offset))
			-- the underline and its stair: gold, under the text, three steps rising to the right after it
			local under = rib:FindFirstChild("RibbonUnderline")
			local steps = ofKind(rib, "Step")
			local w = Theme.Measure("PETS", "Title", 34).X
			T.check(under ~= nil and sameColor(under.BackgroundColor3, Sg.Gold) and math.abs(under.Size.X.Offset - w) <= 2 and under.ZIndex < shadow.ZIndex,
				"kitb title: a gold underline as wide as the text, under the letters", under and tostring(under.Size) or "missing")
			table.sort(steps, function(a, b)
				return a.Position.X.Offset < b.Position.X.Offset
			end)
			local rising = #steps == 3
			for i = 2, #steps do
				rising = rising and steps[i].Size.Y.Offset > steps[i - 1].Size.Y.Offset and steps[i].Position.X.Offset > steps[i - 1].Position.X.Offset
			end
			T.check(rising and under ~= nil and steps[1].Position.X.Offset >= under.Position.X.Offset + under.Size.X.Offset - 1 and sameColor(steps[1].BackgroundColor3, Sg.Gold),
				"kitb title: ...that ends in three gold steps rising to the right", tostring(#steps) .. " steps")
			T.check(band ~= nil and tails[1] ~= nil and tails[1].ZIndex < band.ZIndex and band.ZIndex < under.ZIndex and under.ZIndex < shadow.ZIndex and shadow.ZIndex < face.ZIndex,
				"kitb title: drawn back to front: tails, band, underline, shadow, face")
			-- the copies follow the label
			l.Text = "Shop"
			T.check(face.Text == "SHOP" and shadow.Text == "SHOP", "kitb title: a new text on the title shows on its copies (in capitals)", face.Text .. " / " .. shadow.Text)
			T.check(under ~= nil and math.abs(under.Size.X.Offset - Theme.Measure("SHOP", "Title", 34).X) <= 2, "kitb title: ...and the underline fits the new text", under and tostring(under.Size) or "")
			-- the ribbon measures the text the label really draws (its TextBounds, once it has them): the renders' font
			-- metrics, Roblox's own text layout
			local savedExtent = Mock.TextExtent
			Mock.TextExtent = function(obj, limit)
				if obj == l then
					return 123, 34
				end
				return savedExtent(obj, limit)
			end
			l.Text = "Shop!"
			local okTB = under ~= nil and math.abs(under.Size.X.Offset - 123) <= 1
			Mock.TextExtent = savedExtent
			l.Text = "Shop"
			T.check(okTB, "kitb title: the underline follows the label's TextBounds when it has them", under and tostring(under.Size) or "")
			l.TextSize = 28
			T.check(face.TextSize == 28 and shadow.TextSize == 28 and band ~= nil and math.abs(band.Size.Y.Offset - 42) <= 1, "kitb title: a new size resizes the copies and the band",
				tostring(face.TextSize) .. " band " .. (band and tostring(band.Size.Y.Offset) or ""))
			l.TextTransparency = 0.5
			T.check(face.TextTransparency == 0.5 and shadow.TextTransparency == 0.5 and fs[1] ~= nil and fs[1].Transparency == 0.5,
				"kitb title: a fade on the title fades its copies and outline", tostring(face.TextTransparency))
			l.TextXAlignment = Enum.TextXAlignment.Center
			T.check(under ~= nil and under.Position.X.Scale == 0.5 and face.TextXAlignment == Enum.TextXAlignment.Center, "kitb title: a centred title centres its copies and underline")
			-- a centred title (a dialog, the hatch stage) hangs a banner round its text, not across its whole box: it stays
			-- on the screen however wide the box is
			local tw = Theme.Measure("SHOP", "Title", 28).X
			T.check(band ~= nil and band.Size.X.Scale == 0 and band.Position.X.Scale == 0.5 and band.Size.X.Offset > tw and band.Size.X.Offset < tw + 6 * 28
				and math.abs(band.Position.X.Offset + band.Size.X.Offset / 2) <= 1, "kitb title: a centred title's band fits round its text (with room for the steps)",
				band and (tostring(band.Size) .. " at " .. tostring(band.Position)) or "")
		end
		l:Destroy()
		T.check(Theme.StyleTitle(nil) == nil, "kitb title: StyleTitle(nil) is a no-op")
		T.check(type(Theme.OutlineOnPlate) == "table" and Theme.OutlineOnPlate.Title == true and next(Theme.OutlineOnPlate, "Title") == nil and next(Theme.OutlineOnPlate) == "Title",
			"kitb title: the U6 exception is written down: only the Title role may carry one outline on a plate (Theme.OutlineOnPlate)")
		-- (T0 review) a heading that is not a window's name passes its Theme.TitleExempt kind: stamped with it, nothing added
		local kinds = 0
		for kind, why in pairs(Theme.TitleExempt or {}) do
			kinds = kinds + 1
			T.check(type(why) == "string" and #why > 20, "kitb title: exempt kind " .. tostring(kind) .. " gives its reason", tostring(why))
			local h = Theme.Label("Best times", "Title", { Size = 28 })
			local n = #h:GetChildren()
			Theme.StyleTitle(h, kind)
			T.check(h:GetAttribute("TitleLook") == kind and #h:GetChildren() == n, "kitb title: StyleTitle(label, " .. tostring(kind) .. ") stamps the kind and adds nothing",
				tostring(h:GetAttribute("TitleLook")))
			h:Destroy()
		end
		T.check(kinds >= 3 and Theme.TitleExempt.Plain == nil and Theme.TitleExempt.Ribbon == nil and Theme.TitleExempt.Logo ~= nil,
			"kitb title: Theme.TitleExempt names its kinds (Section, OwnGradient, Logo), never Plain or Ribbon", tostring(kinds))
		K.flushErrors("theme_style_title")
	end)

	-- (kit-b merge, U8 x T1) a header title's ribbon under a UIScale: Roblox's TextBounds and AbsoluteSize are screen px
	-- (after every UIScale on and above the label) while the ribbon's offsets are the label's own px. The Pets window's
	-- Signboard header sits under its Fit UIScale; at 390x844 the right tail's notch reached 16 px past the title's box,
	-- onto the A button. At 0.8, 1, 1.25 and 1.7 the right tail (its notch too) ends inside the box and the underline is
	-- as wide as the text in the label's own px
	S.theme_title_ribbon_uiscale = guarded("theme_title_ribbon_uiscale", function()
		local Theme = theme()
		local Mock = rawget(_G, "Mock")
		if not (Theme and Theme.StyleTitle and Mock) then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		for _, sc in ipairs({ 0.8, 1, 1.25, 1.7 }) do
			local root = Instance.new("Frame")
			root.Size = UDim2.fromOffset(400, 200)
			local ui = Instance.new("UIScale")
			ui.Scale = sc
			ui.Parent = root
			root.Parent = gui
			local l = Theme.Label("PETS", "Title", { Size = 24 })
			l.Size = UDim2.fromOffset(110, 40)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Parent = root
			Theme.StyleTitle(l)
			local tailR, under = l:FindFirstChild("TailR"), l:FindFirstChild("RibbonUnderline")
			local reach = math.huge
			if tailR then
				reach = tailR.Position.X.Offset + tailR.Size.X.Offset
				for _, n in ipairs(tailR:GetChildren()) do
					reach = math.max(reach, tailR.Position.X.Offset + n.Position.X.Offset + n.Size.X.Offset)
				end
			end
			T.check(tailR ~= nil and tailR.Position.X.Scale == 0 and reach <= 110,
				fmt("kitb title: UIScale %.2f, the right tail (its notch too) ends inside the 110 px box", sc), fmt("reaches %s", tostring(reach)))
			local own = Mock.TextExtent(l)
			T.check(under ~= nil and math.abs(under.Size.X.Offset - own) <= 2,
				fmt("kitb title: UIScale %.2f, the underline is the text's width in the label's own px", sc),
				fmt("underline %s, text %.1f", under and tostring(under.Size.X.Offset) or "missing", own))
		end
		gui:Destroy()
		K.flushErrors("theme_title_ribbon_uiscale")
	end)

	-- (render gate, GATE_KITB finding 1; the pitch title_T1: "The band sizes to the header; the tails are fixed") a
	-- SignKit.Header with Ribbon: its navy plate IS the band (the lit top, the lip, two brass pipings, the header's whole
	-- width), reaching HeaderBand.Over past the frame on each side with a swallowtail tail behind each end; the title keeps
	-- only its letters, underline and stair (its own band and tails hidden), the underline on the plate's low piping.
	-- SignKit.HeaderOverhang(head, false) pulls the band inside the rim and drops the tails, the title staying put. A title
	-- with RibbonBand = "NoTails" (on a navy header that is not the band) keeps its own band from its box's edge, no tails
	S.theme_title_ribbon_modes = guarded("theme_title_ribbon_modes", function()
		local Theme, SK = theme(), shared("SignKit")
		if not (Theme and SK) then
			return
		end
		if not T.check(type(SK.HeaderOverhang) == "function" and type(SK.HeaderBand) == "table", "ribbon modes: SignKit.HeaderOverhang and SignKit.HeaderBand exist") then
			return
		end
		local Sg = Theme.Sign
		local gui = Instance.new("ScreenGui")
		gui.IgnoreGuiInset = true
		local win = Instance.new("Frame")
		win.Size = UDim2.fromOffset(900, 600)
		win.Position = UDim2.fromOffset(100, 100)
		win.Parent = gui
		local head, plate = SK.Header(win, { Title = "Pets", TitleSize = 34, Height = 64, Rim = 6, IconSlot = true, Reserve = 70, Ribbon = true })
		local title = plate:FindFirstChild("Title")
		local over = SK.HeaderBand.Over
		if not T.check(title ~= nil and title:GetAttribute("TitleLook") == "Ribbon" and title:GetAttribute("RibbonBand") == "Header",
			"ribbon modes: a Ribbon header's title wears the ribbon with RibbonBand = Header") then
			gui:Destroy()
			return
		end
		T.check(sameColor(plate.BackgroundColor3, Sg.Navy) and plate.Position.X.Offset == -over and plate.Size.X.Scale == 1 and plate.Size.X.Offset == 2 * over,
			"ribbon modes: the plate is the band the header's width, out over the frame by HeaderBand.Over each side", tostring(plate.Position) .. " " .. tostring(plate.Size))
		local lines = {}
		for _, name in ipairs({ "BandTop", "BandLip", "BandPipeTop", "BandPipeLow" }) do
			local f = plate:FindFirstChild(name)
			lines[name] = f
			T.check(f ~= nil and f.Size.X.Scale == 1 and f.Size.X.Offset == 0, "ribbon modes: the plate carries " .. name .. " along its whole width")
		end
		T.check(lines.BandTop and sameColor(lines.BandTop.BackgroundColor3, Sg.NavyTop) and lines.BandLip and sameColor(lines.BandLip.BackgroundColor3, Sg.NavyLip)
			and lines.BandPipeTop and sameColor(lines.BandPipeTop.BackgroundColor3, Sg.Brass) and lines.BandPipeLow and sameColor(lines.BandPipeLow.BackgroundColor3, Sg.Brass),
			"ribbon modes: ...the lit top, the darker lip and two brass pipings")
		local slot = plate:FindFirstChild("IconSlot")
		T.check(slot ~= nil and lines.BandPipeTop ~= nil and slot.ZIndex > lines.BandPipeTop.ZIndex and title.ZIndex > lines.BandPipeTop.ZIndex,
			"ribbon modes: the icon square and the title draw over the band's lines")
		-- the tails: behind the plate, past the frame, notched
		local plateX0 = plate.Position.X.Offset
		local plateX1 = 900 + plate.Position.X.Offset + plate.Size.X.Offset
		for _, side in ipairs({ "TailL", "TailR" }) do
			local tail = head:FindFirstChild(side)
			if T.check(tail ~= nil and tail.Visible and tail.ZIndex < plate.ZIndex and sameColor(tail.BackgroundColor3, Sg.NavyLip), "ribbon modes: " .. side .. " hangs behind the band") then
				local x0 = tail.Position.X.Scale * 900 + tail.Position.X.Offset
				local lo, hi = x0, x0 + tail.Size.X.Offset
				local notches = 0
				for _, n in ipairs(tail:GetChildren()) do
					lo, hi = math.min(lo, x0 + n.Position.X.Offset), math.max(hi, x0 + n.Position.X.Offset + n.Size.X.Offset)
					notches = notches + 1
				end
				if side == "TailL" then
					T.check(lo < plateX0 and hi > plateX0 and lo < -over, "ribbon modes: the left tail sticks out past the band's left end, beyond the frame", fmt("tail %d..%d, band from %d", lo, hi, plateX0))
				else
					T.check(hi > plateX1 and lo < plateX1 and hi > 900 + over, "ribbon modes: the right tail sticks out past the band's right end, beyond the frame", fmt("tail %d..%d, band to %d", lo, hi, plateX1))
				end
				T.check(notches >= 2, "ribbon modes: " .. side .. " has its stepped swallowtail notch")
			end
		end
		-- the title: no band or tails of its own; its underline sits on the plate's low piping
		local band, under = title:FindFirstChild("RibbonBand"), title:FindFirstChild("RibbonUnderline")
		T.check(band ~= nil and not band.Visible and not title:FindFirstChild("TailL").Visible and not title:FindFirstChild("TailR").Visible,
			"ribbon modes: the title's own band and tails are hidden (the plate is its band)")
		local pipeLow = lines.BandPipeLow
		T.check(under ~= nil and pipeLow ~= nil and under.Position.Y.Scale == 1 and pipeLow.Position.Y.Scale == 1
			and under.Position.Y.Offset + under.Size.Y.Offset == pipeLow.Position.Y.Offset and sameColor(under.BackgroundColor3, Sg.Gold),
			"ribbon modes: the gold underline sits on the plate's low piping", under and pipeLow and (tostring(under.Position) .. " / " .. tostring(pipeLow.Position)) or "")
		local steps = 0
		for _, d in ipairs(title:GetChildren()) do
			if d:GetAttribute("Ribbon") == "Step" and d.Visible then
				steps = steps + 1
			end
		end
		T.eq(steps, 3, "ribbon modes: ...and ends in its three steps (the box has room)")
		-- pulled in: inside the rim, no tails, the title and the icon where they were on the screen
		local function at(o)
			return o.Position.X.Offset + plate.Position.X.Offset
		end
		local titleAt, slotAt = at(title), at(slot)
		SK.HeaderOverhang(head, false)
		T.check(plate.Position.X.Offset == 6 and plate.Size.X.Offset == -12 and not head.TailL.Visible and not head.TailR.Visible,
			"ribbon modes: HeaderOverhang(false) keeps the band inside the rim and drops the tails", tostring(plate.Position) .. " " .. tostring(plate.Size))
		T.check(at(title) == titleAt and at(slot) == slotAt, "ribbon modes: ...the title and the icon stay where they were", fmt("title %d -> %d", titleAt, at(title)))
		SK.HeaderOverhang(head, true)
		T.check(plate.Position.X.Offset == -over and head.TailL.Visible and head.TailR.Visible and at(title) == titleAt, "ribbon modes: HeaderOverhang(true) puts them back")
		-- a header built without Ribbon keeps today's look: the plate inside the rim, the title's own ribbon
		local _, plain = SK.Header(win, { Title = "Credits", TitleSize = 34, Height = 64, Rim = 6 })
		local pt = plain:FindFirstChild("Title")
		T.check(plain.Position.X.Offset == 6 and plain:FindFirstChild("BandPipeLow") == nil and pt and pt:GetAttribute("RibbonBand") == nil and pt.RibbonBand.Visible,
			"ribbon modes: a header without Ribbon keeps its plate inside the rim and the title's own band")
		-- NoTails: the title's own band from its box's left edge, no tails
		local l = Theme.Label("Shop", "Title", { Size = 34 })
		l.Size = UDim2.fromOffset(420, 58)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l:SetAttribute("RibbonBand", "NoTails")
		l.Parent = win
		Theme.StyleTitle(l)
		T.check(l.RibbonBand.Visible and l.RibbonBand.Position.X.Offset == 0 and not l.TailL.Visible and not l.TailR.Visible,
			"ribbon modes: NoTails keeps the title's own band from its box's edge, without tails", tostring(l.RibbonBand.Position))
		l:SetAttribute("RibbonBand", nil)
		T.check(l.TailL.Visible and l.TailR.Visible and l.RibbonBand.Position.X.Offset > 0, "ribbon modes: ...and the tails come back when the attribute goes")
		gui:Destroy()
		K.flushErrors("theme_title_ribbon_modes")
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
		-- (sign/logo build) SmokeCommon.StrokeWalk with Theme.OutlineOnPlate: the Title role's ONE outline on a plate is the
		-- owner's written exception (T1); every other outlined text on a plate still fails
		local themeInst = Mock.GetPath(ROOTS.shared .. "/Theme")
		local okTheme, Theme = pcall(require, themeInst)
		local total, doubled, panelled = SmokeCommon.StrokeWalk(pg, okTheme and type(Theme) == "table" and Theme.OutlineOnPlate or nil)
		T.check(total > 0, "kitb stroke walk: the client run left text in PlayerGui", tostring(total))
		T.info(fmt("*kitb stroke walk: %d texts, %d with stroke + outline, %d outlined on an opaque panel", total, #doubled, #panelled))
		-- U6: a failure from now on (U1 reported these as a warning); tools/stroke_walk.py runs the same rule over the dumps of
		-- every render scenario
		T.check(#doubled == 0, fmt("kitb stroke walk: no text with both a classic stroke and an outline (%d)", #doubled), table.concat(doubled, "; ", 1, math.min(#doubled, 8)))
		T.check(#panelled == 0, fmt("kitb stroke walk: no outlined text on an opaque panel (%d)", #panelled), table.concat(panelled, "; ", 1, math.min(#panelled, 8)))
	end)

	-- U6 review: the contrast rule over every shown text with no outline in PlayerGui after the client run (SmokeCommon.Contrast:
	-- its colour against the fill painted under its glyphs, the worst gradient stop; 3:1 from 18 px, 4.5:1 below).
	-- tools/stroke_walk.py runs the same rule over the dumps of every render scenario
	S.kitb_text_contrast = guarded("kitb_text_contrast", function()
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(pg ~= nil, "kitb contrast: PlayerGui exists") then
			return
		end
		local bad, read, owed = SmokeCommon.Contrast.Walk(pg)
		T.info(fmt("*kitb contrast: %d texts read against their fill, %d below the rule, %d more in tools/fixtures/contrast_backlog.txt", read, #bad, owed))
		T.check(read > 0, "kitb contrast: the client run left text on a fill in PlayerGui", tostring(read))
		T.check(#bad == 0, fmt("kitb contrast: every text without an outline reads on its fill (3:1 from 18 px, 4.5:1 below) (%d not)", #bad),
			table.concat(bad, "; ", 1, math.min(#bad, 10)))
	end)

	-- U6 (fonts audit F9): kit B's casing rule over every text Theme stamped with a role in PlayerGui after the client run:
	-- a Button reads in sentence case (no all-capitals word of 4+ letters: "Leave", not "LEAVE"), a Tag / Title / Sign /
	-- Accent in capitals (Theme keeps those, so they fail in every family). Rich text tags are not text. A button in
	-- capitals fails in the ScreenGuis of the families U6 swept (CASING_SWEPT); elsewhere it is a warning with the count (U9 sweeps those windows; the SignKit planks of the main menu, Settings and the loading screen keep
	-- the capitals of the owner's approved U2-U5 boards until the owner rules on it).
	local CASING_SWEPT = { NimbusMenu = true, NimbusBattle = true, NimbusHud = true, NimbusIndex = true, NimbusNotify = true,
		NimbusDungeon = true, NimbusDungeonRun = true }
	S.kitb_casing_rule = guarded("kitb_casing_rule", function()
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(pg ~= nil, "kitb casing: PlayerGui exists") then
			return
		end
		local shouty, quiet, buttons, tags, later = {}, {}, 0, 0, {}
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				local role = d:GetAttribute("FontRole")
				local text = tostring(d.Text or ""):gsub("<[^>]->", "")
				local path = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
				local swept = CASING_SWEPT[path:match("^([^.]+)") or ""] == true
				if role == "Button" and text:find("%a") then
					buttons = buttons + 1
					for word in text:gmatch("%a+") do
						if #word >= 4 and word == word:upper() then
							local into = swept and shouty or later
							into[#into + 1] = path .. " \"" .. text .. "\""
							break
						end
					end
				elseif (role == "Tag" or role == "Title" or role == "Sign" or role == "Accent") and text:find("%a") then
					-- (Theme.SetRole keeps these in capitals, so a lower-case letter fails in every family)
					tags = tags + 1
					if text:find("%l") then
						quiet[#quiet + 1] = path .. " \"" .. text .. "\" (" .. role .. ")"
					end
				end
			end
		end
		table.sort(shouty)
		table.sort(quiet)
		T.info(fmt("*kitb casing: %d button texts, %d tag / title texts", buttons, tags))
		T.check(buttons > 0, "kitb casing: the client run left Button-role text in PlayerGui", tostring(buttons))
		T.check(#shouty == 0, fmt("kitb casing: buttons read in sentence case (%d in capitals)", #shouty), table.concat(shouty, "; ", 1, math.min(#shouty, 8)))
		T.check(#quiet == 0, fmt("kitb casing: tags, titles, signs and accents read in capitals (%d not)", #quiet), table.concat(quiet, "; ", 1, math.min(#quiet, 8)))
		if #later > 0 then
			table.sort(later)
			T.warn(fmt("kitb casing: %d text(s) outside the swept families break the casing rule (U9 sweeps them)", #later), table.concat(later, "; ", 1, math.min(#later, 8)))
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

	-- the board of the pitch: two ropes, the flat awning roof (sign/logo build: the B2 canopy, navy and cream), the navy
	-- header with the game's logo (L2 until the L1 picture is uploaded; the typed title stays off), the 6 px wood frame round
	-- the stone body; width min(0.5 W, 620 design px) on a wide screen and the screen less a 16 px gutter on each side on a
	-- portrait phone; the board sways like the title screen's (Config.MainMenu.Sway: its Swing turns +-Degrees, Period a
	-- full back-and-forth)
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
				T.check(roof ~= nil and face ~= nil and sameColor(face.BackgroundColor3, Sign.Canvas) and roof.Size.X.Scale == 0 and roof.Size.Y.Offset == 18,
					"loading board: the flat canopy roof (B2: a canvas face under navy stripes, 18 px, a fixed offset width) at " .. tag, roof and tostring(roof.Size) or "missing")
				local plate = head and head:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				T.check(plate ~= nil and sameColor(plate.BackgroundColor3, Sign.Navy), "loading board: the navy header plank at " .. tag)
				local logo = board:FindFirstChild("Logo", true)
				T.check(logo ~= nil and logo:GetAttribute("Logo") == "L2" and logo.Visible, "loading board: the header shows the logo (L2, the live stand-in) at " .. tag,
					logo and tostring(logo:GetAttribute("Logo")) or "missing")
				T.check(title == nil or title.Visible == false, "loading board: ...and the typed title is off at " .. tag)
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
				local W = LoadingH.shared("Config").MainMenu.Sway
				local goal = swingTween and Mock.TweenGoals(swingTween).Rotation
				local info = swingTween and swingTween.TweenInfo
				T.check(math.abs(swing.Rotation) <= W.Degrees + 0.01 and goal ~= nil and math.abs(math.abs(goal) - W.Degrees) < 1e-6 and math.abs(goal - swing.Rotation) > 2 * W.Degrees - 0.1,
					"loading board: the board sways from -" .. W.Degrees .. " to +" .. W.Degrees .. " degrees (as the title screen's) at " .. tag, fmt("%.2f -> %s", swing.Rotation, tostring(goal)))
				T.check(info ~= nil and info.RepeatCount < 0 and info.Reverses == true and info.EasingStyle == Enum.EasingStyle.Sine and math.abs(info.Time - W.Period / 2) < 1e-6,
					"loading board: ...endlessly, back and forth, Sine, Sway.Period a full swing")
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

	-- no neon: no UIStroke, no glow, no classic text stroke, no gradient but the sky's, none of the old neon colours.
	-- (sign/logo build) Except the logo's letters: the owner's L2 (2026-11-13) gives each letter ONE brown outline and a
	-- three-band fill (Title role, the U6 Title exception); the typed title under it is off
	S.loading_no_neon_no_stroke = guarded("loading_no_neon_no_stroke", function()
		local NEON = { "#40E2EC", "#B068FF", "#3C3296", "#BE6EC8", "#96F6FF" }
		local ok, err = pcall(function()
			local gui = LoadingH.run({ Wait = 6.6 })
			if not T.check(gui ~= nil, "loading neon: (setup) the screen is built") then
				return
			end
			-- shown: no hidden object between it and the gui; the logo's letters are the one allowed outline
			local function exempt(d)
				local o = d.Parent
				while o and o ~= gui do
					if (o:IsA("GuiObject") and not o.Visible) or o:GetAttribute("Logo") ~= nil then
						return true
					end
					o = o.Parent
				end
				return false
			end
			local strokes, grads, classic, neon = {}, {}, {}, {}
			for _, d in ipairs(gui:GetDescendants()) do
				if exempt(d) then
					-- the logo's letters (or something not on screen)
				elseif d:IsA("UIStroke") then
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
			-- (sign/logo build) the roof is the B2 canopy from the first frame: navy, its darker edge and lip (no pink flash
			-- before SignKit stripes it)
			local roof = board:FindFirstChild("Roof")
			want(roof, "NavyLip", "roof edge")
			want(roof and roof:FindFirstChild("Face"), "NavyLight", "roof face")
			want(roof and roof:FindFirstChild("Face") and roof.Face:FindFirstChild("Lip"), "NavyLip", "roof lip")
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
			local logo0 = gui:FindFirstChild("Logo", true)
			local clouds = gui:FindFirstChild("Clouds", true)
			T.check(logo0 ~= nil and logo0:GetAttribute("Logo") == "L2" and clouds ~= nil and clouds.Visible,
				"loading images: ids 0 -> the live L2 logo (the L1 picture's stand-in) and the cloud sky", logo0 and tostring(logo0:GetAttribute("Logo")) or "no logo")
			LoadingH.cleanup()
			ids[keys.Logo], ids[keys.Backdrop], ids[keys.Mascot] = 101, 202, 303
			local g2 = LoadingH.run()
			if not T.check(g2 ~= nil, "loading images: (setup) the screen is built with the ids set") then
				return
			end
			local logo = g2:FindFirstChild("Logo", true)
			local back = g2:FindFirstChild("Backdrop", true)
			local mascot = g2:FindFirstChild("Mascot", true)
			T.check(logo ~= nil and logo:IsA("ImageLabel") and logo.Image == "rbxassetid://101" and logo:GetAttribute("Logo") == "L1",
				"loading images: the logo id -> the L1 Logo image in the header", logo and tostring(logo.Image) or "missing")
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
				T.check(roof ~= nil and face ~= nil and sameColor(face.BackgroundColor3, Sign.Canvas) and roof.Size.X.Scale == 0,
					"menu board: the flat canopy roof (B2: a canvas face under navy stripes, a fixed offset width) at " .. tag, roof and tostring(roof.Size) or "missing")
				local head = (kinds.Header or {})[1]
				local plate = head and head:FindFirstChild("Plate")
				local title = plate and plate:FindFirstChild("Title")
				T.check(plate ~= nil and sameColor(plate.BackgroundColor3, Sign.Navy), "menu board: the navy header plank at " .. tag)
				-- (sign/logo build) the header shows the game's logo (L2 until the L1 picture is uploaded); the typed
				-- Config.MainMenu.Header stays under it, off
				local logo = MenuH.find(board, "Logo")
				T.check(logo ~= nil and logo:GetAttribute("Logo") == "L2" and logo.Visible, "menu board: the header shows the logo (L2) at " .. tag,
					logo and tostring(logo:GetAttribute("Logo")) or "missing")
				T.check(title ~= nil and title.Text == "NIMBUS CLIMB" and title.Visible == false, "menu board: ...the typed NIMBUS CLIMB is under it, off, at " .. tag,
					title and (title.Text .. " " .. tostring(title.Visible)) or "missing")
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
					if designedLook(d) then
						-- the T1 ribbon / the logo's letters (the owner's picks)
					elseif d:IsA("UIGradient") or d:IsA("UICorner") then
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

	-- the entrance: the board drops in on its ropes, the buttons pop 60 ms apart; PLAY pulls the board up (0.3 s, Quad In)
	-- while the camera tweens to the spawn view (0.8 s, Sine InOut) and only then turns Custom. (sign build) The owner's
	-- "Rope drop" replaced U4's 0.45 s Back Out drop and 2 degree / 1.2 s Elastic settle: the fall is
	-- Config.MainMenu.Entrance.Drop (Quad In), the swing starts from level to Entrance.Swing[1], and at rest the board sways
	-- within Sway.Degrees (smoke_kitb_sign.lua pins the rest of the new motion)
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
			local E = LoadingH.shared("Config").MainMenu.Entrance
			local drop = tweensOf(swing, "Position")[1]
			local info = drop and drop.TweenInfo
			T.check(info ~= nil and math.abs(info.Time - E.Drop) < 1e-6 and info.EasingStyle == Enum.EasingStyle.Quad and info.EasingDirection == Enum.EasingDirection.In,
				"menu motion: the board drops in on its ropes (Position, Entrance.Drop, Quad In)", info and fmt("%.2f %s %s", info.Time, tostring(info.EasingStyle), tostring(info.EasingDirection)) or "no tween")
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
			LKC.advance(E.Drop + 0.02)
			local settle = tweensOf(swing, "Rotation")[1]
			local sInfo = settle and settle.TweenInfo
			T.check(sInfo ~= nil and math.abs(sInfo.Time - E.SwingTime) < 1e-6 and math.abs(swing.Rotation) < 1e-6 and Mock.TweenGoals(settle).Rotation == E.Swing[1],
				"menu motion: then the snap swings it from level to Entrance.Swing[1]", sInfo and fmt("%.2f deg, %.2f s", swing.Rotation, sInfo.Time) or "no tween")
			LKC.advance(1.4)
			local sway = LoadingH.shared("Config").MainMenu.Sway.Degrees
			T.check(math.abs(swing.Rotation) <= sway + 1e-6 and rest ~= nil and swing.Position.Y.Offset == rest.Y.Offset and swing.Position.X.Offset == rest.X.Offset,
				"menu motion: at rest after the entrance (swaying within Sway.Degrees)", fmt("%.2f deg", swing.Rotation))
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
	-- board waits lifted with its buttons at pop scale 0 and no tween runs; the entrance starts when Done arrives. (sign
	-- build) The owner's pick: once the loading screen has FADED after its Done (smoke_kitb_sign.lua
	-- menu_entrance_after_loading pins the fade)
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
			-- the loading screen finishes: the entrance starts once it has faded away (0.4 s)
			lg:SetAttribute("Done", true)
			LKC.advance(0.5)
			local drop = tweensOf(swing, "Position")[1]
			local goal = drop and Mock.TweenGoals(drop).Position
			T.check(goal ~= nil and goal.Y.Offset == rest.Y.Offset and goal.X.Offset == rest.X.Offset, "menu wait: at Done the board drops in to its rest place")
			for _, b in ipairs(planks) do
				local pop = b:FindFirstChild("Pop")
				T.check(pop ~= nil and #tweensOf(pop, "Scale") == 1, "menu wait: at Done " .. b.Name .. " pops in")
			end
			LKC.advance(2)
			T.check(math.abs(swing.Rotation) <= 1.5 and swing.Position.Y.Offset == rest.Y.Offset, "menu wait: at rest after the entrance")
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
			if designedLook(d) then
				-- the header title's T1 ribbon (the owner's pick)
			elseif d:IsA("UIGradient") or d:IsA("UICorner") then
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
			T.check(t:GetAttribute("FontRole") == "Title" and t.Font == Theme.Fonts.Title and sameColor(t.TextColor3, Sign.Gold) and t:GetAttribute("TitleLook") == "Ribbon",
				"u5 window: " .. title .. " in FredokaOne gold (Title role, through Theme.StyleTitle)",
				tostring(t.Font) .. " " .. hex(t.TextColor3) .. " " .. tostring(t:GetAttribute("TitleLook")))
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

	-- (T0 review) every window title goes through Theme.StyleTitle, seen at run time: the walk opens the windows that build
	-- late (Training with its confirm, Fusion, the pet picker, the Shop, the Home window with its hero cards and Prestige
	-- confirm, the loss screen, a battle's result card, the hatch stage, the garden recall dialog), then fails on any
	-- Title-role TextLabel named Title / TitleText / Headline in PlayerGui whose TitleLook is not "Ribbon" (a window title: the owner's T1)
	-- or a kind of Theme.TitleExempt (a heading that skips the title look on purpose, each kind with its reason). Each
	-- expected window title must be found as "Ribbon", so a window that stops building fails here instead of passing absent.
	S.kitb_titles_stamped = guarded("kitb_titles_stamped", function()
		local Theme = LoadingH.shared("Theme")
		local PC = LoadingH.shared("PetCatalog")
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(Theme and type(Theme.TitleExempt) == "table" and pg, "kitb titles walk: Theme.TitleExempt and PlayerGui exist") then
			return
		end
		local function client(path)
			local inst = Mock.GetPath(ROOTS.client .. "/" .. path)
			local ok, mod = false, nil
			if inst then
				ok, mod = pcall(require, inst)
			end
			return ok and type(mod) == "table" and mod or nil
		end
		local function try(what, fn)
			local ok, err = pcall(fn)
			T.check(ok, "kitb titles walk: " .. what .. " opens", tostring(err))
			LKC.advance(0.3)
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LKC.advance(0.1)
		local names = { Title = true, TitleText = true, Headline = true }
		local found, bad = {}, {}
		-- (sign/logo review) the ribbon is a window's NAME: never on a heading inside a scrolling body (a Shop card's
		-- SECRET ROULETTE, Gems, XP Potion), and the Shop holds one ribbon (its header's "Shop")
		local scrolled, shopRibbons = {}, {}
		local function walk()
			for _, d in ipairs(pg:GetDescendants()) do
				if d:IsA("TextLabel") and d:GetAttribute("TitleLook") == "Ribbon" then
					local path = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
					if d:FindFirstAncestorWhichIsA("ScrollingFrame") then
						scrolled[path] = true
					end
					if path:find("^NimbusShop%.") then
						shopRibbons[path] = true
					end
				end
				if d:IsA("TextLabel") and names[d.Name] and d:GetAttribute("FontRole") == "Title" then
					local path = d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
					local look = d:GetAttribute("TitleLook")
					found[path] = look
					if look ~= "Ribbon" and (look == nil or Theme.TitleExempt[look] == nil) then
						bad[path] = tostring(look)
					end
				end
			end
		end
		walk() -- what the boot built (the Care confirm, the dungeon's end card, the HUD panels, the menu windows' bars)
		local Menu = client("Controllers/MenuController")
		try("the Home window", function()
			Menu.Open("Home")
		end)
		walk()
		try("Training", function()
			client("Controllers/TrainController").Open({})
		end)
		walk()
		try("the pet picker", function()
			client("UI/PetPicker").Open({ Context = "Train", Title = "Pick a pet to train", OnPick = function() end, OnClose = function() end })
		end)
		walk()
		pcall(client("UI/PetPicker").Close)
		pcall(client("Controllers/TrainController").Close)
		try("Fusion", function()
			client("Controllers/FusionController").Open("Upgrade", {})
		end)
		walk()
		pcall(client("Controllers/FusionController").Close)
		try("the Shop", function()
			client("Controllers/ShopController").Open({ Tab = "Eggs" })
		end)
		walk()
		pcall(client("Controllers/ShopController").Close)
		try("the loss screen", function()
			client("Controllers/LossScreen").Show({ Mode = "Ring", Title = "RUN OVER", Sub = "The champion won round 2", Pets = {} })
		end)
		walk()
		pcall(client("Controllers/LossScreen").Hide)
		try("a battle's result card", function()
			local BC = client("Controllers/BattleController")
			local id = "kitb_titles"
			game:GetService("Players").LocalPlayer:SetAttribute(LoadingH.shared("Config").Attr.InBattle, id)
			BC.HandleState("Start", { BattleId = id, Mode = "Ring", Side = 1, Spectator = false, T = 0, Units = {}, Ring = { Round = 1, Best = 0, Start = 1 },
				Zone = { CFrame = CFrame.new(0, 400, 0), X = 40, Z = 40 } }, id)
			LKC.advance(0.2)
			BC.HandleState("End", { BattleId = id, Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "KO",
				Rewards = { Won = true, Round = 1, Cash = 10, Xp = 5, Start = 1 } }, id)
		end)
		walk()
		pcall(function()
			client("Controllers/BattleController").HideResult()
			game:GetService("Players").LocalPlayer:SetAttribute(LoadingH.shared("Config").Attr.InBattle, nil)
		end)
		try("the hatch stage", function()
			local def = PC.RarityPool("Cloud", "Common")[1]
			local all = {}
			for _, d in ipairs(PC.PossiblePets("Cloud")) do
				all[#all + 1] = d.Id
			end
			local strip = {}
			for i = 1, 40 do
				strip[i] = all[((i * 7) % #all) + 1]
			end
			strip[34] = def.Id
			local pull = { PetId = def.Id, Key = def.Id, Rarity = def.Rarity, IsNew = true, NewDiscovery = true, Count = 1, PoolSize = 1, Strip = strip }
			client("UI/EggStage").Show({ Ok = true, RouletteId = "Cloud", Currency = "Tokens", Spins = 1, UnitPrice = 50, Price = 50, Pulls = { pull }, Tokens = 5000, Gems = 5000,
				PetId = def.Id, Key = def.Id, IsNew = true, NewDiscovery = true, Count = 1, Strip = strip })
		end)
		walk()
		try("the garden recall dialog", function()
			client("UI/PetBits").askRecall(pg:FindFirstChild("NimbusMenu") or pg, "kitb_pet", { To = "Team", Preset = 1, Keys = {} }, nil, nil, function() end)
		end)
		walk()
		pcall(client("UI/PetBits").closeRecall)
		-- the window titles this walk must have seen as "Ribbon" (a Lua pattern on the path inside PlayerGui each); (U9-5, the
		-- owner's ruling 2026-11-14: the T1 ribbon is for window titles only) a third field names another look: the Care
		-- family's dialogs wear the plain kit B "Section" title
		local expected = {
			{ "the Care confirm", "^NimbusCare%.CareConfirm%.Box%.Title$", "Section" },
			{ "the dungeon's end card", "^NimbusDungeonRun%.EndCard%..-%.Title$" },
			{ "the Home window's bar", "%.Window_Home%..-%.TitleBar%.Title$" },
			{ "the Go home hero card", "%.Hero%.GoHome%..-%.Title$" },
			{ "the Prestige confirm", "%.PrestigeConfirm%.Box%.Title$" },
			{ "the Training window", "^NimbusTrain%..-Header%.Title$" },
			{ "the Training confirm", "^NimbusTrain%..-%.Box%.Title$", "Section" },
			{ "the pet picker", "^NimbusPetPicker%..-%.Title$" },
			{ "the Fusion window", "^NimbusFusion%..-%.Title$" },
			{ "the Shop", "^NimbusShop%..-%.Title$" },
			{ "the Sky Trove", "^NimbusTrove%..-%.TitleText$" },
			{ "the loss card", "^NimbusLoss%.LossCard%..-%.Title$", "Section" }, -- (U9-6) pop-up cards wear the plain kit B title
			{ "the battle result card", "%.ResultCard%..-%.Title$", "Section" },
			{ "the hatch stage", "^NimbusHatch%..-%.Title$" },
			{ "the garden recall dialog", "%.GardenRecall%.Box%.Title$" },
			{ "the party panel", "^NimbusHud%..-%.PartyPanel%..-%.Title$" },
		}
		local missing = {}
		for _, e in ipairs(expected) do
			local hit = false
			for path, look in pairs(found) do
				if look == (e[3] or "Ribbon") and path:find(e[2]) then
					hit = true
					break
				end
			end
			if not hit then
				missing[#missing + 1] = e[1]
			end
		end
		local badList, seen = {}, {}
		for path, look in pairs(bad) do
			badList[#badList + 1] = path .. " (" .. look .. ")"
		end
		for path, look in pairs(found) do
			seen[#seen + 1] = path .. "=" .. tostring(look)
		end
		table.sort(badList)
		table.sort(seen)
		T.check(#missing == 0, "kitb titles walk: every expected window title is built and stamped Ribbon", table.concat(missing, ", ") .. " | seen: " .. table.concat(seen, "; "))
		T.check(#badList == 0, "kitb titles walk: no Title-role title without the TitleLook stamp (Plain, or a Theme.TitleExempt kind)", table.concat(badList, "; "))
		local inScroll, shopList = {}, {}
		for path in pairs(scrolled) do
			inScroll[#inScroll + 1] = path
		end
		for path in pairs(shopRibbons) do
			shopList[#shopList + 1] = path
		end
		table.sort(inScroll)
		table.sort(shopList)
		T.check(#inScroll == 0, "kitb titles walk: no ribbon title inside a scrolling body (a card or section heading passes \"Section\")", table.concat(inScroll, "; "))
		T.check(#shopList == 1 and shopList[1]:find("%.Header%.Title$") ~= nil, "kitb titles walk: the Shop holds one ribbon, its header's title", table.concat(shopList, "; "))
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.2)
		LKC.flushErrors("kitb_titles_stamped")
	end)

	------------------------------------------------------------------------------------------------
	-- U7a (icons: tiles and currency; finding 7, rejects audit 5): the icon ids draw PixelIcons, the Cloud Token is its coin
	local U7 = {}
	function U7.client(path)
		local inst = Mock.GetPath(ROOTS.client .. "/" .. path)
		local ok, mod = false, nil
		if inst then
			ok, mod = pcall(require, inst)
		end
		return ok and type(mod) == "table" and mod or nil
	end
	function U7.try(what, fn)
		local ok, err = pcall(fn)
		T.check(ok, "u7a walk: " .. what .. " opens", tostring(err))
		LKC.advance(0.4)
	end
	function U7.path(d)
		return (d:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", ""))
	end
	-- the windows U7a reworked, opened one after another; `look()` runs after each (and once before, for the boot's GUI)
	function U7.openAll(look)
		local Config = LoadingH.shared("Config")
		local PC = LoadingH.shared("PetCatalog")
		local Menu = U7.client("Controllers/MenuController")
		look()
		for _, id in ipairs({ "Pets", "Index", "Stats" }) do
			U7.try("the " .. id .. " window", function()
				Menu.Open(id)
			end)
			look()
		end
		pcall(Menu.Close)
		for _, tab in ipairs({ "Eggs", "Gems", "Packs", "Passes", "Boosts" }) do
			U7.try("the Shop on " .. tab, function()
				U7.client("Controllers/ShopController").Open({ Tab = tab })
			end)
			look()
		end
		pcall(U7.client("Controllers/ShopController").Close)
		U7.try("the Gifts window", function()
			U7.client("Controllers/DailyController").Open({})
		end)
		look()
		pcall(U7.client("Controllers/DailyController").Close)
		U7.try("Fusion", function()
			U7.client("Controllers/FusionController").Open("Upgrade", {})
		end)
		look()
		pcall(U7.client("Controllers/FusionController").Close)
		U7.try("a token toast", function()
			LKC.toClient("Notify", "+25 cloud tokens", "token", 8)
		end)
		look()
		U7.try("a match result", function()
			game:GetService("Players").LocalPlayer:SetAttribute(Config.Attr.InMatch, true)
			LKC.toClient("MatchResult", {
				Won = true, Reason = "victory", Seconds = 187, MatchTokens = 11, Bonus = 10, DifficultyId = "Easy", DifficultyName = "Easy",
				Stars = 1, TotalTokens = 24,
				Members = {
					{ Name = game:GetService("Players").LocalPlayer.Name, MatchTokens = 11, Finished = true, Downed = false },
					{ Name = "Buddy", MatchTokens = 6, Finished = true, Downed = false },
				},
			})
			LKC.advance(1.5)
		end)
		look()
		pcall(function()
			game:GetService("Players").LocalPlayer:SetAttribute(Config.Attr.InMatch, nil)
		end)
		U7.try("the hatch stage", function()
			local def = PC.RarityPool("Cloud", "Common")[1]
			local all = {}
			for _, d in ipairs(PC.PossiblePets("Cloud")) do
				all[#all + 1] = d.Id
			end
			local strip = {}
			for i = 1, 40 do
				strip[i] = all[((i * 7) % #all) + 1]
			end
			strip[34] = def.Id
			local pull = { PetId = def.Id, Key = def.Id, Rarity = def.Rarity, IsNew = true, NewDiscovery = true, Count = 1, PoolSize = 1, Strip = strip }
			U7.client("UI/EggStage").Show({ Ok = true, RouletteId = "Cloud", Currency = "Tokens", Spins = 1, UnitPrice = 50, Price = 50, Pulls = { pull }, Tokens = 5000, Gems = 5000,
				PetId = def.Id, Key = def.Id, IsNew = true, NewDiscovery = true, Count = 1, Strip = strip })
			LKC.advance(8)
		end)
		look()
	end
	-- (U7b) the windows of U7b's glyph tables, opened the way the server opens them (OpenPanel): the Arena on each tab, the
	-- Champion Ring, the Dungeon, the Training Place, the Home window, the Food Machine and the garden picker, the Obby
	-- picker; `look()` runs after each
	function U7.openU7b(look)
		local panels = {
			{ "Arena", { Tab = "Duels" } }, { "Arena", { Tab = "Raid" } }, { "Arena", { Tab = "Leaderboard" } }, { "Ring", {} },
			{ "Dungeon", {} }, { "Train", {} }, { "Home", {} }, { "Pets", { Tab = "Pets", Action = "Feed" } },
			{ "Pets", { Action = "Garden", Slot = 3 } }, { "Obby", {} },
		}
		for _, p in ipairs(panels) do
			U7.try("the " .. p[1] .. " panel " .. tostring(p[2].Tab or p[2].Action or ""), function()
				LKC.toClient("OpenPanel", p[1], p[2])
				LKC.advance(1)
			end)
			look()
			pcall(function()
				LKC.toClient("ClosePanel", p[1])
			end)
			pcall(U7.client("Controllers/MenuController").Close)
			LKC.advance(0.3)
		end
	end

	-- (U9-5) the Care family, opened the way the game opens it: the Training Place, the Food Machine and the garden picker
	-- (OpenPanel), the Fusion Machine on both tabs, and the shared pet picker over the window that opens it (Train's
	-- Change, Fusion's slots). U9.FAMILY: { view, the ScreenGui that shows it }
	local U9 = {}
	U9.FAMILY = {
		{ "train", "NimbusTrain" }, { "feed", "NimbusCare" }, { "garden", "NimbusCare" }, { "fusion:upgrade", "NimbusFusion" },
		{ "fusion:mix", "NimbusFusion" }, { "picker:train", "NimbusPetPicker" }, { "picker:upgrade", "NimbusPetPicker" },
		{ "picker:mix", "NimbusPetPicker" },
	}
	function U9.close()
		pcall(U7.client("UI/PetPicker").Close)
		pcall(U7.client("Controllers/FusionController").Close)
		pcall(U7.client("Controllers/TrainController").Close)
		pcall(U7.client("Controllers/CareController").Close)
		pcall(U7.client("Controllers/MenuController").Close)
		LKC.advance(0.5)
	end
	-- the view's window shows: its ScreenGui enabled with a shown window frame in it
	function U9.showing(gui)
		if not gui or gui.Enabled == false then
			return false
		end
		for _, c in ipairs(gui:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible and c.Name ~= "Shade" then
				return true
			end
		end
		return false
	end
	function U9.open(view)
		local FC = U7.client("Controllers/FusionController")
		local PP = U7.client("UI/PetPicker")
		local base, sub = tostring(view):match("^([^:]+):?(.*)$")
		if base == "train" or (base == "picker" and sub == "train") then
			LKC.toClient("OpenPanel", "Train", {})
		elseif base == "feed" then
			LKC.toClient("OpenPanel", "Pets", { Tab = "Pets", Action = "Feed" })
		elseif base == "garden" then
			LKC.toClient("OpenPanel", "Pets", { Action = "Garden", Slot = 3 })
		elseif base == "fusion" or base == "picker" then
			FC.Open((sub == "mix") and "Mix" or "Upgrade", {})
		end
		LKC.advance(1)
		if base == "picker" then
			if sub == "train" then
				PP.Open({ Context = "Train", Title = "Pick a pet to train" })
			elseif sub == "upgrade" then
				PP.Open({ Context = "Upgrade", Title = "Pick a pet to upgrade" })
			else
				PP.Open({ Context = "Mix", Title = "Pick the Style pet" })
			end
			LKC.advance(1)
		end
	end

	-- (U9-6) the battle family: the battle HUD (NimbusBattle) in a dungeon room with a mini-boss (the fighter card, the
	-- helpers, the enemy list, the top card with the boss bar and pills, the commands, Cheer up!), a boss raid (the raid's
	-- boss bar, Retreat, LEAVE), a Champion Ring round (LEAVE, the pay pills), the ring's next-round card, the run's result
	-- card, and the loss screen (NimbusLoss). The fights come from smoke_p5_battleclient's driver (_G.P5BattleH: a real
	-- BattleSim sent the way BattleService sends it). U96.FAMILY: { view, the ScreenGui that shows it }
	local U96 = {}
	U96.FAMILY = {
		{ "battle:dungeon", "NimbusBattle" }, { "battle:raid", "NimbusBattle" }, { "battle:ring", "NimbusBattle" },
		{ "battle:next", "NimbusBattle" }, { "battle:result", "NimbusBattle" }, { "loss", "NimbusLoss" },
	}
	-- the emoji rule over PlayerGui (tools/stroke_walk.py --emoji runs it over the dump of every render scenario): after the
	-- client run and with each window U7a reworked open in turn (the menu's Pets / Index / Stats, the Shop on every tab,
	-- the Gifts window, Fusion, a token toast, a match result, the hatch stage), no shown text carries an emoji or
	-- pictographic symbol code point (SmokeCommon.Emoji). The texts in tools/fixtures/emoji_backlog.txt (U7b's glyph
	-- tables) are counted, not failed; U7b empties that list.
	S.kitb_no_emoji_ui = guarded("kitb_no_emoji_ui", function()
		local Emoji = SmokeCommon.Emoji
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(Emoji ~= nil and pg ~= nil, "kitb emoji walk: SmokeCommon.Emoji and PlayerGui exist") then
			return
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LKC.advance(0.1)
		local hits, owed, walks = {}, {}, 0
		local function walk()
			walks = walks + 1
			Emoji.Walk(pg, hits, owed)
		end
		U7.openAll(walk)
		U7.openU7b(walk) -- (U7b) and the windows of the glyph tables U7b redrew; the backlog is empty
		for _, f in ipairs(U9.FAMILY) do -- (U9-5) and every view of the Care family (Fusion's Mix tab, the pet picker)
			U7.try("the care family " .. f[1], function()
				U9.open(f[1])
			end)
			walk()
			U9.close()
		end
		for _, f in ipairs(U96.FAMILY) do -- (U9-6) and every view of the battle family (the HUD, its cards, the loss screen)
			U7.try("the battle family " .. f[1], function()
				U96.open(f[1])
			end)
			walk()
			U96.close()
		end
		local list, n = {}, 0
		for path, cps in pairs(hits) do
			list[#list + 1] = path .. " " .. cps
		end
		for _ in pairs(owed) do
			n = n + 1
		end
		table.sort(list)
		T.info(fmt("*kitb emoji walk: %d walks, %d texts with an emoji outside the backlog, %d in tools/fixtures/emoji_backlog.txt", walks, #list, n))
		T.check(#list == 0, fmt("kitb emoji walk: no shown text carries an emoji code point (%d)", #list), table.concat(list, "; ", 1, math.min(#list, 10)))
		local backlog = SmokeCommon.Contrast.Backlog(Emoji.BACKLOG)
		T.check(#backlog == 0 and n == 0, "kitb emoji walk: U7b emptied tools/fixtures/emoji_backlog.txt (zero allowed)", #backlog .. " line(s), " .. n .. " text(s) on them")
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.2)
		LKC.flushErrors("kitb_no_emoji_ui")
	end)

	-- (U7b review) the incoming-challenge side card (K.SIDE_W 340 px) at five-digit trophies and power: the trophies (the
	-- trophy icon), the power (the sword) and the countdown (the hourglass, in its own right-hand label) each sit inside
	-- the card's body and clear of each other, so the clock, the one live value, is never cut or spilled
	S.arena_side_invite_fits = guarded("arena_side_invite_fits", function()
		local AC = U7.client("Controllers/ArenaController")
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(AC and pg, "arena side invite: ArenaController and PlayerGui") then
			return
		end
		local IconOn = SmokeCommon.IconOn
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		pcall(AC.Close)
		pcall(U7.client("Controllers/MenuController").Close)
		LKC.advance(0.3)
		LKC.toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 },
			Invites = { { FromUserId = 501, FromName = "StormChaser", Trophies = 12345, Power = 98765, ExpiresIn = 28 } } })
		LKC.advance(0.6)
		local side = pg:FindFirstChild("NimbusArenaSide")
		local card = side and side:FindFirstChild("Invite1", true)
		local body = card and card:FindFirstChild("Body")
		local info = body and body:FindFirstChild("Info")
		if T.check(card and body and info and LKC.isShown(card), "arena side invite: the card shows with its Info line") then
			local sc = card.AbsoluteSize.X / 340
			local bx0, bx1 = body.AbsolutePosition.X, body.AbsolutePosition.X + body.AbsoluteSize.X
			-- the screen span of a label's glyphs (its alignment in its padded box) and of its Lead icon
			local function span(label)
				local pad = label:FindFirstChildOfClass("UIPadding")
				local x0 = label.AbsolutePosition.X + (pad and pad.PaddingLeft.Offset or 0) * sc
				local x1 = label.AbsolutePosition.X + label.AbsoluteSize.X - (pad and pad.PaddingRight.Offset or 0) * sc
				local tw = label.TextBounds.X
				local a = label.TextXAlignment
				local t0 = (a == Enum.TextXAlignment.Left and x0) or (a == Enum.TextXAlignment.Right and x1 - tw) or ((x0 + x1 - tw) / 2)
				local lo, hi = t0, t0 + tw
				local box = label:FindFirstChild("LeadIcon")
				if box then
					lo = math.min(lo, box.AbsolutePosition.X)
					hi = math.max(hi, box.AbsolutePosition.X + box.AbsoluteSize.X)
				end
				return lo, hi
			end
			local trophies, power, clock = info:FindFirstChild("Trophies", true), info:FindFirstChild("Power", true), info:FindFirstChild("Clock", true)
			T.check(trophies and power and clock, "arena side invite: the Info line holds Trophies, Power and Clock labels",
				fmt("%s '%s'", info.ClassName, tostring(info:IsA("TextLabel") and info.Text or "")))
			if trophies and power and clock then
				T.check(trophies.Text == "12,345" and IconOn(trophies, "Lead") == "trophy" and power.Text == "98,765" and IconOn(power, "Lead") == "sword"
					and tostring(clock.Text):match("^%d+:%d%d$") and IconOn(clock, "Lead") == "hourglass",
					"arena side invite: trophies (trophy icon), power (sword icon) and the clock (hourglass icon) as values",
					fmt("'%s' %s, '%s' %s, '%s' %s", trophies.Text, tostring(IconOn(trophies, "Lead")), power.Text, tostring(IconOn(power, "Lead")), clock.Text, tostring(IconOn(clock, "Lead"))))
				local spans, out = {}, {}
				for _, l in ipairs({ trophies, power, clock }) do
					local lo, hi = span(l)
					spans[#spans + 1] = { l.Name, lo, hi }
					if lo < bx0 - 0.5 or hi > bx1 + 0.5 then
						out[#out + 1] = fmt("%s %.0f..%.0f", l.Name, lo, hi)
					end
				end
				T.check(#out == 0, "arena side invite: every value and icon sits inside the card body", fmt("body %.0f..%.0f; %s", bx0, bx1, table.concat(out, ", ")))
				T.check(spans[1][3] <= spans[2][2] + 0.5 and spans[2][3] <= spans[3][2] + 0.5, "arena side invite: trophies, power and clock never overlap",
					fmt("%.0f..%.0f, %.0f..%.0f, %.0f..%.0f", spans[1][2], spans[1][3], spans[2][2], spans[2][3], spans[3][2], spans[3][3]))
			else
				-- the line as one label: it must fit the body at least (it did not: the clock spilled)
				local lo, hi = span(info)
				T.check(hi <= bx1 + 0.5, "arena side invite: the Info line fits the card body", fmt("text %.0f..%.0f, body %.0f..%.0f", lo, hi, bx0, bx1))
			end
		end
		LKC.toClient("BattleState", "Lobby", { Queue = { Queued = false, Waiting = 0 }, Invites = {} })
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.3)
		LKC.flushErrors("arena_side_invite_fits")
	end)

	-- the Cloud Token is its PixelIcon coin wherever the game shows the currency: Theme.Currency names the icons (no emoji
	-- glyph left in any currency), Config.Icons fills every icon id from PixelIcon, NeonKit.Icon("Tokens") draws the coin
	-- (and follows the colour / fade a caller sets on it), PixelIcon.Lead puts the coin before an amount, and at run time
	-- each token surface holds a "token" PixelIcon and no cloud glyph: the HUD coin and title card, the match HUD line,
	-- the Shop's balance, an egg card's price and the Gems tab's token piles, the Fusion chip, the token toast, the Stats
	-- tiles, the Index reward, the match result's rows and the hatch stage's Spin again chip
	S.token_icon_everywhere = guarded("token_icon_everywhere", function()
		local Theme = LoadingH.shared("Theme")
		local Config = LoadingH.shared("Config")
		local PixelIcon = LoadingH.shared("PixelIcon")
		local NK = U7.client("UI/NeonKit")
		local Emoji = SmokeCommon.Emoji
		if not T.check(Theme and Config and PixelIcon and NK and Emoji, "token icon: Theme, Config, PixelIcon, NeonKit and SmokeCommon.Emoji load") then
			return
		end
		-- the data
		local cur = Theme.Currency or {}
		T.check(cur.Tokens and cur.Tokens.Icon == "token" and PixelIcon.Bitmaps.token ~= nil, "token icon: Theme.Currency.Tokens.Icon = \"token\" (the PixelIcon coin)", tostring(cur.Tokens and cur.Tokens.Icon))
		T.check(cur.Cash and cur.Cash.Icon == "note" and cur.Gems and cur.Gems.Icon == "Gems", "token icon: Cash draws the note, Gems the cut gem (Icon = \"Gems\")")
		local glyphs = {}
		for id, c in pairs(cur) do
			for k, v in pairs(c) do
				if type(v) == "string" and #Emoji.Find(v) > 0 then
					glyphs[#glyphs + 1] = id .. "." .. k
				end
			end
		end
		T.check(#glyphs == 0, "token icon: no emoji glyph left in Theme.Currency", table.concat(glyphs, ", "))
		local ids = { "Pets", "Items", "Inventory", "Team", "Index", "Shop", "Home", "Spot", "Stats", "Settings", "Travel", "Obby", "Dungeon",
			"Ring", "Arena", "Altar", "Care", "Berries", "Fusion", "Battle", "Cash", "Tokens", "Lock", "Play", "Store", "Packs", "Passes",
			"Boosts", "Currency", "Roulettes", "Eggs", "Gifts", "Repair", "VipCrown", "Trove" }
		local missing, badValue = {}, {}
		for _, id in ipairs(ids) do
			if Config.Icons[id] == nil then
				missing[#missing + 1] = id
			end
		end
		for id, v in pairs(Config.Icons) do
			if not (type(v) == "string" and (PixelIcon.Bitmaps[v] or v:sub(1, 13) == "rbxassetid://")) then
				badValue[#badValue + 1] = id .. "=" .. tostring(v)
			end
		end
		T.check(#missing == 0, "token icon: Config.Icons names an icon for every tile / tab / coin id", table.concat(missing, ", "))
		T.check(#badValue == 0, "token icon: every Config.Icons value is a PixelIcon bitmap (or an rbxassetid)", table.concat(badValue, ", "))
		T.check(Config.Icons.Tokens == "token", "token icon: Config.Icons.Tokens = \"token\"")
		-- NeonKit.Icon draws it and follows what a caller sets on a glyph
		local f = Instance.new("Frame")
		local icon = NK.Icon(f, "Tokens", 27)
		local pix = icon and icon:FindFirstChild("Icon")
		T.check(icon and icon:IsA("TextLabel") and icon.Text == "" and icon:GetAttribute("PixelIcon") == "token" and pix and pix:GetAttribute("PixelIcon") == "token",
			"token icon: NeonKit.Icon(parent, \"Tokens\") is an empty TextLabel hosting the token PixelIcon", icon and (icon.ClassName .. " '" .. tostring(icon.Text) .. "'") or "nil")
		local rect = pix and pix:FindFirstChild("R1")
		if rect then
			T.check(pix.Size.X.Offset == 27 and #pix:GetChildren() == #PixelIcon.Runs("token"), "token icon: the coin is 27 px, one Frame per merged run")
			icon.TextColor3 = Color3.fromRGB(10, 200, 30)
			icon.TextTransparency = 0.5
			icon.ZIndex = 7
			T.check(rect.BackgroundColor3 == Color3.fromRGB(10, 200, 30) and math.abs(rect.BackgroundTransparency - 0.5) < 1e-6 and rect.ZIndex == 7,
				"token icon: the coin follows the icon's TextColor3, TextTransparency and ZIndex")
		end
		local tile = NK.Icon(f, "Pets", 38)
		T.check(tile and tile:GetAttribute("PixelIcon") == "paw" and tile:FindFirstChild("Icon") and tile:FindFirstChild("Icon").Size.X.Offset == 36,
			"token icon: a tile id draws its PixelIcon at the nearest multiple of 9 (Pets: the paw, 38 -> 36 px)")
		local plain = NK.Icon(f, "R$", 20)
		T.check(plain and plain.Text == "R$", "token icon: plain text that is no icon id shows as it is")
		f:Destroy()
		-- PixelIcon.Host on a host that already holds an icon replaces it (a mark that changes, the HUD coin resized by the
		-- layout poll): one icon left, and the old one's colour hooks are gone with it
		local host = Instance.new("TextLabel")
		host.TextSize = 20
		PixelIcon.Host(host, "check")
		PixelIcon.Host(host, "x")
		local icons = {}
		for _, c in ipairs(host:GetChildren()) do
			if c.Name == "Icon" then
				icons[#icons + 1] = c
			end
		end
		host.TextColor3 = Color3.fromRGB(200, 10, 10)
		local r1 = icons[1] and icons[1]:FindFirstChild("R1")
		T.check(#icons == 1 and icons[1]:GetAttribute("PixelIcon") == "x" and r1 and r1.BackgroundColor3 == Color3.fromRGB(200, 10, 10),
			"token icon: hosting again replaces the icon (one left, the new one follows the host's colour)", tostring(#icons))
		host:Destroy()
		-- PixelIcon.Lead: the coin before an amount
		local lab = Instance.new("TextLabel")
		lab.Size = UDim2.fromOffset(200, 30)
		lab.TextSize = 20
		lab.Text = "1,250"
		lab.TextXAlignment = Enum.TextXAlignment.Left
		local lead = type(PixelIcon.Lead) == "function" and PixelIcon.Lead(lab, "token") or nil
		local pad = lab:FindFirstChildOfClass("UIPadding")
		T.check(lead and lead.Name == "LeadIcon" and lead:GetAttribute("PixelIcon") == "token" and lead.Size.X.Offset == 18 and pad and pad.PaddingLeft.Offset >= 18,
			"token icon: PixelIcon.Lead(label, \"token\") puts an 18 px coin before a 20 px amount and pads the text past it")
		lab:Destroy()
		-- run time: each surface holds the coin and no cloud glyph
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local surfaces = {
			{ "the HUD token coin", "^NimbusHud%.TopRight%.Currency%.Currency_Tokens" },
			{ "the HUD title card", "^NimbusHud%.TopLeft%.TitleCard%.Coin" },
			{ "the match HUD tokens line", "^NimbusHud%.TopLeft%.MatchPanel%..-%.Inner%.Tokens" },
			{ "the Shop's token balance", "^NimbusShop%..-%.Balance_Tokens" },
			{ "an egg card's spin price", "^NimbusShop%..-ShopCard_Cloud%.Body%.Spin" },
			{ "the Gems tab's token piles", "^NimbusShop%..-%.TokenPack_%d+%.Body%.Art" },
			{ "the Fusion token chip", "^NimbusFusion%..-%.TokenChip" },
			{ "the token toast", "^NimbusNotify%..-%.Toast%.Icon" },
			{ "the Stats window's tokens", "^NimbusMenu%.Window_Stats%..-%.Tile_Tokens" },
			{ "the Stats window's tokens earned", "^NimbusMenu%.Window_Stats%..-%.Tile_Earned" },
			{ "the Index reward", "^NimbusIndex%..-%.Rewards%.Amount" },
			{ "the match result's tokens", "^NimbusNotify%.ResultHolder%..-%.RowTokens" },
			{ "the match result's members", "^NimbusNotify%.ResultHolder%..-%.Member%d+%.Tokens" },
			{ "the hatch stage's Spin again", "^NimbusHatch%..-%.SpinAgain" },
		}
		local seen, cloudy = {}, {}
		local function look()
			for _, d in ipairs(pg:GetDescendants()) do
				local path = U7.path(d)
				for _, s in ipairs(surfaces) do
					if path:find(s[2]) then
						if d:GetAttribute("PixelIcon") == "token" then
							seen[s[1]] = true
						end
						if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text:find("\226\152\129", 1, true) then
							cloudy[path] = true
						end
					end
				end
			end
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		Mock.SetViewport(1920, 1080)
		LKC.advance(0.1)
		U7.openAll(look)
		local absent, cl = {}, {}
		for _, s in ipairs(surfaces) do
			if not seen[s[1]] then
				absent[#absent + 1] = s[1]
			end
		end
		for path in pairs(cloudy) do
			cl[#cl + 1] = path
		end
		table.sort(cl)
		T.check(#absent == 0, "token icon: every token surface holds the token PixelIcon", table.concat(absent, ", "))
		T.check(#cl == 0, "token icon: no token surface shows the cloud glyph", table.concat(cl, "; "))
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.2)
		LKC.flushErrors("token_icon_everywhere")
	end)

	------------------------------------------------------------------------------------------------
	-- U8 (finding 15; the owner's kit B pitch, the HUD and Pets stages, and the Index moved in on 2026-11-13): the lobby HUD,
	-- the Pets window and the Index on the Signboard kit. Each scenario sets its screen and input, feeds a known profile
	-- (U8.feed: five pets, a team of two) and puts everything back after.
	local U8 = {}
	U8.KEYS = { "ember_phoenix", "biscuit_bear", "sunbeam_bear", "pebble_pup", "maple_fox" }
	function U8.pg()
		return game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	function U8.rect(o)
		local p, s = o.AbsolutePosition, o.AbsoluteSize
		return { X = p.X, Y = p.Y, R = p.X + s.X, B = p.Y + s.Y }
	end
	function U8.show(r)
		return fmt("%d,%d..%d,%d", r.X, r.Y, r.R, r.B)
	end
	function U8.overlap(a, b)
		return a.X < b.R - 0.5 and b.X < a.R - 0.5 and a.Y < b.B - 0.5 and b.Y < a.B - 0.5
	end
	-- the product of the UIScales on an object and every GuiObject above it (screen px per design px)
	function U8.scaleOf(o)
		local s, cur = 1, o
		while cur and not cur:IsA("LayerCollector") do
			if cur:IsA("GuiObject") then
				for _, c in ipairs(cur:GetChildren()) do
					if c:IsA("UIScale") and c.Scale > 0 then
						s = s * c.Scale
					end
				end
			end
			cur = cur.Parent
		end
		return s
	end
	-- shown: every GuiObject up to its ScreenGui visible, and the ScreenGui enabled
	function U8.shown(o)
		local cur = o
		while cur and not cur:IsA("LayerCollector") do
			if cur:IsA("GuiObject") and not cur.Visible then
				return false
			end
			cur = cur.Parent
		end
		return cur ~= nil and cur.Enabled ~= false
	end
	function U8.feed(team, garden, growth, stations) -- (render gate) garden: keys in the Pet Garden (busy pets); growth: PetGrowth; stations: Home.Stations
		local pets, levels, discovered = {}, {}, {}
		for i, key in ipairs(U8.KEYS) do
			pets[key] = 1
			levels[key] = { Level = 4 + 3 * i, Xp = 10 }
			discovered[key] = true
		end
		local preset = team or { U8.KEYS[1], U8.KEYS[2] }
		LKC.toClient("ProfileSync", {
			Tokens = 1250, Pets = pets, Equipped = preset, Items = {},
			Stats = { Matches = 0, Wins = 0, TokensEarned = 0, Spins = 0, BestTimes = {} },
			Perks = { MaxHealth = 0, TokenBonus = 0, StaminaRegen = 0, CheckpointHeal = 0 },
			Discovered = discovered, IndexClaimed = {},
			Tutorial = { Step = 1000, Done = true, Gifted = true },
			Cash = 48200, Gems = 320,
			Home = { Level = 5, Prestige = 0, Stations = stations or { Garden = 1 }, Garden = garden or {}, Gym = {}, CollectorCash = 0 },
			Food = {}, Tiers = {}, Hybrids = {}, PetLevels = levels,
			Teams = { Presets = { preset, {}, {} }, Active = 1, Slots = 3, Busy = {} },
			Battle = { Trophies = 120, TrialBest = 0, TrialCleared = {}, Raids = 0, RaidBestDamage = 0, PvPWins = 0, PvPLosses = 0, EventPets = {} },
			PetGrowth = growth or {}, Ring = { Best = 0, Runs = 0 },
		})
		LKC.advance(0.2)
	end
	function U8.closeAll()
		for _, name in ipairs({ "Controllers/PetsController", "Controllers/IndexController", "Controllers/MenuController", "Controllers/DailyController",
			"Controllers/ShopController" }) do
			local m = U7.client(name)
			if m and type(m.Close) == "function" then
				pcall(m.Close, true)
			end
		end
		LKC.advance(0.4)
	end
	-- runs fn(tag) at a screen size and input, in the lobby (no match, no battle), with the U8 profile and every window closed
	function U8.at(w, h, touch, label, fn)
		local UIS = game:GetService("UserInputService")
		local Config = LoadingH.shared("Config")
		local lp = game:GetService("Players").LocalPlayer
		local old = { Mock.Viewport.X, Mock.Viewport.Y, UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled }
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = touch, not touch, not touch
		Mock.SetViewport(w, h)
		lp:SetAttribute(Config.Attr.InMatch, false)
		lp:SetAttribute(Config.Attr.InBattle, nil)
		LKC.toClient("MatchState", nil)
		LKC.toClient("PartyState", nil)
		U8.closeAll()
		U8.feed()
		LKC.advance(1.2) -- the HUD's layout poll (0.5 s) and the gift's relayout
		local tag = fmt("%s %dx%d", label, w, h)
		local ok, err = pcall(fn, tag)
		T.check(ok, tag .. ": the check ran", tostring(err))
		U8.closeAll()
		UIS.TouchEnabled, UIS.KeyboardEnabled, UIS.MouseEnabled = old[3], old[4], old[5]
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.6)
	end
	U8.SIZES = { { 1920, 1080, false }, { 1280, 720, false }, { 844, 390, true }, { 390, 844, true } }
	-- a fill counts as green: the grass plank of kit B, or any colour whose green leads red and blue clearly
	function U8.green(c)
		local Sign = LoadingH.shared("Theme").Sign
		return sameColor(c, Sign.Grass) or sameColor(c, Sign.GrassLip) or (c.G > c.R + 0.2 and c.G > c.B + 0.2)
	end
	-- the face a button shows: its own fill when it paints one, else its Face child's (a SignKit plank, a kit B block)
	function U8.faceOf(button)
		if button.BackgroundTransparency < 0.5 then
			return button.BackgroundColor3
		end
		local face = button:FindFirstChild("Face", true)
		if face and face:IsA("GuiObject") and face.BackgroundTransparency < 0.5 then
			return face.BackgroundColor3
		end
		return nil
	end
	-- the shown buttons under `root` whose face is green (the actions; a pet card's in-team chip is a label, not a button)
	function U8.greenActions(root)
		local out = {}
		for _, d in ipairs(root and root:GetDescendants() or {}) do
			if d:IsA("GuiButton") and U8.shown(d) then
				local c = U8.faceOf(d)
				if c and U8.green(c) then
					out[#out + 1] = d.Name
				end
			end
		end
		table.sort(out)
		return out
	end

	-- (U9-6) the battle family's views (U96.FAMILY, declared above: the emoji walk opens them too), defined here, after U8
	function U96.close()
		local H = _G.P5BattleH
		local BC = U7.client("Controllers/BattleController")
		pcall(U7.client("Controllers/LossScreen").Hide)
		if H and BC then
			pcall(H.cleanup, BC, U96.d)
		end
		U96.d = nil
		game:GetService("Players").LocalPlayer:SetAttribute(LoadingH.shared("Config").Attr.InBattle, nil)
		LKC.advance(0.5)
	end
	function U96.open(view)
		local H = _G.P5BattleH
		local lp = game:GetService("Players").LocalPlayer
		if view == "loss" then
			local pets = {}
			for i = 1, 3 do
				pets[i] = { Key = U8.KEYS[i], PetId = U8.KEYS[i], Before = 18 + i, After = (i == 1) and 20 or (18 + i), XpFrac = 0.6, XpBefore = 0.2 }
			end
			U7.client("Controllers/LossScreen").Show({ Mode = "Ring", Title = "RUN OVER", Sub = "Champion Ring: the champion won round 3", Pets = pets,
				Lines = { { "+$1,240 Cash" }, { "+96 Pet XP" }, { "+8 Tokens" } }, Start = 1, OnFightAgain = function() end, OnClose = function() end })
			LKC.advance(1)
			return
		end
		if not H then
			return
		end
		local sub = view:match("^battle:(.*)$")
		local me = lp.UserId
		local d
		if sub == "dungeon" then
			d = H.dungeon(4, true)
		elseif sub == "raid" then
			d = H.driver({ Mode = "Raid", Boss = "storm_titan", Teams = { { Owner = me, Side = 1, Pets = H.team(3, 0, 30) },
				{ Owner = 77, Side = 1, Pets = H.team(3, 2, 26), Auto = true } } })
		else
			local BCat = LoadingH.shared("BattleCatalog")
			d = H.driver({ Mode = "Ring", Round = 8, Zone = { X = 44, Z = 44 }, TimeLimit = 90,
				Teams = { { Owner = me, Side = 1, Pets = H.team(3, 0, 30) }, BCat.ChampionTeam(8, 7) },
				Ring = { Round = 8, Best = 12, Start = 1, Champion = {} } })
		end
		if not d then
			return
		end
		U96.d = d
		H.begin(d)
		d:run(1, 30)
		if sub == "next" or sub == "result" then
			LKC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Ring", Outcome = "Win", Won = true, Spectator = false, Reason = "Wipe",
				Rewards = { Won = true, Next = 9, Round = 8, Cash = 428, Xp = 68, Tokens = 0, Record = false, LevelUps = 0 } }, d.id)
			LKC.advance(0.9)
			if sub == "result" then
				LKC.toClient("BattleState", "End", { BattleId = d.id, Mode = "Ring", Outcome = "Left", Won = false, Spectator = false, Reason = "Forfeit", Round = 8,
					Rewards = { Won = false, Final = true, Round = 8, Cash = 0, Xp = 0, LevelUps = 2,
						Run = { Wins = 8, Cash = 2571, Xp = 806, Tokens = 0, Round = 8, Start = 1, Best = 12 } } }, d.id)
				LKC.advance(0.8)
			end
		end
	end
	-- the view shows: its ScreenGui enabled with a shown part in it
	function U96.showing(gui)
		if not gui or gui.Enabled == false then
			return false
		end
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("GuiObject") and d.BackgroundTransparency < 1 and d.AbsoluteSize.X > 0 and U8.shown(d) then
				return true
			end
		end
		return false
	end

	-- (U8) the gift docks under the currency strips (the pitch's HUD stage: a small pink block right-aligned under them): its
	-- right edge on the strips' right edge, its top a small gap under the last strip, never over a strip, and the HUD's
	-- TopRightBottom (where the toasts start) under it; a kit B block (the pink awning colour, square, the pixel gift and
	-- "Gift"), at every grid size
	S.hud_gift_under_strips = guarded("hud_gift_under_strips", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		for _, s in ipairs(U8.SIZES) do
			U8.at(s[1], s[2], s[3], "hud gift", function(tag)
				local pg = U8.pg()
				local hud = pg:FindFirstChild("NimbusHud")
				local daily = pg:FindFirstChild("NimbusDaily")
				local gift = daily and daily:FindFirstChild("GiftsButton", true)
				local strips = nil
				for _, d in ipairs(hud and hud:GetDescendants() or {}) do
					if d.Name:match("^Currency_") and d:IsA("GuiObject") and U8.shown(d) then
						local r = U8.rect(d)
						strips = strips and { X = math.min(strips.X, r.X), Y = math.min(strips.Y, r.Y), R = math.max(strips.R, r.R), B = math.max(strips.B, r.B) } or r
					end
				end
				if not T.check(gift ~= nil and strips ~= nil and U8.shown(gift), tag .. ": the strips and the Gifts button show in the lobby") then
					return
				end
				local g = U8.rect(gift)
				T.check(math.abs(g.R - strips.R) <= 1.5, tag .. ": the gift's right edge is the strips' right edge", fmt("gift %s, strips %s", U8.show(g), U8.show(strips)))
				T.check(g.Y >= strips.B + 2 and g.Y <= strips.B + 16, tag .. ": the gift sits a small gap under the last strip", fmt("gift %s, strips %s", U8.show(g), U8.show(strips)))
				local over = {}
				for _, d in ipairs(hud:GetDescendants()) do
					if d.Name:match("^Currency_") and d:IsA("GuiObject") and U8.shown(d) and U8.overlap(U8.rect(d), g) then
						over[#over + 1] = d.Name
					end
				end
				T.check(#over == 0, tag .. ": the gift covers no strip", table.concat(over, ", "))
				T.check((tonumber(hud:GetAttribute("TopRightBottom")) or 0) >= g.B - 0.5, tag .. ": TopRightBottom (where the toasts start) is under the gift",
					fmt("TopRightBottom %s, gift bottom %d", tostring(hud:GetAttribute("TopRightBottom")), g.B))
				T.check(g.R - g.X >= 44 - 0.5 and g.B - g.Y >= 44 - 0.5, tag .. ": the gift is a thumb-sized target (44 px)", U8.show(g))
				-- the kit B block
				local face = U8.faceOf(gift)
				T.check(face ~= nil and sameColor(face, Sign.Roof), tag .. ": the gift is a pink block (the awning colour)", face and hex(face) or "no face")
				local round, gloss, icon, word = false, false, false, false
				for _, d in ipairs(gift:GetDescendants()) do
					round = round or (d:IsA("UICorner") and d.Parent == gift)
					gloss = gloss or d:IsA("UIGradient")
					icon = icon or d:GetAttribute("PixelIcon") == "gift"
					word = word or ((d:IsA("TextLabel")) and d.Text == "Gift" and U8.shown(d))
				end
				T.check(not round and not gloss, tag .. ": square, no gloss gradient")
				T.check(icon and word, tag .. ": the pixel gift and the word Gift", fmt("icon %s, word %s", tostring(icon), tostring(word)))
			end)
		end
		LKC.flushErrors("hud_gift_under_strips")
	end)

	-- (U8) the Pets window's cards (the pitch's .pc): a stone face, the rarity on the card's lip (the bottom band in the
	-- rarity's colour), a light pet well, the element as a chip with its PixelIcon (no letter), the team slot on a green chip,
	-- the selected card gold-faced; no corner, no gloss. The Index's pet tiles share the card (the owner moved the Index into
	-- U8: one pet card for both windows)
	S.pets_rarity_on_lip = guarded("pets_rarity_on_lip", function()
		local Theme = LoadingH.shared("Theme")
		local Config = LoadingH.shared("Config")
		local Sign = Theme.Sign
		local CloudUI = U7.client("UI/CloudUI")
		local State = U7.client("State")
		local PC = U7.client("Controllers/PetsController")
		if not T.check(CloudUI and State and PC, "pets lip: CloudUI, State and PetsController load") then
			return
		end
		local function checkCard(card, def, tag, what)
			local lip = card:FindFirstChild("Lip")
			local c = U8.rect(card)
			T.check(card.BackgroundTransparency < 0.05 and (sameColor(card.BackgroundColor3, Sign.Tile) or sameColor(card.BackgroundColor3, Sign.Selected)),
				tag .. ": " .. what .. " has a stone face", hex(card.BackgroundColor3))
			if T.check(lip ~= nil and lip:IsA("Frame"), tag .. ": " .. what .. " has its Lip") then
				local l = U8.rect(lip)
				T.check(sameColor(lip.BackgroundColor3, CloudUI.RarityColor(def.Rarity)) and lip.BackgroundTransparency < 0.05,
					tag .. ": " .. what .. "'s lip wears its rarity's colour (" .. tostring(def.Rarity) .. ")", hex(lip.BackgroundColor3))
				T.check(math.abs(l.B - c.B) <= 1.5 and l.B - l.Y >= 4 and math.abs(l.X - c.X) <= 1.5 and math.abs(l.R - c.R) <= 1.5,
					tag .. ": " .. what .. "'s lip runs along the card's bottom edge", fmt("lip %s, card %s", U8.show(l), U8.show(c)))
			end
			T.eq(card:GetAttribute("Rarity"), def.Rarity, tag .. ": " .. what .. " carries attribute Rarity")
			T.check(card:FindFirstChildOfClass("UICorner") == nil and card:FindFirstChildOfClass("UIGradient") == nil, tag .. ": " .. what .. " is square with no gloss")
		end
		for _, s in ipairs({ { 1920, 1080, false }, { 844, 390, true } }) do
			U8.at(s[1], s[2], s[3], "pets lip", function(tag)
				PC.Open({ Key = U8.KEYS[4] })
				LKC.advance(1)
				local win = U8.pg():FindFirstChild("NimbusPets")
				for i, key in ipairs(U8.KEYS) do
					local card = win and win:FindFirstChild("Card_" .. key, true)
					local def = State.DefOf(key)
					if T.check(card ~= nil and def ~= nil, tag .. ": the card of " .. key .. " exists") then
						checkCard(card, def, tag, key)
						local element = card:FindFirstChild("Element")
						local el = def.Element or (type(def.Elements) == "table" and def.Elements[1]) or nil
						local info = el and Config.Elements.Info[el]
						if info then
							local icon = nil
							for _, d in ipairs(element and element:GetDescendants() or {}) do
								icon = icon or d:GetAttribute("PixelIcon")
							end
							T.check(element and sameColor(element.BackgroundColor3, info.Color) and (not element:IsA("TextLabel") or element.Text == "")
								and icon ~= nil and icon == info.Icon, tag .. ": " .. key .. "'s element is a chip with its PixelIcon (" .. tostring(info.Icon) .. "), no letter",
								element and fmt("%s %s icon %s", element.ClassName, hex(element.BackgroundColor3), tostring(icon)) or "no Element")
						end
						local number = card:FindFirstChild("Number")
						if i <= 2 then
							T.check(number and U8.shown(number) and number.Text == tostring(i) and sameColor(number.BackgroundColor3, Sign.Grass),
								tag .. ": " .. key .. " (team slot " .. i .. ") shows its slot on a green chip", number and fmt("%q %s", number.Text, hex(number.BackgroundColor3)) or "no Number")
						end
						local well = card:FindFirstChild("Picture")
						T.check(well and well.BackgroundTransparency < 0.05 and sameColor(well.BackgroundColor3, Sign.PetWell), tag .. ": " .. key .. "'s pet sits in the light pet well",
							well and hex(well.BackgroundColor3) or "no Picture")
						if key == U8.KEYS[4] then
							T.check(sameColor(card.BackgroundColor3, Sign.Selected), tag .. ": the selected card is gold-faced", hex(card.BackgroundColor3))
						end
					end
				end
				PC.Close(true)
				LKC.advance(0.4)
				-- the Index's tiles: the same card (U8 review: on the first key's rarity tab, so a tab left open by an earlier
				-- scenario, say an empty Fusions tab after client_p2ui, never hides the tiles)
				local Menu = U7.client("Controllers/MenuController")
				local first = LoadingH.shared("PetCatalog").Get(U8.KEYS[1])
				Menu.Open("Index", { GroupId = first and first.Rarity or "Common" })
				LKC.advance(1)
				local index = U8.pg():FindFirstChild("NimbusIndex")
				local n = 0
				for _, d in ipairs(index and index:GetDescendants() or {}) do
					local id = d.Name:match("^IndexPet_(.+)$")
					if id and d:IsA("GuiButton") and U8.shown(d) then
						local def = LoadingH.shared("PetCatalog").Get(id)
						if def then
							n = n + 1
							checkCard(d, def, tag, "Index tile " .. id)
						end
					end
				end
				T.check(n > 0, tag .. ": the Index shows pet tiles", tostring(n))
			end)
		end
		LKC.flushErrors("pets_rarity_on_lip")
	end)

	-- (render gate, GATE_KITB findings 1-4) the Pets window at the four gate sizes, with a gardening team pet and an
	-- evolved one: on PC the header's T1 band reaches out over the frame with its tails, clear of the HUD's currency
	-- strips and inside the screen; on a phone the band stays in the short sign, no tails and no roof stub; a portrait
	-- window starts under the currency row with a gap; a busy pet's cover is opaque and leaves the slot's power (and a
	-- card's level) clear, the team number on top; the detail's evolution stars stay inside its rarity line
	S.pets_gate_fixes = guarded("pets_gate_fixes", function()
		local PC = U7.client("Controllers/PetsController")
		if not T.check(PC ~= nil, "pets gate: PetsController loads") then
			return
		end
		local K1, K2, K3 = U8.KEYS[1], U8.KEYS[2], U8.KEYS[3]
		local sizes = { { 960, 640, false } } -- a small PC screen: no room for the tails beside the strips
		for _, s in ipairs(U8.SIZES) do
			sizes[#sizes + 1] = s
		end
		for _, s in ipairs(sizes) do
			U8.at(s[1], s[2], s[3], "pets gate", function(tag)
				U8.feed({ K1, K2, K3 }, { K2 }, { [K1] = { Evo = 2 } })
				PC.Open({ Key = K1 })
				LKC.advance(1)
				local win = U8.pg():FindFirstChild("NimbusPets")
				local holder = win and win:FindFirstChild("Window_Pets", true)
				local head, roof = nil, nil
				for _, d in ipairs(holder and holder:GetDescendants() or {}) do
					head = head or (d:GetAttribute("SignKit") == "Header" and d or nil)
					roof = roof or (d:GetAttribute("SignKit") == "Roof" and d or nil)
				end
				if not T.check(holder ~= nil and head ~= nil, tag .. ": the window and its Signboard header are built") then
					return
				end
				local phone = s[3]
				local vp = Mock.Viewport
				local hud = U8.pg():FindFirstChild("NimbusHud")
				-- rects in screen px: a ScreenGui that does not ignore the gui inset starts under Roblox's top bar
				local function inset(o)
					local g = o:FindFirstAncestorWhichIsA("LayerCollector")
					return (g and g:IsA("ScreenGui") and not g.IgnoreGuiInset) and (Mock.TopInset or 0) or 0
				end
				local function screen(o)
					local r, dy = U8.rect(o), inset(o)
					return { X = r.X, Y = r.Y + dy, R = r.R, B = r.B + dy }
				end
				local strips = {}
				local cur = hud and hud:FindFirstChild("Currency", true)
				for _, row in ipairs(cur and cur:GetChildren() or {}) do
					if row:IsA("GuiObject") and U8.shown(row) then
						strips[#strips + 1] = screen(row)
					end
				end
				local tails = { head:FindFirstChild("TailL"), head:FindFirstChild("TailR") }
				if phone then
					T.check(head:GetAttribute("Overhang") == false and not U8.shown(tails[1]) and not U8.shown(tails[2]),
						tag .. ": a phone's title sign keeps the band inside, no tails (they would land on the A button)")
					T.check(roof == nil or not U8.shown(roof), tag .. ": no roof stub over a phone's title sign")
				elseif vp.X < 1280 then
					local plate = head:FindFirstChild("Plate")
					local slot, title = plate and plate:FindFirstChild("IconSlot"), plate and plate:FindFirstChild("Title")
					T.check(head:GetAttribute("Overhang") == false and not U8.shown(tails[1]) and not U8.shown(tails[2]),
						tag .. ": with no room beside the window the band stays inside the frame, no tails")
					T.check(slot and title and U8.rect(slot).X >= U8.rect(head).X and U8.rect(title).X >= U8.rect(slot).R
						and U8.rect(title).X - U8.rect(slot).R <= 20,
						tag .. ": ...the paw and the title still inside the header, the title right of the paw",
						slot and title and (U8.show(U8.rect(slot)) .. " / " .. U8.show(U8.rect(title))) or "")
				else
					T.check(head:GetAttribute("Overhang") == true and tails[1] and U8.shown(tails[1]) and tails[2] and U8.shown(tails[2]),
						tag .. ": on PC the band reaches out over the frame with its tails (title_T1)")
					for _, tail in ipairs(tails) do
						local r = screen(tail)
						for _, n in ipairs(tail:GetChildren()) do
							local q = screen(n)
							r = { X = math.min(r.X, q.X), Y = math.min(r.Y, q.Y), R = math.max(r.R, q.R), B = math.max(r.B, q.B) }
						end
						T.check(r.X >= 0 and r.R <= vp.X, tag .. ": " .. tail.Name .. " stays on the screen", U8.show(r))
						local hit = nil
						for _, st in ipairs(strips) do
							hit = hit or (U8.overlap(r, st) and st or nil)
						end
						T.check(hit == nil, tag .. ": " .. tail.Name .. " stays clear of the HUD's currency strips", hit and (U8.show(r) .. " over " .. U8.show(hit)) or "")
					end
				end
				if vp.Y > vp.X then
					local top = screen(holder).Y
					local low = 0
					for _, st in ipairs(strips) do
						low = math.max(low, st.B)
					end
					T.check(#strips > 0 and top >= low + 6, tag .. ": the portrait window starts under the currency row with a gap",
						fmt("window top %d, %d strips to %d", top, #strips, low))
				end
				-- the busy slot and card (K2 is in the garden)
				local slot = holder:FindFirstChild("Slot2", true)
				local busy = slot and slot:FindFirstChild("Busy")
				if T.check(busy ~= nil and U8.shown(busy), tag .. ": the gardening team pet's slot shows its busy cover") then
					T.check(busy.BackgroundTransparency == 0, tag .. ": ...opaque (no washed-out text under it)", tostring(busy.BackgroundTransparency))
					local power = slot:FindFirstChild("Power")
					T.check(power and U8.shown(power) and U8.rect(power).Y >= U8.rect(busy).B - 0.5, tag .. ": ...and the slot's power reads below it",
						power and (U8.show(U8.rect(power)) .. " vs " .. U8.show(U8.rect(busy))) or "no Power")
				end
				local card = holder:FindFirstChild("Card_" .. K2, true)
				local cb = card and card:FindFirstChild("Busy")
				if T.check(cb ~= nil and U8.shown(cb), tag .. ": the gardening pet's card shows its busy cover") then
					local level, number = card:FindFirstChild("Level"), card:FindFirstChild("Number")
					T.check(cb.BackgroundTransparency == 0 and level and U8.rect(level).Y >= U8.rect(cb).B - 0.5,
						tag .. ": ...opaque, the card's level clear below it", level and (U8.show(U8.rect(level)) .. " vs " .. U8.show(U8.rect(cb))) or "no Level")
					T.check(number and U8.shown(number) and number.ZIndex > cb.ZIndex, tag .. ": ...the team number chip drawn over it")
				end
				-- the detail's stars (K1 is evolved twice) inside its line and its panel
				local detail = holder:FindFirstChild("Detail", true) or holder:FindFirstChild("Sheet", true)
				local meta = detail and detail:FindFirstChild("Meta")
				local stars = meta and meta:FindFirstChild("TrailIcon")
				if T.check(stars ~= nil, tag .. ": the detail shows the evolution stars after its line") then
					local r, m, d = U8.rect(stars), U8.rect(meta), U8.rect(detail)
					T.check(r.R <= m.R + 0.5 and r.R <= d.R + 0.5, tag .. ": ...inside the line's box and the detail panel", fmt("stars %s, line %s, panel %s", U8.show(r), U8.show(m), U8.show(d)))
				end
				PC.Close(true)
			end)
		end
		LKC.flushErrors("pets_gate_fixes")
	end)

	-- (U8) one colour by role: at most one green action on the screen. The lobby HUD (tiles, pill, strips, gift) has none;
	-- the Pets window's one green action is "Put in team" (shown for a pet out of the team; none for a team pet); the
	-- Index's only possible green is its Claim button
	S.kitb_one_green_action = guarded("kitb_one_green_action", function()
		local PC = U7.client("Controllers/PetsController")
		local Menu = U7.client("Controllers/MenuController")
		U8.at(1920, 1080, false, "one green", function(tag)
			local pg = U8.pg()
			local hud = {}
			for _, name in ipairs({ "NimbusHud", "NimbusTopBar", "NimbusMenu", "NimbusDaily" }) do
				for _, g in ipairs(U8.greenActions(pg:FindFirstChild(name))) do
					hud[#hud + 1] = name .. "." .. g
				end
			end
			T.check(#hud == 0, tag .. ": the lobby HUD has no green action", table.concat(hud, ", "))
			PC.Open({ Key = U8.KEYS[4] })
			LKC.advance(0.8)
			local greens = U8.greenActions(pg:FindFirstChild("NimbusPets"))
			T.check(#greens == 1 and greens[1] == "ActPut", tag .. ": a pet out of the team: Put in team is the one green action", table.concat(greens, ", "))
			PC.Open({ Key = U8.KEYS[2] })
			LKC.advance(0.8)
			greens = U8.greenActions(pg:FindFirstChild("NimbusPets"))
			T.check(#greens == 0, tag .. ": a team pet: no green action (Remove is the red one)", table.concat(greens, ", "))
			PC.Close(true)
			LKC.advance(0.4)
			Menu.Open("Index")
			LKC.advance(1)
			greens = U8.greenActions(pg:FindFirstChild("NimbusIndex"))
			T.check(#greens == 0 or (#greens == 1 and greens[1] == "Claim"), tag .. ": the Index's only green action is Claim", table.concat(greens, ", "))
		end)
		LKC.flushErrors("kitb_one_green_action")
	end)

	-- (U8; the owner's Index renders: "UNCOMMON" cut on the phone tab) the rarity tabs are signboard tabs: at every grid size each
	-- tab that shows in the tab strip shows whole (never half under the strip's edge or the Elements button), and its name fits
	-- the tab at its own size, never cut or squeezed under 18 design px.
	-- U8 review (the after render listed "Uncommon", "Legendary" and "Fusions" overflowing at 1920x1080 while this passed):
	-- widths are FredokaOne's real ones (SmokeCommon.RealWidth; the mock's TextService is a flat 0.5 em), given to the
	-- window through IndexController.Metrics.MEASURE as the renderer does; a name's padding (the Fusions sparkle's inset)
	-- counts, with 2 px to spare; and the name's drawn text (with its lead icon) never meets the tab's count or its badge
	-- corner (the badge shows whenever a reward waits, so its place is kept free while it is hidden too)
	S.index_tabs_fit_phone = guarded("index_tabs_fit_phone", function()
		local Menu = U7.client("Controllers/MenuController")
		local IC = U7.client("Controllers/IndexController")
		local RealWidth = SmokeCommon.RealWidth
		local SPARE = 2
		local metrics = IC and type(IC.Metrics) == "table" and IC.Metrics or nil
		local savedMeasure = metrics and metrics.MEASURE
		if metrics then
			metrics.MEASURE = function(text, size, font)
				return RealWidth(text, size, font)
			end
		end
		-- a label's drawn text in its tab's own design px: the padded box, the text's real width placed by its alignment,
		-- one TextSize tall in the middle of the box
		local function local_(o, tab, sc)
			local p = (o.AbsolutePosition - tab.AbsolutePosition) / sc
			local z = o.AbsoluteSize / sc
			return { X = p.X, Y = p.Y, R = p.X + z.X, B = p.Y + z.Y }
		end
		local function textRect(label, tab, sc)
			local r = local_(label, tab, sc)
			local pad = label:FindFirstChildOfClass("UIPadding")
			local pl, pr = pad and pad.PaddingLeft.Offset or 0, pad and pad.PaddingRight.Offset or 0
			local pt, pb = pad and pad.PaddingTop.Offset or 0, pad and pad.PaddingBottom.Offset or 0
			local w = RealWidth(label.Text, label.TextSize, label.Font)
			local left, right = r.X + pl, r.R - pr
			local x = left
			if label.TextXAlignment == Enum.TextXAlignment.Right then
				x = right - w
			elseif label.TextXAlignment == Enum.TextXAlignment.Center then
				x = (left + right - w) / 2
			end
			local cy = r.Y + pt + (r.B - r.Y - pt - pb) / 2
			local out = { X = x, R = x + w, Y = cy - label.TextSize / 2, B = cy + label.TextSize / 2 }
			local lead = label:FindFirstChild("LeadIcon")
			if lead then
				local l = local_(lead, tab, sc)
				out.X, out.Y, out.B = math.min(out.X, l.X), math.min(out.Y, l.Y), math.max(out.B, l.B)
			end
			return out, w, pl + pr
		end
		for _, s in ipairs(U8.SIZES) do
			U8.at(s[1], s[2], s[3], "index tabs", function(tag)
				Menu.Open("Index")
				LKC.advance(1)
				local index = U8.pg():FindFirstChild("NimbusIndex")
				local list = index and index:FindFirstChild("GroupList", true)
				if not T.check(list ~= nil, tag .. ": the tab strip (GroupList) exists") then
					return
				end
				local view = U8.rect(list)
				local elements = index:FindFirstChild("ElementsButton", true)
				local cut, tight, seen, meets = {}, {}, 0, {}
				for _, tab in ipairs(list:GetDescendants()) do
					if tab.Name:match("^Group_") and tab:IsA("GuiButton") and U8.shown(tab) then
						local r = U8.rect(tab)
						if U8.overlap(r, view) then
							seen = seen + 1
							local inside = r.X >= view.X - 0.5 and r.R <= view.R + 0.5 and r.Y >= view.Y - 0.5 and r.B <= view.B + 0.5
							local under = elements and U8.shown(elements) and U8.overlap(r, U8.rect(elements))
							if not inside or under then
								cut[#cut + 1] = tab.Name .. " " .. U8.show(r)
							end
							local name = tab:FindFirstChild("GroupName", true)
							if name then
								local sc = U8.scaleOf(name)
								local rect, w, inset = textRect(name, tab, sc)
								local room = name.AbsoluteSize.X / sc
								if name.TextScaled or inset + w + SPARE > room + 0.01 or name.TextSize < 18 then
									tight[#tight + 1] = fmt("%s %q %.1f px + %d inset in %.1f at %s%s", tab.Name, name.Text, w, inset, room, tostring(name.TextSize),
										name.TextScaled and " (scaled)" or "")
								end
								for _, other in ipairs({ "Progress", "Badge" }) do
									local o = tab:FindFirstChild(other)
									if o then
										local r = other == "Progress" and (textRect(o, tab, sc)) or local_(o, tab, sc)
										if U8.overlap(rect, r) then
											meets[#meets + 1] = fmt("%s %q %s meets its %s %s", tab.Name, name.Text, U8.show(rect), other, U8.show(r))
										end
									end
								end
							end
						end
					end
				end
				T.check(seen >= 2, tag .. ": the strip shows at least two tabs", tostring(seen))
				T.check(#cut == 0, tag .. ": every tab in view shows whole (none half under the strip's edge or the Elements button)", table.concat(cut, "; ") .. " | view " .. U8.show(view))
				T.check(#tight == 0, tag .. ": every tab's name (with its lead icon's inset and 2 px to spare) fits it at a fixed size of 18 px or more, real FredokaOne widths",
					table.concat(tight, "; "))
				T.check(#meets == 0, tag .. ": no tab's name meets the tab's count or its badge corner", table.concat(meets, "; "))
			end)
		end
		if metrics then
			metrics.MEASURE = savedMeasure
		end
		LKC.flushErrors("index_tabs_fit_phone")
	end)

	-- (U8; the owner's Index renders: Claim under Roblox's jump button at 844x390) on a touch phone the Claim button never
	-- sits under the jump button: Roblox's touch controls go while the window is open (MenuController.SetTouchHidden, as the
	-- Pets window, the Shop and the Gifts window do), or the button is clear of the jump button's square; and they come back
	-- as they were on Close
	S.index_claim_clear_of_jump = guarded("index_claim_clear_of_jump", function()
		local Menu = U7.client("Controllers/MenuController")
		local IC = U7.client("Controllers/IndexController")
		local GuiService = game:GetService("GuiService")
		for _, s in ipairs({ { 844, 390, true }, { 390, 844, true } }) do
			U8.at(s[1], s[2], s[3], "index claim", function(tag)
				local before = GuiService.TouchControlsEnabled
				Menu.Open("Index")
				LKC.advance(1)
				local index = U8.pg():FindFirstChild("NimbusIndex")
				local claim = index and index:FindFirstChild("Claim", true)
				if not T.check(claim ~= nil and U8.shown(claim), tag .. ": the Claim button shows") then
					return
				end
				-- Roblox's jump button on a phone (HudController K: J = 70, from 1.5 J + 10 to 0.5 J + 10 off the right edge, its
				-- bottom 20 px over the bottom edge), in the window's own coordinates
				local J = 70
				local inset = index.IgnoreGuiInset and 0 or 58
				local jump = { X = s[1] - (1.5 * J + 10), R = s[1] - (0.5 * J + 10), Y = s[2] - 20 - J - inset, B = s[2] - 20 - inset }
				local hidden = GuiService.TouchControlsEnabled == false
				local c = U8.rect(claim)
				T.check(hidden or not U8.overlap(c, jump), tag .. ": Claim is never under the jump button (the touch controls hidden, or Claim clear of it)",
					fmt("touch controls %s, claim %s, jump %s", tostring(GuiService.TouchControlsEnabled), U8.show(c), U8.show(jump)))
				IC.Close()
				LKC.advance(0.5)
				T.eq(GuiService.TouchControlsEnabled, before, tag .. ": the touch controls are back as they were after Close")
			end)
		end
		LKC.flushErrors("index_claim_clear_of_jump")
	end)

	-- (U8; finding 15) no neon glow in the U8 families: the lobby HUD (NimbusHud, the top-bar pill, the menu tiles, the gift, the
	-- boost chips under it), the
	-- Pets window and the Index. No glow ring (a NeonKit Glow frame or GlowStroke shown), no gloss gradient (a UIGradient on
	-- a shown object; kit B's functional ones are named Lip, Step, Sweep or Fill and keep a flat face), no neon border (a
	-- Border UIStroke in a Theme.Neon colour) and no Theme.Neon fill. NeonKit.Card's glow is off unless asked for
	S.kitb_no_neon_glow = guarded("kitb_no_neon_glow", function()
		local Theme = LoadingH.shared("Theme")
		local NK = U7.client("UI/NeonKit")
		local PC = U7.client("Controllers/PetsController")
		local Menu = U7.client("Controllers/MenuController")
		if not T.check(NK and PC and Menu, "no neon glow: NeonKit, PetsController and MenuController load") then
			return
		end
		local plain = NK.Card({ Name = "U8Probe" })
		local lit = NK.Card({ Name = "U8Probe", Glow = true })
		T.check(plain.Glow.Visible == false and lit.Glow.Visible == true, "no neon glow: NeonKit.Card's glow is off by default (Glow = true turns it on)")
		plain.Root:Destroy()
		lit.Root:Destroy()
		local ALLOWED = { Lip = true, Step = true, Sweep = true, Fill = true }
		local function neonName(c)
			for name, n in pairs(Theme.Neon) do
				if sameColor(c, n) then
					return name
				end
			end
			return nil
		end
		-- (U8 review) the drawn cut gem (client/UI/GemIcon, spec 5.7) is an icon whose tones are its art (U8 kept it on its navy
		-- square): its gradients are not a panel's gloss. The Gems strip shows only in some lobby states, so the walk met it
		-- only after another scenario had turned it on
		local function inGemIcon(d)
			local cur = d.Parent
			while cur and not cur:IsA("LayerCollector") do
				if cur.Name == "GemIcon" then
					return true
				end
				cur = cur.Parent
			end
			return false
		end
		local function walk(root, family, bad)
			for _, d in ipairs(root and root:GetDescendants() or {}) do
				local p = d.Parent
				if d:IsA("UIStroke") and p and p:IsA("GuiObject") and U8.shown(p) and d.Enabled ~= false and d.Transparency < 0.95 then
					if d.Name == "GlowStroke" or (p.Name == "Glow" and d.ApplyStrokeMode == Enum.ApplyStrokeMode.Border) then
						bad[#bad + 1] = family .. ": a glow ring on " .. p:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
					elseif d.ApplyStrokeMode == Enum.ApplyStrokeMode.Border and neonName(d.Color) then
						bad[#bad + 1] = family .. ": a neon " .. neonName(d.Color) .. " border on " .. p.Name
					end
				elseif d:IsA("UIGradient") and p and p:IsA("GuiObject") and U8.shown(p) and d.Enabled ~= false and not ALLOWED[d.Name] and not inGemIcon(d)
					and not designedLook(d) then -- (kit-b merge) the title's T1 ribbon: its gold bands and TitleHide are the owner's pick
					bad[#bad + 1] = family .. ": a gloss gradient on " .. p:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
				elseif d:IsA("GuiObject") and d.BackgroundTransparency < 0.5 and U8.shown(d) and neonName(d.BackgroundColor3) then
					bad[#bad + 1] = family .. ": a neon " .. neonName(d.BackgroundColor3) .. " fill on " .. d.Name
				end
			end
		end
		for _, s in ipairs({ { 1920, 1080, false }, { 844, 390, true } }) do
			U8.at(s[1], s[2], s[3], "no neon glow", function(tag)
				local pg = U8.pg()
				local bad = {}
				local menu = pg:FindFirstChild("NimbusMenu")
				walk(pg:FindFirstChild("NimbusHud"), "HUD", bad)
				walk(pg:FindFirstChild("NimbusTopBar"), "HUD pill", bad)
				walk(menu and menu:FindFirstChild("MenuColumn"), "HUD tiles", bad)
				local daily = pg:FindFirstChild("NimbusDaily")
				local gift = daily and daily:FindFirstChild("GiftsButton")
				if gift then
					walk(gift, "HUD gift", bad)
				end
				-- (U8 review) the boost chips hang right under the gift: both shown (the two passes), each a kit B tag (a flat
				-- block in its wood edge, square: no UICorner, no gradient)
				local lp = game:GetService("Players").LocalPlayer
				local oldPasses = lp:GetAttribute("OwnedPasses")
				lp:SetAttribute("OwnedPasses", "Cash2x,PetXp2x")
				LKC.advance(0.3)
				local boosts = pg:FindFirstChild("NimbusBoosts")
				local chips = 0
				for _, name in ipairs({ "Chip_Cash", "Chip_Xp" }) do
					local chip = boosts and boosts:FindFirstChild(name, true)
					if chip and U8.shown(chip) then
						chips = chips + 1
						T.check(chip:FindFirstChildOfClass("UICorner") == nil and chip:FindFirstChildOfClass("UIGradient") == nil and chip:FindFirstChild("SignEdge") ~= nil
							and chip.BackgroundTransparency == 0, tag .. ": the boost chip " .. name .. " is a kit B tag (a flat face in a wood edge, square)")
					end
				end
				T.check(chips == 2, tag .. ": both boost chips show under the gift (the two passes)", tostring(chips))
				walk(boosts, "HUD boosts", bad)
				lp:SetAttribute("OwnedPasses", oldPasses)
				LKC.advance(0.3)
				PC.Open({ Key = U8.KEYS[4] })
				LKC.advance(1)
				walk(pg:FindFirstChild("NimbusPets"), "Pets", bad)
				PC.Close(true)
				LKC.advance(0.4)
				Menu.Open("Index")
				LKC.advance(1)
				walk(pg:FindFirstChild("NimbusIndex"), "Index", bad)
				T.check(#bad == 0, fmt("%s: no glow ring, gloss gradient, neon border or neon fill in the HUD, the Pets window and the Index (%d)", tag, #bad),
					table.concat(bad, "; ", 1, math.min(#bad, 12)))
				-- (U9-5) and the Care family: the Training Place, the Food Machine, the garden picker, the Fusion Machine on both
				-- tabs and the pet picker in its three contexts
				pcall(Menu.Close)
				LKC.advance(0.4)
				local family, opened = {}, 0
				for _, f in ipairs(U9.FAMILY) do
					U9.open(f[1])
					local gui = pg:FindFirstChild(f[2])
					if U9.showing(gui) then
						opened = opened + 1
					end
					walk(gui, f[1], family)
					U9.close()
				end
				T.check(opened == #U9.FAMILY, fmt("%s: every Care family view opened (%d of %d)", tag, opened, #U9.FAMILY))
				T.check(#family == 0, fmt("%s: no glow ring, gloss gradient, neon border or neon fill in the Care family (%d)", tag, #family),
					table.concat(family, "; ", 1, math.min(#family, 12)))
				-- (U9-6) and the battle family: the HUD in a dungeon room, a raid and a ring round, the next-round card, the run's
				-- result card and the loss screen. Stricter than the walk above: kit B is square and flat, so a shown gradient is
				-- only a pie's hard-edged Sweep (a cooldown ring) or the title's designed look, and a corner only rounds a disc (a
				-- round button, a portrait: CornerRadius 0.5)
				local battle, seen = {}, 0
				for _, f in ipairs(U96.FAMILY) do
					U96.open(f[1])
					local gui = pg:FindFirstChild(f[2])
					if U96.showing(gui) then
						seen = seen + 1
					end
					walk(gui, f[1], battle)
					for _, d in ipairs(gui and gui:GetDescendants() or {}) do
						local p = d.Parent
						if p and p:IsA("GuiObject") and U8.shown(p) and not designedLook(d) then
							local where = f[1] .. ": " .. p:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
							if d:IsA("UIGradient") and d.Enabled ~= false and d.Name ~= "Sweep" and d.Name ~= "Fill" and d.Name ~= "Lip" then
								battle[#battle + 1] = where .. " has a gradient (" .. d.Name .. ")"
							elseif d:IsA("UIGradient") and d.Enabled ~= false and d.Name == "Fill" then
								battle[#battle + 1] = where .. " has a gloss fill gradient"
							elseif d:IsA("UICorner") and not (d.CornerRadius.Scale >= 0.49 and p.AbsoluteSize.X > 0 and math.abs(p.AbsoluteSize.X - p.AbsoluteSize.Y) <= 1.5) then
								battle[#battle + 1] = where .. " has a rounded corner"
							end
						end
					end
					U96.close()
				end
				T.check(seen == #U96.FAMILY, fmt("%s: every battle family view opened (%d of %d)", tag, seen, #U96.FAMILY))
				T.check(#battle == 0, fmt("%s: no glow, gradient, neon or rounded corner in the battle family (%d)", tag, #battle),
					table.concat(battle, "; ", 1, math.min(#battle, 12)))
			end)
		end
		LKC.flushErrors("kitb_no_neon_glow")
	end)

	-- (U9-5) the Care family fits a phone: at 844x390 and 390x844 (touch) every view of the family (U9.FAMILY) shows, and in
	-- it every shown text and button is whole on the screen, never cut by a clipping frame above it (a ScrollingFrame's
	-- rows scroll, so they are left out), every one-line text fits its box at FredokaOne's / LuckiestGuy's real widths
	-- (SmokeCommon.RealWidth; other faces through Theme.MeasureLabel) with 2 px to spare, and nothing sits under Roblox's
	-- thumbstick or jump button (the render's ghosts: 70 px circles 20 px over the bottom edge, the stick 25 px in from the
	-- left, the jump 45 px in from the right) unless the window hid them (GuiService.TouchControlsEnabled false)
	S.care_family_fits_phone = guarded("care_family_fits_phone", function()
		local Theme = LoadingH.shared("Theme")
		local GuiService = game:GetService("GuiService")
		local RealWidth = SmokeCommon.RealWidth
		local function width(o)
			local text = o.Text
			local role = o:GetAttribute("FontRole")
			if role and Theme.CapsRoles[role] then
				text = Theme.Caps(text)
			end
			local w = RealWidth(text, o.TextSize, Theme.FontOf(o), true)
			return (w or Theme.MeasureLabel(o).X) * U8.scaleOf(o)
		end
		local function inScroll(o)
			local cur = o.Parent
			while cur and not cur:IsA("LayerCollector") do
				if cur:IsA("ScrollingFrame") then
					return true
				end
				cur = cur.Parent
			end
			return false
		end
		-- (a CloudUI bar's text is two copies, each cut at the fill's edge on purpose: TextFill / TextTrack are not counted)
		local SPLIT = { TextFill = true, TextTrack = true }
		local function clipper(o)
			local cur = o.Parent
			while cur and not cur:IsA("LayerCollector") do
				if cur:IsA("GuiObject") and cur.ClipsDescendants and not SPLIT[cur.Name] then
					return cur
				end
				cur = cur.Parent
			end
			return nil
		end
		local function inside(a, b)
			return a.X >= b.X - 1 and a.R <= b.R + 1 and a.Y >= b.Y - 1 and a.B <= b.B + 1
		end
		-- the windows fit their titles and names with Theme.Measure on an Enum font (TextService): the mock's is a flat 0.5 em,
		-- so for the test it measures one line of a known face at its real width, as Roblox does
		local mockMeasure = Theme.Measure
		Theme.Measure = function(text, role, size, width)
			if (tonumber(width) == nil or tonumber(width) >= 4096) and not tostring(text):find("\n") then
				local font, spare = role, 1
				text = tostring(text or "")
				if type(role) == "string" and Theme.Fonts[role] then -- a role: its capitals and its spare widening, as Theme.Measure
					font, spare = Theme.Fonts[role], Theme.MeasureSpare[role] or 1
					if Theme.CapsRoles[role] then
						text = Theme.Caps(text)
					end
				end
				local w = typeof(font) == "EnumItem" and RealWidth(text, tonumber(size) or 14, font, true) or nil
				if w then
					return Vector2.new(math.ceil(w * spare), tonumber(size) or 14)
				end
			end
			return mockMeasure(text, role, size, width)
		end
		for _, s in ipairs({ { 844, 390 }, { 390, 844 } }) do
			local W, Hh = s[1], s[2]
			for _, f in ipairs(U9.FAMILY) do
				U8.at(W, Hh, true, "care family " .. f[1], function(tag)
					U9.open(f[1])
					local gui = U8.pg():FindFirstChild(f[2])
					if not T.check(U9.showing(gui), tag .. ": the window shows (" .. f[2] .. ")") then
						U9.close()
						return
					end
					local dy = gui.IgnoreGuiInset and 0 or Mock.TopInset
					local screen = { X = 0, Y = -dy, R = W, B = Hh - dy }
					local zones = {}
					if GuiService.TouchControlsEnabled ~= false then
						zones[1] = { X = 25, Y = Hh - 90 - dy, R = 95, B = Hh - 20 - dy, Name = "thumbstick" }
						zones[2] = { X = W - 115, Y = Hh - 90 - dy, R = W - 45, B = Hh - 20 - dy, Name = "jump" }
					end
					local off, cut, tight, under = {}, {}, {}, {}
					for _, d in ipairs(gui:GetDescendants()) do
						local texty = (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 1
						if (texty or d:IsA("GuiButton")) and U8.shown(d) and not inScroll(d) and d.AbsoluteSize.X > 0 then
							local r = U8.rect(d)
							local name = d:GetFullName():gsub("^.-" .. f[2] .. "%.", "")
							if not inside(r, screen) then
								off[#off + 1] = name .. " " .. U8.show(r)
							end
							local c = clipper(d)
							if c and not inside(r, U8.rect(c)) then
								cut[#cut + 1] = name .. " " .. U8.show(r) .. " in " .. c.Name .. " " .. U8.show(U8.rect(c))
							end
							if texty and not d.TextWrapped and not d.TextScaled then
								local pad = d:FindFirstChildOfClass("UIPadding")
								local inset = pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) * U8.scaleOf(d) or 0
								local w = width(d)
								if w + inset + 2 > d.AbsoluteSize.X + 0.01 then
									tight[#tight + 1] = fmt("%s %q %.0f px in %.0f", name, d.Text, w + inset, d.AbsoluteSize.X)
								end
							end
							for _, z in ipairs(zones) do
								if U8.overlap(r, z) then
									under[#under + 1] = name .. " under the " .. z.Name
								end
							end
						end
					end
					T.check(#off == 0, fmt("%s: every text and button is on the screen (%d)", tag, #off), table.concat(off, "; ", 1, math.min(#off, 8)))
					T.check(#cut == 0, fmt("%s: no text or button cut by a clipping frame (%d)", tag, #cut), table.concat(cut, "; ", 1, math.min(#cut, 8)))
					T.check(#tight == 0, fmt("%s: every one-line text fits its box (%d)", tag, #tight), table.concat(tight, "; ", 1, math.min(#tight, 8)))
					T.check(#under == 0, fmt("%s: nothing under the thumbstick or the jump button (touch controls %s) (%d)", tag,
						tostring(GuiService.TouchControlsEnabled), #under), table.concat(under, "; ", 1, math.min(#under, 8)))
					U9.close()
				end)
			end
		end
		Theme.Measure = mockMeasure
		LKC.flushErrors("care_family_fits_phone")
	end)

	-- (U9-5) one colour by role in the Care family: at most one green action in a window. The Training Place's four TRAIN
	-- buttons are peers (stone), the Food Machine's one green is its next step, the garden picker has none, the Fusion
	-- Machine's is FUSE!, the pet picker has none
	S.care_family_one_green = guarded("care_family_one_green", function()
		U8.at(1920, 1080, false, "care family one green", function(tag)
			for _, f in ipairs(U9.FAMILY) do
				U9.open(f[1])
				local greens = U8.greenActions(U8.pg():FindFirstChild(f[2]))
				local ok = #greens <= 1
				if f[1] == "train" or f[1] == "garden" or f[1]:match("^picker") then
					ok = #greens == 0
				elseif f[1]:match("^fusion") then
					ok = #greens == 0 or (#greens == 1 and greens[1] == "FuseButton")
				end
				T.check(ok, tag .. ": " .. f[1] .. " has at most its one green action", table.concat(greens, ", "))
				U9.close()
			end
		end)
		-- (U9-5 review) the Feed buttons are stone peers, so a feed the basket cannot pay for says so on its own: its price in
		-- Theme.Sign.RedLip (as Train's short TRAIN), still pressable; a feed the basket holds has no red. Every row at 0
		-- berries is short, none at a full basket
		U8.at(1920, 1080, false, "care feed short look", function(tag)
			local Theme = LoadingH.shared("Theme")
			local LP = game:GetService("Players").LocalPlayer
			local red = '<font color="#' .. string.format("%02x%02x%02x", math.floor(Theme.Sign.RedLip.R * 255 + 0.5),
				math.floor(Theme.Sign.RedLip.G * 255 + 0.5), math.floor(Theme.Sign.RedLip.B * 255 + 0.5)) .. '">'
			local old = LP:GetAttribute("Berries")
			U8.feed(nil, nil, nil, { Garden = 1, Kitchen = 2 }) -- the Food Machine built: the Feed buttons show their price
			U9.open("feed")
			local function feeds()
				local out = {}
				local gui = U8.pg():FindFirstChild("NimbusCare")
				for _, d in ipairs(gui and gui:GetDescendants() or {}) do
					if d:IsA("TextButton") and d.Name == "Feed" and d.Parent and d.Parent.Name == "Buttons" then
						local cost = d.Text:gsub("<[^>]->", ""):match("^Feed  ([%d,]+) berries")
						if cost then
							out[#out + 1] = { Button = d, Cost = tonumber((cost:gsub(",", ""))) }
						end
					end
				end
				return out
			end
			for _, case in ipairs({ { 0, true }, { 10 ^ 9, false } }) do
				LP:SetAttribute("Berries", case[1])
				LKC.advance(1)
				local rows, wrong = feeds(), {}
				for _, r in ipairs(rows) do
					local marked = r.Button.RichText and r.Button.Text:lower():find(red, 1, true) ~= nil
					if marked ~= case[2] or r.Button:GetAttribute("Disabled") == true then
						wrong[#wrong + 1] = fmt("%s %q (cost %d)", r.Button.Parent.Parent.Name, r.Button.Text, r.Cost)
					end
				end
				T.check(#rows > 0 and #wrong == 0, fmt("%s: at %d berries every priced Feed %s the red short price and stays pressable (%d rows)", tag,
					case[1], case[2] and "carries" or "has no", #rows), table.concat(wrong, "; ", 1, math.min(#wrong, 6)))
			end
			LP:SetAttribute("Berries", old)
			LKC.advance(0.5)
			U9.close()
			U8.feed()
		end)
		LKC.flushErrors("care_family_one_green")
	end)

	-- (U9-6; the GATE_KITB render gate's battle findings) the battle family fits every screen. At 844x390 and 390x844 (touch)
	-- every view of the family (U96.FAMILY): each shown text and button is whole on the screen, never cut by a clipping
	-- frame above it (a bar's text copies, TextFill / TextTrail / TextTrack, are cut at the fill's edge on purpose), every
	-- one-line text fits its box at FredokaOne's / LuckiestGuy's real widths (other faces through Theme.MeasureLabel) with 2
	-- px to spare, and nothing sits under Roblox's thumbstick or jump button unless the view hid them. At every grid size:
	-- no text is drawn under the readability floor (15 px on a screen 1000 px tall or more, 14 below) and none is TextScaled
	-- (a scaled text's drawn size is the font engine's guess: the HUD sizes its names itself), and the enemy list (its
	-- TARGET tab too) stays clear of the HUD's currency strips
	S.battle_family_fits = guarded("battle_family_fits", function()
		local Theme = LoadingH.shared("Theme")
		local GuiService = game:GetService("GuiService")
		local RealWidth = SmokeCommon.RealWidth
		if not T.check(_G.P5BattleH ~= nil, "battle family fits: (setup) smoke_p5_battleclient's battle driver is loaded") then
			return
		end
		local function width(o)
			local text = o.Text
			if o.RichText then
				text = text:gsub("<[^>]->", "")
			end
			local role = o:GetAttribute("FontRole")
			if role and Theme.CapsRoles[role] then
				text = Theme.Caps(text)
			end
			local w = RealWidth(text, o.TextSize, Theme.FontOf(o), true)
			return (w or Theme.MeasureLabel(o).X) * U8.scaleOf(o)
		end
		local SPLIT = { TextFill = true, TextTrail = true, TextTrack = true }
		local function clipper(o)
			local cur = o.Parent
			while cur and not cur:IsA("LayerCollector") do
				if cur:IsA("GuiObject") and cur.ClipsDescendants and not SPLIT[cur.Name] then
					return cur
				end
				cur = cur.Parent
			end
			return nil
		end
		local function inside(a, b)
			return a.X >= b.X - 1 and a.R <= b.R + 1 and a.Y >= b.Y - 1 and a.B <= b.B + 1
		end
		local function texty(d)
			return (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.TextTransparency < 1
		end
		for _, s in ipairs(U8.SIZES) do
			local W, Hh, touch = s[1], s[2], s[3]
			local floorPx = (Hh >= 1000) and 15 or 14
			for _, f in ipairs(U96.FAMILY) do
				U8.at(W, Hh, touch, "battle family " .. f[1], function(tag)
					U96.open(f[1])
					local gui = U8.pg():FindFirstChild(f[2])
					if not T.check(U96.showing(gui), tag .. ": the view shows (" .. f[2] .. ")") then
						U96.close()
						return
					end
					local dy = gui.IgnoreGuiInset and 0 or Mock.TopInset
					local screen = { X = 0, Y = -dy, R = W, B = Hh - dy }
					local small, scaled = {}, {}
					local off, cut, tight, under = {}, {}, {}, {}
					local zones = {}
					if touch and GuiService.TouchControlsEnabled ~= false then
						zones[1] = { X = 25, Y = Hh - 90 - dy, R = 95, B = Hh - 20 - dy, Name = "thumbstick" }
						zones[2] = { X = W - 115, Y = Hh - 90 - dy, R = W - 45, B = Hh - 20 - dy, Name = "jump" }
					end
					for _, d in ipairs(gui:GetDescendants()) do
						local tx = texty(d)
						if (tx or d:IsA("GuiButton")) and U8.shown(d) and d.AbsoluteSize.X > 0 then
							local name = d:GetFullName():gsub("^.-" .. f[2] .. "%.", "")
							if tx then
								local px = d.TextSize * U8.scaleOf(d)
								if d.TextScaled then
									scaled[#scaled + 1] = name
								elseif px < floorPx - 0.01 then
									small[#small + 1] = fmt("%s %q %.1f px", name, d.Text, px)
								end
							end
							do -- (every size: the gate's clipped HP text and the TARGET tab's overflow were on the desktop)
								local r = U8.rect(d)
								if not inside(r, screen) then
									off[#off + 1] = name .. " " .. U8.show(r)
								end
								local c = clipper(d)
								if c and not inside(r, U8.rect(c)) then
									cut[#cut + 1] = name .. " " .. U8.show(r) .. " in " .. c.Name .. " " .. U8.show(U8.rect(c))
								end
								if tx and not d.TextWrapped and not d.TextScaled then
									local pad = d:FindFirstChildOfClass("UIPadding")
									local inset = pad and (pad.PaddingLeft.Offset + pad.PaddingRight.Offset) * U8.scaleOf(d) or 0
									local w = width(d)
									if w + inset + 2 > d.AbsoluteSize.X + 0.01 then
										tight[#tight + 1] = fmt("%s %q %.0f px in %.0f", name, d.Text, w + inset, d.AbsoluteSize.X)
									end
								end
								for _, z in ipairs(zones) do
									if U8.overlap(r, z) then
										under[#under + 1] = name .. " under the " .. z.Name
									end
								end
							end
						end
					end
					T.check(#small == 0, fmt("%s: every text at %d px or more on the screen (%d)", tag, floorPx, #small), table.concat(small, "; ", 1, math.min(#small, 8)))
					T.check(#scaled == 0, fmt("%s: no TextScaled text (%d)", tag, #scaled), table.concat(scaled, "; ", 1, math.min(#scaled, 8)))
					T.check(#off == 0, fmt("%s: every text and button is on the screen (%d)", tag, #off), table.concat(off, "; ", 1, math.min(#off, 8)))
					T.check(#cut == 0, fmt("%s: no text or button cut by a clipping frame (%d)", tag, #cut), table.concat(cut, "; ", 1, math.min(#cut, 8)))
					T.check(#tight == 0, fmt("%s: every one-line text fits its box (%d)", tag, #tight), table.concat(tight, "; ", 1, math.min(#tight, 8)))
					if touch then
						T.check(#under == 0, fmt("%s: nothing under the thumbstick or the jump button (touch controls %s) (%d)", tag,
							tostring(GuiService.TouchControlsEnabled), #under), table.concat(under, "; ", 1, math.min(#under, 8)))
					end
					-- the enemy list (with the TARGET tab on its locked row) clear of the currency strips
					local enemies = gui:FindFirstChild("Enemies", true)
					local hud = U8.pg():FindFirstChild("NimbusHud")
					local over = {}
					if enemies and U8.shown(enemies) then
						for _, strip in ipairs(hud and hud:GetDescendants() or {}) do
							if strip.Name:match("^Currency_") and strip:IsA("GuiObject") and U8.shown(strip) then
								local sr = U8.rect(strip)
								sr = { X = sr.X, R = sr.R, Y = sr.Y + (hud.IgnoreGuiInset and 0 or Mock.TopInset) - dy, B = sr.B + (hud.IgnoreGuiInset and 0 or Mock.TopInset) - dy }
								for _, d in ipairs(enemies:GetDescendants()) do
									if d:IsA("GuiObject") and U8.shown(d) and d.BackgroundTransparency < 1 and U8.overlap(U8.rect(d), sr) then
										over[#over + 1] = d.Name .. " " .. U8.show(U8.rect(d)) .. " on " .. strip.Name .. " " .. U8.show(sr)
									end
								end
							end
						end
					end
					T.check(#over == 0, fmt("%s: the enemy list and its TARGET tab stay clear of the currency strips (%d)", tag, #over), table.concat(over, "; ", 1, math.min(#over, 6)))
					-- kit B's contrast rule on this view (3:1 from 18 px, 4.5:1 below; the family has no backlog lines left)
					-- (the walk reads the whole PlayerGui, so the screens under the view are its backdrop; only this view's texts count)
					local all, read, low = SmokeCommon.Contrast.Walk(U8.pg()), 0, {}
					for _, line in ipairs(all) do
						if line:sub(1, #f[2] + 1) == f[2] .. "." then
							low[#low + 1] = line
						end
					end
					for _, d in ipairs(gui:GetDescendants()) do
						read = read + (texty(d) and U8.shown(d) and 1 or 0)
					end
					T.check(read > 0 and #low == 0, fmt("%s: every text reads on its fill (%d read, %d not)", tag, read, #low), table.concat(low, "; ", 1, math.min(#low, 6)))
					U96.close()
				end)
			end
		end
		LKC.flushErrors("battle_family_fits")
	end)

	-- (U8) CloudUI.Panel's Signboard skin (Skin = "Signboard"; the Pets window and the Index wear it): the flat pink awning at a
	-- FIXED size centred on the top (never stretched with the window: Gemini's sign rule), the navy header plank in its wood
	-- rim with the title in gold through Theme.StyleTitle (stamped TitleLook), the wood frame and the stone body, the red
	-- close block with the drawn X; Panel.Content where it always was (callers' layouts do not move); no glow, gradient or
	-- corner
	S.panel_signboard_skin = guarded("panel_signboard_skin", function()
		local Theme = LoadingH.shared("Theme")
		local Sign = Theme.Sign
		local CloudUI = U7.client("UI/CloudUI")
		local SK = LoadingH.shared("SignKit")
		local gui = Instance.new("ScreenGui")
		gui.Name = "U8PanelProbe"
		gui.Parent = U8.pg()
		local function build(w, h)
			return CloudUI.Panel({ Name = "Probe", Title = "Pets", Closable = true, Skin = "Signboard", Icon = "paw", Size = UDim2.fromOffset(w, h), Parent = gui })
		end
		local a, b = build(900, 600), build(1200, 760)
		local plain = CloudUI.Panel({ Name = "Plain", Title = "Pets", Size = UDim2.fromOffset(900, 600), Parent = gui })
		LKC.advance(0.1)
		for _, p in ipairs({ a, b }) do
			local root = p.Root
			local roof = root:FindFirstChild("Roof")
			T.check(roof and roof:GetAttribute("SignKit") == "Roof" and roof.Size.X.Scale == 0 and roof.Size.Y.Scale == 0, "panel skin: a SignKit roof of fixed offset size")
			local head = nil
			for _, d in ipairs(root:GetDescendants()) do
				head = head or (d:GetAttribute("SignKit") == "Header" and d or nil)
			end
			local plate = head and head:FindFirstChild("Plate")
			T.check(head and head:GetAttribute("SignKit") == "Header" and plate and sameColor(plate.BackgroundColor3, Sign.Navy), "panel skin: the navy header plank (SignKit Header)")
			T.check(p.TitleLabel and sameColor(p.TitleLabel.TextColor3, Sign.Gold) and p.TitleLabel:GetAttribute("TitleLook") ~= nil and p.TitleLabel:GetAttribute("FontRole") == "Title",
				"panel skin: the title in gold, Title role, through Theme.StyleTitle", p.TitleLabel and hex(p.TitleLabel.TextColor3) or "no title")
			local icon = false
			for _, d in ipairs(root:GetDescendants()) do
				icon = icon or d:GetAttribute("PixelIcon") == "paw"
			end
			T.check(icon, "panel skin: the header carries the window's pixel icon (paw)")
			T.check(p.Body and sameColor(p.Body.BackgroundColor3, Sign.Wood) and p.Body.BackgroundTransparency < 0.05, "panel skin: the wood frame (Body)", p.Body and hex(p.Body.BackgroundColor3) or "")
			local stone = p.Body:FindFirstChild("Stone")
			T.check(stone and sameColor(stone.BackgroundColor3, Sign.Stone), "panel skin: the stone body inside the frame")
			T.check(p.CloseButton and U8.faceOf(p.CloseButton) and sameColor(U8.faceOf(p.CloseButton), Sign.Red) and p.CloseButton:FindFirstChild("CloseMark"),
				"panel skin: the red close block with the drawn X")
			local bad = {}
			for _, d in ipairs(root:GetDescendants()) do
				if designedLook(d) then
					-- (kit-b merge) the title's T1 ribbon (the owner's pick)
				elseif d:IsA("UIGradient") or d:IsA("UICorner") then
					bad[#bad + 1] = d.ClassName .. " on " .. d.Parent.Name
				elseif d.Name == "Glow" and d:IsA("GuiObject") and d.Visible then
					bad[#bad + 1] = "a glow on " .. d.Parent.Name
				end
			end
			T.check(#bad == 0, "panel skin: no gradient, corner or glow", table.concat(bad, ", "))
		end
		T.check(a.Root:FindFirstChild("Roof").Size == b.Root:FindFirstChild("Roof").Size, "panel skin: the roof keeps its size on a bigger window")
		T.check(a.Content.Position == plain.Content.Position and a.Content.Size == plain.Content.Size, "panel skin: Panel.Content sits where the plain panel's does")
		T.eq(SK.Sizes.RoofH, a.Root:FindFirstChild("Roof").Size.Y.Offset, "panel skin: the roof is the SignKit roof's height")
		gui:Destroy()
		LKC.flushErrors("panel_signboard_skin")
	end)

	-- (sign/logo review, SIGN2 renders) a header title's ribbon stays clear of its neighbours: at 390x844 and 844x390 the
	-- Shop, Pets, Training, Fusion, the pet picker and the Sky Trove are opened, and no piece of a visible ribbon (band,
	-- tails with their notches, underline, steps) may cross a visible sibling of the title (the Shop's egg icon, a tab or
	-- close button, a balance pill; a strip under the title's whole width and a thin rule of 4 px or less do not count) or
	-- a button of its window laid over the header (the Pets window's A/B/C),
	-- nor leave its window's frame by more than TailOver
	S.kitb_title_ribbon_clear = guarded("kitb_title_ribbon_clear", function()
		local Theme = LoadingH.shared("Theme")
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not T.check(Theme and Theme.TitleRibbon and pg, "kitb ribbon clear: Theme.TitleRibbon and PlayerGui exist") then
			return
		end
		local function client(path)
			local inst = Mock.GetPath(ROOTS.client .. "/" .. path)
			local ok, mod = false, nil
			if inst then
				ok, mod = pcall(require, inst)
			end
			return ok and type(mod) == "table" and mod or nil
		end
		local function shown(g)
			local p = g
			while p and not p:IsA("LayerCollector") do
				if p:IsA("GuiObject") and not p.Visible then
					return false
				end
				p = p.Parent
			end
			return p ~= nil and p.Enabled ~= false
		end
		local function rect(g)
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			return { p.X, p.Y, p.X + s.X, p.Y + s.Y }
		end
		local function cross(a, b)
			return math.min(a[3], b[3]) - math.max(a[1], b[1]) > 0.5 and math.min(a[4], b[4]) - math.max(a[2], b[2]) > 0.5
		end
		-- a strip that runs under the title's whole width (the header's band, its foot) is the plate the ribbon sits on
		local function spans(outer, inner)
			return outer[1] <= inner[1] + 0.5 and outer[3] >= inner[3] - 0.5
		end
		local problems, seen = {}, {}
		local function check(where)
			for _, l in ipairs(pg:GetDescendants()) do
				if l:IsA("TextLabel") and l:GetAttribute("TitleLook") == "Ribbon" and l.TextXAlignment ~= Enum.TextXAlignment.Center and shown(l) then
					local name = l:GetFullName():gsub("^Players%.[^.]+%.PlayerGui%.", "")
					seen[#seen + 1] = where .. " " .. name
					local own = rect(l)
					local k = (tonumber(l.TextSize) or 20) / Theme.TitleRibbon.Base
					local slack = math.max(1, math.floor(Theme.TitleRibbon.TailOver * k + 0.5))
					-- the window: the title's ancestor right under its ScreenGui
					local win = l
					while win.Parent and not win.Parent:IsA("LayerCollector") do
						win = win.Parent
					end
					local frame = rect(win)
					local pieces = {}
					for _, d in ipairs(l:GetDescendants()) do
						if d:IsA("Frame") and d.BackgroundTransparency < 1 and shown(d) then
							local r = rect(d)
							if r[3] - r[1] > 0 and r[4] - r[2] > 0 then
								pieces[#pieces + 1] = { d, r }
							end
						end
					end
					-- its siblings, and every button of its window laid over the header (the Pets window's A/B/C sit on
					-- the right end of the title's box on a phone)
					local near = l.Parent:GetChildren()
					for _, b in ipairs(win:GetDescendants()) do
						if b:IsA("GuiButton") and b.Parent ~= l.Parent and not b:IsDescendantOf(l) and shown(b) then
							near[#near + 1] = b
						end
					end
					for _, sib in ipairs(near) do
						if sib ~= l and sib:IsA("GuiObject") and sib.Visible then
							local r = rect(sib)
							if r[3] - r[1] > 4 and r[4] - r[2] > 4 and not spans(r, own) then
								for _, pc in ipairs(pieces) do
									if cross(pc[2], r) then
										problems[#problems + 1] = fmt("%s %s: %s crosses %s (title x %d..%d, piece x %d..%d, %s x %d..%d)", where, name, pc[1].Name, sib.Name,
											own[1], own[3], pc[2][1], pc[2][3], sib.Name, r[1], r[3])
										break
									end
								end
							end
						end
					end
					for _, pc in ipairs(pieces) do
						local r = pc[2]
						if r[1] < frame[1] - slack or r[3] > frame[3] + slack then
							problems[#problems + 1] = fmt("%s %s: %s leaves the window by %d px", where, name, pc[1].Name,
								math.floor(math.max(frame[1] - r[1], r[3] - frame[3])))
						end
					end
				end
			end
		end
		local old = { Mock.Viewport.X, Mock.Viewport.Y }
		local windows = {
			{ "Shop", function()
				client("Controllers/ShopController").Open({ Tab = "Eggs" })
			end, function()
				client("Controllers/ShopController").Close()
			end },
			{ "Pets", function()
				client("Controllers/MenuController").Open("Pets")
			end, function()
				client("Controllers/MenuController").Close()
			end },
			{ "Training", function()
				client("Controllers/TrainController").Open({})
			end, function()
				client("Controllers/TrainController").Close()
			end },
			{ "Fusion", function()
				client("Controllers/FusionController").Open("Upgrade", {})
			end, function()
				client("Controllers/FusionController").Close()
			end },
			{ "the pet picker", function()
				client("UI/PetPicker").Open({ Context = "Train", Title = "Pick a pet to train", OnPick = function() end, OnClose = function() end })
			end, function()
				client("UI/PetPicker").Close()
			end },
			{ "the Sky Trove", function()
				client("Controllers/TroveController").Open({})
			end, function()
				client("Controllers/TroveController").Close()
			end },
		}
		for _, size in ipairs({ { 390, 844 }, { 844, 390 } }) do
			Mock.SetViewport(size[1], size[2])
			LKC.advance(0.3)
			for _, w in ipairs(windows) do
				local ok, err = pcall(w[2])
				T.check(ok, "kitb ribbon clear: " .. w[1] .. " opens at " .. size[1] .. "x" .. size[2], tostring(err))
				LKC.advance(0.4)
				check(size[1] .. "x" .. size[2] .. " " .. w[1])
				pcall(w[3])
				LKC.advance(0.2)
			end
		end
		T.check(#seen >= 8, "kitb ribbon clear: (setup) the walk saw the header titles", table.concat(seen, "; "))
		T.check(#problems == 0, "kitb ribbon clear: no header ribbon crosses a neighbour of its title or leaves its window", table.concat(problems, "; "))
		Mock.SetViewport(old[1], old[2])
		LKC.advance(0.2)
		LKC.flushErrors("kitb_title_ribbon_clear")
	end)

	return S
end

if (ARGS and ARGS.context or "server") == "server" then
	return serverScenarios()
end
return clientScenarios()
