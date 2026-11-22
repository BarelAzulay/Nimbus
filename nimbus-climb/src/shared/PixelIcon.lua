-- PixelIcon: the kit B icon set (U2 of .superpowers/slop-audit/round3/BUILD_PLAN.md, findings 5 and 7; decisions 2 and 3).
-- Every icon is a 9 x 9 one-colour bitmap kept as data: nine rows of nine cells, "#" drawn and "." empty, rows joined by
-- "/". The first 27 are the pitch's own (kit_pitch_mockups.html:523-550, the `I` table), ported as they are so the icons in
-- the game are the ones the owner saw; the rest are the ones the loading screen, menu, settings and credits need.
--   PixelIcon.Bitmaps[name]            the bitmap string
--   PixelIcon.Runs(name)               its merged rectangles { { x, y, w, h }, ... } in cells (nil for an unknown name)
--   PixelIcon.New(parent, name, px, colour)  a transparent px x px Frame (attribute PixelIcon = name) holding one Frame per
--                                      merged rectangle, snapped to whole pixels (cell = floor(px / 9), centred); nil for
--                                      an unknown name. px under 9 draws at 9; a px between multiples of 9 warns once
--                                      (PixelIcon.Warned). (U9-7 look) Under a UIScale the cells are whole screen px
--                                      (round(cell x scale), attribute CellPx), refitted when that scale changes
--   PixelIcon.Fit(icon)                (U9-7 look) fits an icon to the UIScales above it now (New and moves do it)
--   PixelIcon.Snap(px)                 the multiple of 9 nearest px (at least 9): the size an icon for a px glyph draws at
--   PixelIcon.Host(host, name, px[, colour])  (U7a) the icon centred in a text object, following its TextColor3 (unless
--                                      colour), TextTransparency and ZIndex (and with px nil its TextSize): an icon a
--                                      caller treats as a glyph
--   PixelIcon.Lead(label, name[, opts]) (U7a) the icon in front of a label's text ("<coin> 1,250"), the text inset past it;
--                                      opts.After / Count / Of: a rating after the text ("Easy" + 3 lit stars of 5); opts.Gap;
--                                      opts.Room (render gate): a left-aligned label keeps the trailing icons' room inside
--                                      its box (its text truncates first, the icons never leave the box).
--                                      Placed from TextBounds, or Theme.MeasureLabel when that reads 0 (a server: world signs)
--   PixelIcon.Clear(label[, opts])     (U7b) takes a Lead icon off again (a row whose mark comes and goes), insets back
--   PixelIcon.Mark(label, name|nil[, opts])  (U7b) Lead / Clear only when the mark changed: a status line set each refresh
--   PixelIcon.Set(host, name|nil[, px])      (U7b) Host only when the icon changed (the text emptied): a glyph label
-- Runs: each row's horizontal runs, then runs with the same columns in the rows below merged into one taller rectangle,
-- so an icon is a handful of Frames (smoke: at most 25).
-- (Pitch 2 item 9 B "Carved soft", spec docs/superpowers/specs/2026-11-20-pitch2-build-design.md) the redrawn icons in
-- their own colours: the spec's 16 (note, token, gem, pot, egg, bag, gift, box, ticket, potion, paw, book, house, stats,
-- gear, signpost), the 7 rarity dots (rarity_<rarity>) and the 8 element badges (Config.Elements.Info[*].Icon):
--   PixelIcon.Art[name]                { R = 10 rows of 10 (the 9 x 9 glyph + its 1-cell drop shadow), P = letter -> hex }
--                                      (the generated block below; tools/build_upload_sheets.py)
--   PixelIcon.Own                      the colour to pass for "its own colours": New(parent, name, px, PixelIcon.Own)
--                                      draws Art[name] (one Frame per merged run of one colour; the drop shadow Text at
--                                      30 %, attribute BaseT 0.7); a name with no Art draws white, as with no colour
--   Host / Lead / Mark / Set           a caller that gives no colour gets an Art icon in its own colours (it follows the
--                                      text's transparency and ZIndex, not its colour); a caller that gives a colour, and
--                                      every one-ink glyph, get the Bitmaps drawing in that one ink, as before
--   the art sizes (36 px and up: 2+ px cells on an 18 grid) of the 16 come from ONE uploaded sheet once
--                                      Config.IconSheet.Id is set (build/upload_sheets/icons_b.png, PixelIcon.SheetCells):
--                                      the icon Frame (attribute Sheet) holds one ImageLabel "Art" cut by ImageRectOffset /
--                                      ImageRectSize (19 x 19: the 18 x 18 art + its drop shadow), ResampleMode Pixelated,
--                                      19 cells of px / 18 on whole screen px. With no id (0, shipping) they draw the 9 x 9
--                                      glyph (54 px: 6 px cells): Review Focus 2, no image, no empty box
--   PixelIcon.Grey(icon, on)           the disabled state: the sheet's greyed row, or every colour of the 9 x 9 glyph to
--                                      its grey twin (the sheet's rule); off gives the colours back
-- Requires nothing at load (Shared, usable from ReplicatedFirst); Lead requires Theme (its sibling) on the first text it
-- must measure itself (U7b review: a server's TextBounds read 0), and an art-size Own icon reads Config (its sibling) for
-- the sheet's id when it draws (a loading screen before Config arrives draws the 9 x 9 glyph). Plain Lua 5.1-compatible
-- syntax only.

local PixelIcon = {}

PixelIcon.Bitmaps = {
	-- the pitch's icons (kit_pitch_mockups.html, exactly as drawn there)
	paw = "..##.##../..##.##../##.....##/##.###.##/..#####../.#######./.#######./..##.##../.........",
	book = "........./###...###/####.####/####.####/####.####/####.####/####.####/.###.###./.........",
	house = "....#..../...###.../..#####../.#######./#########/.#######./.##...##./.##...##./.##...##.",
	stats = "........./......##./......##./...##.##./...##.##./##.##.##./##.##.##./##.##.##./.........",
	bag = "...###.../..#...#../.#######./#########/#########/#########/#########/#########/.#######.",
	arrow = "........./....#..../....##.../#######../########./#######../....##.../....#..../.........",
	gear = "...###.../.#.###.#./.#######./###...###/###...###/###...###/.#######./.#.###.#./...###...",
	heart = "........./.##...##./####.####/#########/#########/.#######./..#####../...###.../....#....",
	bolt = ".....###./....###../...###.../..######./....###../...###.../..###..../.##....../.........",
	note = "........./........./#########/#.......#/#..###..#/#..###..#/#.......#/#########/.........", -- a banknote (cash)
	coin = "..#####../.#######./####.####/####.####/####.####/####.####/####.####/.#######./..#####..",
	gem = "........./.#######./#########/#########/.#######./..#####../...###.../....#..../.........",
	gift = ".##...##./#..#.#..#/.#######./#########/#########/.###.###./.###.###./.###.###./.###.###.",
	check = "........./........#/.......##/#.....##./##...##../.##.##.../..###..../...#...../.........",
	x = "........./.##...##./.###.###./..#####../...###.../..#####../.###.###./.##...##./.........",
	sword = "......###/.....####/....####./...####../#.####.../.####..../..##...../.#.##..../#...#....",
	star = "....#..../....#..../...###.../#########/.#######./..#####../..#####../.##...##./.#.....#.",
	-- (Pitch 2 items 9 B + 12_elements A) the three-tongue flame with a hollow core: the pitch's flame was a drop with a
	-- notch, so Water -> Flame read as drop -> drop
	flame = "....#..../.#..##.../.#..##.#./.##.####./#########/####.####/###...###/.##...##./..#####..",
	flake = "....#..../.#..#..#./..#.#.#../...###.../#########/...###.../..#.#.#../.#..#..#./....#....",
	moon = "...####../..###..../.###...../.###...../.###...../.###...../.####...#/..######./...####..",
	cloud = "........./...##..../..####.#./.#######./#########/#########/.#######./........./.........",
	apple = ".....##../....#..../.###.###./#########/#########/#########/#########/.#######./..##.##..",
	bell = "........./........./##.....##/##.....##/#########/##.....##/##.....##/........./.........",
	sprout = "........./###...###/####.####/.###.###./...###.../....#..../....#..../..#####../.#######.",
	plus = "...###.../...###.../...###.../#########/#########/#########/...###.../...###.../...###...",
	dash = "........./##..##.../.##..##../..##..##./...##..##/..##..##./.##..##../##..##.../.........",
	down = "........./........./##.....##/###...###/.###.###./..#####../...###.../....#..../.........",

	-- the screens' icons (U2): loading, menu, settings, credits
	play = ".#......./.###...../.#####.../.#######./.########/.#######./.#####.../.###...../.#.......",
	scroll = ".#######./#########/.#.....#./.#.###.#./.#.....#./.#.###.#./.#.....#./#########/.#######.",
	music = "...######/...######/...#....#/...#....#/...#....#/.###..###/####.####/####.####/.##...##.", -- a musical note
	speaker = "....#..../...##..#./..###...#/#####.#.#/#####.#.#/#####.#.#/..###...#/...##..#./....#....",
	monitor = "#########/#.......#/#.......#/#.......#/#.......#/#########/....#..../...###.../.#######.",
	shake = "#.#...#.#/...###.../#########/###...###/##..#..##/###...###/#########/........./#.#...#.#", -- camera shake
	mouse = "....#..../..#####../.##.#.##./.##.#.##./.#######./.#######./.#######./.#######./..#####..",
	bulb = "..#####../.#######./##..#####/##.######/.#######./..#####../........./..#####../...###...", -- a tip
	swap = "........./.....#.../########./.....#.../........./...#...../.########/...#...../.........",
	token = "..#####../.#######./####.####/###...###/##.....##/##.....##/#########/.#######./..#####..", -- the Cloud Token coin
	-- (U5) the settings scale's - (the pitch's plus without its upright)
	minus = "........./........./........./#########/#########/#########/........./........./.........",

	-- (U7a) the tiles' and the shop's icons the pitch did not draw (Config.Icons, NeonKit.Icon), in the pitch's style:
	-- solid shapes, a one-cell gap for every inner line
	pack = "..#####../.##...##./.#######./#########/##.....##/##.###.##/##.###.##/##.....##/.#######.", -- a backpack (Items)
	shield = ".#######./####.####/####.####/#.......#/####.####/.###.###./.###.###./..##.##../...###...", -- the Team
	trophy = "#########/#.#####.#/#.#####.#/.#######./..#####../...###.../....#..../..#####../.#######.", -- the Arena
	mountain = "...#...../..###..../..###.#../.#######./.########/#########/#########/#########/.........", -- the Obby (two peaks)
	key = "..####.../.##..##../.##..##../..####.../...##..../...####../...##..../...###.../...##....", -- the Dungeon
	crown = "........./#...#...#/##.###.##/#########/#########/#.#.#.#.#/#########/........./.........", -- the Ring, VIP
	sparkle = "....#..../....#..../...###.../..#####../#########/..#####../...###.../....#..../....#....", -- Fusion
	lock = "..#####../.##...##./.##...##./.##...##./#########/####.####/###...###/####.####/#########",
	box = "........./##.....##/###...###/#########/####.####/####.####/####.####/#########/.........", -- Packs
	ticket = "........./#########/##.######/.#######./.#.#####./.#######./##.######/#########/.........", -- Passes (notches, a torn line)
	potion = "...###.../....#..../....#..../..#####../.##...##./#########/#########/#########/.#######.", -- Boosts
	-- the Roulettes: the gumball globe (two off-centre balls so it never reads as a face), its neck and a solid base
	gumball = "..#####../.##.####./.#######./.####.##./..#####../...###.../..#####../.#######./#########",
	egg = "...###.../..#####../.#######./.#######./#########/#########/#########/.#######./..#####..",
	wrench = ".##..##../.##..##../.######../..####.../...##..../...##..../...##..../...##..../...##....", -- Repair
	chest = "........./.#######./#########/#########/........./###...###/####.####/#########/#########", -- the Sky Trove
	people = ".##...##./####.####/.##...##./........./.###.###./####.####/####.####/####.####/.........", -- the Trove's group
	clock = "..#####../.###.###./####.####/####.####/####...##/#########/#########/.#######./..#####..", -- a play-time tier

	-- (U7b) the battle HUD's elements and actions, the dungeon, the Training Place and the Home window's stations (the
	-- emoji they replace in brackets), same style
	drop = "....#..../....#..../...###.../..#####../.#######./.##.####./.#######./..#####../.........", -- Water
	leaf = ".....####/...######/..####.##/.####.###/.###.####/.##.####./..####.../.#......./#........", -- Nature
	target = "..#####../.#.....#./#..###..#/#.#...#.#/#.#.#.#.#/#.#...#.#/#..###..#/.#.....#./..#####..", -- the Target button
	skull = "..#####../.#######./#########/##..#..##/##..#..##/####.####/.#######./..#.#.#../..#####..", -- a dungeon boss room
	hourglass = "#########/.#######./..#####../...###.../....#..../...#.#.../..#...#../.#######./#########", -- a wait
	glass = ".####..../##..##.../#....#.../#....#.../##..##.../.####.#../......##./.......##/........#", -- search
	castle = "#.#.#.#.#/#########/#########/##.###.##/#########/####.####/###...###/###...###/###...###", -- the Sky Castle
	berry = "...#.#.../..#####../.#######./##.###.##/#########/.###.###./.#######./..#####../...###...", -- the Berry Farm
	pot = "..#.#.#../..#.#.#../........./#########/#########/.#######./.#######./..#####../.##...##.", -- the Food Machine
	weight = "..#####../.#.....#./.#.....#./..#####../.#######./#########/#########/#########/.#######.", -- training (a kettlebell: a dumbbell read as an H)
	vault = "#########/#.......#/#..###..#/#.#...#.#/#.#.#.#.#/#.#...#.#/#..###..#/#########/.#.....#.", -- the Vault
	fence = ".#..#..#./.#..#..#./#########/.#..#..#./.#..#..#./#########/.#..#..#./.#..#..#./.........", -- the Yard Fence
	fountain = "....#..../..#.#.#../.#..#..#./....#..../..#####../....#..../#########/#########/.#######.", -- the Fountain
	basket = "...###.../..#...#../.#.....#./#########/#.#.#.#.#/#########/.#.#.#.#./.#######./.........", -- the berry basket
	pip = "........./........./..#####../..#####../..#####../..#####../..#####../........./.........", -- a progress pip
	up = "........./....#..../...###.../..#####../.###.###./###...###/##.....##/........./.........", -- a bounce pad (down, turned)
	left = "........./....#..../...##..../..#######/.########/..#######/...##..../....#..../.........", -- the D-pad left (arrow, turned)
	shift = "....#..../...###.../..##.##../.##...##./####.####/..##.##../..##.##../..#####../.........", -- the Shift key (hollow up arrow)
	-- (LOOK-ui) the vitals' downed mark (was the "!" letter on the heart tile)
	bang = "...###.../...###.../...###.../...###.../...###.../....#..../........./...###.../...###...",
	-- (LOOK-ui, kitb-look1) a narrow pointer, three cells wide: at 18 px (2 px cells, the screen's own size) it fits the
	-- ~14 px gap between two tiles that "play" (8 cells) at 9 px (1 px cells) filled
	nub = "........./........./...#...../...##..../...###.../...##..../...#...../........./.........",
	-- (Pitch 2 item 12_elements A, the wheel's links) the arrow turned to the other 90 degree ways, and the 45 degree ones on
	-- even stairs (one cell a row: the mock's kitb_lib.draw_cell_arrow), never a rotated frame (a turned icon draws soft)
	arrowdown = "...###.../...###.../...###.../...###.../.#######./..#####../...###.../....#..../.........",
	arrowup = "........./....#..../...###.../..#####../.#######./...###.../...###.../...###.../...###...",
	arrowse = "##......./###....../.###..##./..###.##./...#####./....####./..######./..######./.........",
	arrowsw = ".......##/......###/.##..###./.##.###../.#####.../.####..../.######../.######../.........",
	arrowne = "........./..######./..######./....####./...#####./..###.##./.###..##./###....../##.......",
	arrownw = "........./.######../.######../.####..../.#####.../.##.###../.##..###./......###/.......##",
}
-- BEGIN GENERATED icons_b (tools/build_upload_sheets.py; do not edit by hand: change tools/pixelart/icons_b.py and
-- run the script). Pitch 2 item 9 B "Carved soft": every redrawn icon's 9 x 9 glyph in its own colours, 10 x 10
-- rows (the glyph + its 1-cell drop shadow on the right and bottom); one letter a colour of P ("~": the drop
-- shadow, Text at 30 %), "." empty. L: the Frames that draw it, bottom first, 5 characters each: x, y, w, h
-- (base 36, in cells) and the letter; the shadow first, then each colour over the ones drawn after it
PixelIcon.Art = {
	note = { R = "........../aaaaaaaab./acccccccd~/aceedeead~/acedfdead~/aceedeead~/aaaaaaaad~/bdddddddd~/.~~~~~~~~~/..........", P = { a = "3F9A45", b = "2A6E34", c = "ACEA98", d = "184A26", e = "6FCF6A", f = "F0FFEC" }, L = "1297~0186a2353e1781d8215d4313d3431d4411f1271c1313c8111b0711b" }, -- Cash
	token = { R = "..aaaab.../.accccdb../acedddddb./acddcadaf~/acddcadaf~/adddcadaf~/bddddddaf~/.bdaaaaf~~/..bffff~~./...~~~~~..", P = { a = "F2A93B", b = "AA7022", c = "FFE58A", d = "FFD24A", e = "FFFCEC", f = "70420E" }, L = "8325~3852~8811~2059b0295b1177b1275d2157d8314f3841f7711f2211e2041a0214a7314a3741a5313a1111a2141c1213c4313c" }, -- Tokens
	gem = { R = "........../..aaaab.../.acdcceb../acceeeeaf./.beeeaaf~~/..beaaf~~./...baf~~../....f~~.../.....~..../..........", P = { a = "3A8FCB", b = "2760A1", c = "BEEAFF", d = "FFFFFF", e = "6CC4F5", f = "183A7E" }, L = "7422~5622~9411~7611~5811~1273b2155b3611b1252c2141a4432a1211a0311a7311a4611a3211d8311f7411f6511f5611f4711f3341e2431e6211e3511e" }, -- Gems
	pot = { R = "....ab..../.cd.e~cd../cfcghcfcd./dcghihccg~/.dgjjjdg~~/kklllllkm./.nkkkkkm~~/..nmmmm~~./...~~~~~../..........", P = { a = "2C7636", b = "143E20", c = "B8364F", d = "90263D", e = "1F572A", f = "FFF2F4", g = "70182E", h = "7354C4", i = "FAF6FF", j = "382276", k = "DCC9A0", l = "FFFDF6", m = "745632", n = "A38A64" }, L = "3752~8322~8621~5111~8711~1461d0292d2111d7111d1611n2711n2223g8311g7411g2562k0521k4011a2551l5232c1113c0231c6111c3741m8511m7611m1211f6211f3331h4211h4311i4111e3431j5011b" }, -- Food
	egg = { R = "...aab..../..acdab.../..adeaf~../.adeegab../.adeeeaf~./.ageeeaf~./.adeegaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "DEC49A", b = "9D815F", c = "FFFFFF", d = "FFFAEE", e = "FAECCE", f = "684A2E", g = "6CC4F5" }, L = "3258~8415~1375b2158b5011b3247f7414f2355a1314a2142a3021a2314d3122d5314g2511g3324e5412e4211e3111c" }, -- Eggs
	bag = { R = "aaaaaaaab./acdcdcdce~/afafafafe~/e~e~e~e~e~/.g.~.~.g.~/.h~....h~./iiiiiiiij./igkkkkkkl~/jh~~~~~hl~/.~~.....~~", P = { a = "C44A82", b = "9B3868", c = "DCC9A0", d = "F8ACD0", e = "7A2A52", f = "745632", g = "5E3A1B", h = "3A220E", i = "8C5A2E", j = "663E1C", k = "4A2D14", l = "46280E" }, L = "2782~1193~1921~8921~3411~5411~9411~2511~8511~1514h7514h8011b8113e0311e2311e4311e6311e8611j0811j0083a8712l1171c2111d4111d6111d2761k1211f3211f5211f7211f1411g7411g1711g0681i0711i" }, -- Shop
	gift = { R = "..ab.ab.../.a.~a.~a../cccdacccd./dcceaccce~/.ffgaffg~~/.ffeaffe~./.ffeaffe~./.geebgee~./..~~~~~~~./..........", P = { a = "F2A93B", b = "70420E", c = "CC4660", d = "992D44", e = "70182E", f = "B8364F", g = "90263D" }, L = "2475~9312~3111~6111~1474g2523e6523e3361e3011b6011b4711b3261d0311d5232c1222c0211c1423f5423f4116a2011a5011a1111a7111a" }, -- Gift
	box = { R = "....a...../...aab..../aaacdaaae./.baaeaae~~/..be~be~~./ffgffgffh./fijjijjkl~/ffffffffm~/hmmmmmmmm~/.~~~~~~~~~", P = { a = "F2A93B", b = "AA7022", c = "FFE58A", d = "FFFCEC", e = "70420E", f = "B27E42", g = "F0CC92", h = "83592A", i = "FFFDF6", j = "FFF7E6", k = "DCC9A0", l = "745632", m = "5C3A16" }, L = "1694~4352~9311~3211c4211d0583f1641i7611k8611l2511g5511g8511h0811h2621j5621j1881m8711m5114b1311b2411b4341e8211e3411e6411e5222a0231a4012a2321a3111a7211a" }, -- Packs
	ticket = { R = "........../........../aaaaaaaab./bacdcceae~/.adfghae~~/aaaiaaeab./beeeeeeee~/.~~~~~~~~~/........../..........", P = { a = "7354C4", b = "533899", c = "D0BEF8", d = "FFE58A", e = "382276", f = "FFFCEC", g = "FFD24A", h = "A98BEA", i = "F2A93B" }, L = "1692~8322~0292b0592b4411g5411h1681e6323e8311e0281a0561a1312a7311a6411a7511a3511i2322d4321c2311c3411f" }, -- Passes
	potion = { R = "...aab..../...ccd~.../...ccd~.../..cccce.../.cfddddd../.ghhhhgi~./.gjkkkji~./.lgggggi~./..liiii~~./...~~~~~..", P = { a = "5E3A1B", b = "4A2D14", c = "9CC8E4", d = "466C96", e = "6D95B9", f = "FFFFFF", g = "C44A82", h = "F8ACD0", i = "7A2A52", j = "FFF0F8", k = "EE6FA6", l = "9B3868" }, L = "3852~8514~6112~3021a5011b6311e2411f1563g2541h2651j3631k3451d5112d3841i7513i1711l2811l3123c2341c1411c" }, -- Boosts
	paw = { R = "..ab.ab.../..bc~bc~../ab.~~.~ab./bc~dde.bc~/.~dffde.~~/.dfagade../.eddhddh~./..eh~eh~~./...~~.~~../..........", P = { a = "B5763C", b = "5E3A1B", c = "3A220E", d = "8C5A2E", e = "663E1C", f = "D69C5C", g = "F6D6A0", h = "46280E" }, L = "3128~8322~7622~6821~6122~1322~5315e1572e6411e2711e2022b5022b0222b7222b3111c6111c1311c8311c2432f3531a2011a5011a0211a7211a4641h3711h6711h3321d6512d2621d2411d5411d1511d5611d4511g" }, -- Pets
	book = { R = ".abbbbbc../.adeeeef~./.aeeggef~./.aeehgef~./.aeeeeef~./.abbbbbf~./.aiiiiij~./.kffffff~./..~~~~~~~./..........", P = { a = "8C243A", b = "B8364F", c = "90263D", d = "FAA6B2", e = "EE6A7F", f = "70182E", g = "FFD24A", h = "FFFCEC", i = "DCC9A0", j = "745632", k = "6B1A2D" }, L = "2178~1017a2167f2056b2154e1711k7011c2651i4222g4311h2111d7611j" }, -- Index
	house = { R = "....a...../...aab..../..acdab.../.acdddab../aaaaaaaae./.ffffffg~~/.fhijjfk~./.fffllfk~./.gkkmmkk~./..~~~~~~~.", P = { a = "B8364F", b = "90263D", c = "FAA6B2", d = "EE6A7F", e = "70182E", f = "DCC9A0", g = "A38A64", h = "BEEAFF", i = "FFFDF6", j = "B5763C", k = "745632", l = "5E3A1B", m = "3A220E" }, L = "2575~9511~2663k2222c7511g1811g1563f0481a4012a5222a3111a2211a1311a4621j5111b6211b7311b2611h3331d4211d4821m8411e3611i4721l" }, -- Home
	stats = { R = "......aab./......aac~/...ddefac~/...ddgfac~/hhijdgfac~/hhkddgaac~/ikkgggccc~/lmmmmmmmm~/.~~~~~~~~~/..........", P = { a = "7354C4", b = "533899", c = "382276", d = "3F9A45", e = "2A6E34", f = "D0BEF8", g = "184A26", h = "3A8FCB", i = "2760A1", j = "ACEA98", k = "183A7E", l = "4A2D14", m = "3A220E" }, L = "1495~9113~1522k6026a8011b8116c6621c1781m5211e0711l6213f3334g2411i0611i0422h3224d3411j" }, -- Stats
	gear = { R = "...aab..../.a.aac~a../.aacccac~./aac~~~aab./aac~..aac~/bac~..aac~/.acaaacc~~/.c~aac~c~./..~bcc~.~./....~~~...", P = { a = "5D6670", b = "424952", c = "2C323A" }, L = "4733~2326~8423~4133~8712~8211~5011b8311b0511b3811b6224a1116a3632a3022a0312a7111a2211a2314c3231c8412c6621c5712c5111c7211c1711c7711c4811c" }, -- Settings
	signpost = { R = "....a...../bbbbbbc.../bdddedbc../bdeeeeebf./bbbbebbf~~/cfffbff~~./.~~~g~~~../....a~..../..hijik.../...~~~~~..", P = { a = "4A2D14", b = "8C5A2E", c = "663E1C", d = "D69C5C", e = "B5763C", f = "46280E", g = "5E3A1B", h = "2C7636", i = "1F572A", j = "3A220E", k = "143E20" }, L = "1572~3951~8421~8511~5711~4611g3831i0175b7311b4011a4711a6111c7211c0511c1252d1531f5521f8311f7411f2351e4213e2811h4811j6811k" }, -- Travel
	rarity_common = { R = "........../...aab..../..acdab.../.aceeeab../.adeeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "808595", b = "666777", c = "F3F4F6", d = "CDD2DC", e = "A8B2C2", f = "504E5F" }, L = "7423~4732~7711~3137b1373b2255b2222c3344a3121a1312a2211a5211a2511a4211d2411d7412f4721f6611f3333e" }, -- Common
	rarity_uncommon = { R = "........../...aab..../..acdab.../.aceeeab../.adeeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "529266", b = "447054", c = "EAF7ED", d = "A7DDB5", e = "68C480", f = "385446" }, L = "7423~4732~7711~3137b1373b2255b2222c3344a3121a1312a2211a5211a2511a4211d2411d7412f4721f6611f3333e" }, -- Uncommon
	rarity_rare = { R = "........../...aab..../..acdab.../.aceeeab../.adeeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "4776B1", b = "3B5C8C", c = "E8F1FC", d = "9EC7F2", e = "589EE8", f = "32466D" }, L = "7423~4732~7711~3137b1373b2255b2222c3344a3121a1312a2211a5211a2511a4211d2411d7412f4721f6611f3333e" }, -- Rare
	rarity_epic = { R = "........../...aab..../..acdab.../.aceeeab../.adeeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "8652B1", b = "6A418C", c = "F4EAFC", d = "D1AAF2", e = "B06CE8", f = "53336D" }, L = "7423~4732~7711~3137b1373b2255b2222c3344a3121a1312a2211a5211a2511a4211d2411d7412f4721f6611f3333e" }, -- Epic
	rarity_legendary = { R = "........../...aab..../..acdab.../.adddeab../.acdeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "B6883A", b = "8D6934", c = "F7D593", d = "FDF5E5", e = "F2B644", f = "6C4F2F" }, L = "7423~4732~7711~3137b1373b2255b2223c3344a3121a1312a2211a5211a2511a3333e7412f4721f6611f2331d4211d3411d" }, -- Legendary
	rarity_mythic = { R = "........../...aab..../..acdab.../.adddeab../.acdeeaf~./.baeeeaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "B34B6E", b = "8B3C5A", c = "F5A4BC", d = "FDE9EF", e = "EE628C", f = "6B2F4A" }, L = "7423~4732~7711~3137b1373b2255b2223c3344a3121a1312a2211a5211a2511a3333e7412f4721f6611f2331d4211d3411d" }, -- Mythic
	rarity_secret = { R = "........../...aab..../..accab.../.acdedab../.aceeeaf~./.badedaf~./..baaaf~~./...bff~~../....~~~.../..........", P = { a = "24212F", b = "211D2C", c = "828289", d = "282834", e = "FFFFFF", f = "1F1929" }, L = "7423~4732~7711~3137b1373b2255b2233c3344a3121a1312a2211a5211a2511a3333d7412f4721f6611f4313e3431e" }, -- Secret
	drop = { R = "....a...../...aab..../...aac~.../..adeab.../.afeeeab../.afeeeac~./.baaaaac~./..bcccc~~./...~~~~~../..........", P = { a = "356FB3", b = "2E568E", c = "28426F", d = "90C1F4", e = "4094EC", f = "E4F0FC" }, L = "3752~8513~6211~1473b2355b5111b3741c7512c5211c2453a3122a1412a2341a4011a3311d2412f3432e4311e" }, -- Water
	flame = { R = "....a...../.a..ab..../.b~.ac~a../.ab.aaac~./adaacadab./adacebaac~/bacfgeaac~/.bceheac~~/..bbbbc~~./...~~~~~..", P = { a = "B45232", b = "8C412E", c = "6B332A", d = "F6AA8C", e = "F2A93B", f = "FFE58A", g = "FFD24A", h = "FFFCEC" }, L = "3852~8523~2211~6211~8311~8811~3533e2841b5115b1216b2311b8411b0611b8512c2612c7315c4223c3511c6811c3611f6423a4014a0432a5322a1314a1111a7211a3411a6711a4711h1412d6411d4611g" }, -- Flame
	flake = { R = "....a...../.b.aab.b../..acdab.~./.aceddab../aadddddaf./.badddaf~~/..badaf~~./.b.baf~b../..~.f~~.~./.....~....", P = { a = "73A4BC", b = "5C7E94", c = "C2ECFB", d = "96DEF8", e = "F0FAFE", f = "495E73" }, L = "7522~5722~8211~9511~2811~8811~5911~3137b1373b2255b1111b7111b1711b7711b2222c3344a4018a0481a3111a2211a5211a1311a2511a3333d4215d2451d8411f7511f6611f5711f4811f3311e" }, -- Frost
	leaf = { R = ".....aaab./...aaccad~/..accefad~/.acffffad~/.acfffad~~/.baaaad~~./..bddd~~../.g.~~~~.../g.~......./.~........", P = { a = "528D47", b = "446D3E", c = "A7D99D", d = "385236", e = "EAF6E7", f = "68BE56", g = "1F572A" }, L = "8124~3642~7521~7611~2811~1911~5035a1353a3121a2211a5121c3221c2312c3332f6212f1711g0811g8113d3631d7411d6511d8011b1511b2611b5211e" }, -- Nature
	mountain = { R = "...a....../..aab...../..aac~a.../.adeaaab../.adffdfab./adfffffac~/aaaaaaaac~/bcccccccc~/.~~~~~~~~~/..........", P = { a = "876143", b = "6B4C3A", c = "543B33", d = "D2B59A", e = "F4EDE6", f = "B28050" }, L = "1594~5211~1374a2122a0512a3011a6211a2452f1781c8512c4211c2312d5411d1511d4111b7311b8411b0711b3311e" }, -- Earth
	bolt = { R = ".....aab../....aab~~./...aab~~../..abaaab../...~aab~~./...aab~~../..abb~~.../.ab~~~..../..~~....../..........", P = { a = "5661C1", b = "3A3B76" }, L = "6125~3434~2821~8111~8411~6611~4125a5021a2351a3211a3511a2611a1711a3621b7011b6111b5211b3311b7311b6411b5511b2711b" }, -- Storm
	sparkle = { R = "....a...../....b~..../...aab..../..acdab.../abadddabe./.~badae~~~/...bae~~../....b~~.../....e~..../.....~....", P = { a = "BF9D54", b = "947847", c = "FFF9EA", d = "FFD468", e = "715A3D" }, L = "5119~7531~6621~1511~6711~4117b1471b3235b2353b3311c4324a3221a2312a3442a4011a0411a8411e6511e5611e4811e4313d3431d" }, -- Celestial
	moon = { R = "...aabc.../..aac~~~../.aac~~..../.adc~...../.aac~...../.aac~...../.baab...b./..baaaac.~/...bccc~~./....~~~~..", P = { a = "63388A", b = "502E6F", c = "412559", d = "EDE5F4" }, L = "4218~5832~5131~5211~9711~8811~1641b5011b8611b2711b3811b1224a3741a2126a3021a2311d3214c4831c6011c4111c7711c" }, -- Shadow
	egg_common = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "808595", b = "666777", c = "F3F4F6", d = "CDD2DC", e = "A8B2C2", f = "504E5F" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Common
	egg_uncommon = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "529266", b = "447054", c = "EAF7ED", d = "A7DDB5", e = "68C480", f = "385446" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Uncommon
	egg_rare = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "4776B1", b = "3B5C8C", c = "E8F1FC", d = "9EC7F2", e = "589EE8", f = "32466D" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Rare
	egg_epic = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "8652B1", b = "6A418C", c = "F4EAFC", d = "D1AAF2", e = "B06CE8", f = "53336D" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Epic
	egg_legendary = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "B6883A", b = "8D6934", c = "FDF5E5", d = "F7D593", e = "F2B644", f = "6C4F2F" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Legendary
	egg_mythic = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeeeaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "B34B6E", b = "8B3C5A", c = "FDE9EF", d = "F5A4BC", e = "EE628C", f = "6B2F4A" }, L = "3258~8415~1365a2142a3021a7414f3841f6211f5011b6111b7311b1711b2811b3334e4211e2551d2314d4111d3211d3111c" }, -- odds egg Mythic
	egg_secret = { R = "...aab..../..acdab.../..adeaf~../.adeeeab../.adeegaf~./.adddddf~./.adeeeaf~./.baaaaaf~./..bffff~~./...~~~~~..", P = { a = "1E1C32", b = "131222", c = "DCD2FF", d = "5A548C", e = "2E2C48", f = "0A0A14", g = "FFFFFF" }, L = "3258~8415~1375b2158b5011b2256a1314a3021a2141a3334e4211e5411g2551d2314d4111d3211d7414f3841f6211f3111c" }, -- odds egg Secret
}
PixelIcon.Bitmaps.signpost = "....#..../#######../########./#########/########./#######../....#..../....#..../..#####.." -- Travel, one ink
PixelIcon.Bitmaps.rarity_common = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Common, one ink
PixelIcon.Bitmaps.rarity_uncommon = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Uncommon, one ink
PixelIcon.Bitmaps.rarity_rare = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Rare, one ink
PixelIcon.Bitmaps.rarity_epic = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Epic, one ink
PixelIcon.Bitmaps.rarity_legendary = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Legendary, one ink
PixelIcon.Bitmaps.rarity_mythic = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Mythic, one ink
PixelIcon.Bitmaps.rarity_secret = "........./...###.../..#####../.#######./.#######./.#######./..#####../...###.../........." -- Secret, one ink
-- each art-size icon's 19 x 19 cell in build/upload_sheets/icons_b.png (x, y); GreyY: the greyed twins' offset
PixelIcon.SheetCells = { Art = 19, GreyY = 40, note = { 0, 0 }, token = { 20, 0 }, gem = { 40, 0 }, pot = { 60, 0 }, egg = { 80, 0 }, bag = { 100, 0 }, gift = { 120, 0 }, box = { 140, 0 }, ticket = { 0, 20 }, potion = { 20, 20 }, paw = { 40, 20 }, book = { 60, 20 }, house = { 80, 20 }, stats = { 100, 20 }, gear = { 120, 20 }, signpost = { 140, 20 } }
-- END GENERATED icons_b
-- tick is the pitch's check (one drawing, two names)
PixelIcon.Bitmaps.tick = PixelIcon.Bitmaps.check

local cache = {}

-- (U5) the sizes warned about: [px] = 1. A size between multiples of 9 draws whole cells off-centre in a padded box, so
-- New warns once per such size (pass 18, 27, 36, ...)
PixelIcon.Warned = {}

-- the merged rectangles of an icon, { x, y, w, h } in cells (0-based), nil for an unknown name
function PixelIcon.Runs(name)
	if cache[name] then
		return cache[name]
	end
	local bmp = PixelIcon.Bitmaps[name]
	if type(bmp) ~= "string" then
		return nil
	end
	local rows = {}
	for row in (bmp .. "/"):gmatch("([^/]*)/") do
		rows[#rows + 1] = row
	end
	local rects = {}
	local open = {} -- [x .. ":" .. w] = the rectangle still growing down from the row above
	for y = 0, #rows - 1 do
		local row = rows[y + 1]
		local nextOpen = {}
		local x = 1
		while x <= #row do
			if row:sub(x, x) == "#" then
				local s = x
				while x <= #row and row:sub(x, x) == "#" do
					x = x + 1
				end
				local key = (s - 1) .. ":" .. (x - s)
				local r = open[key]
				if r then
					r[4] = r[4] + 1
				else
					r = { s - 1, y, x - s, 1 }
					rects[#rects + 1] = r
				end
				nextOpen[key] = r
			else
				x = x + 1
			end
		end
		open = nextOpen
	end
	cache[name] = rects
	return rects
end

----------------------------------------------------------------------
-- (Pitch 2 item 9 B) the own-colour glyphs, the greyed state and the uploaded sheet
----------------------------------------------------------------------
PixelIcon.Own = "Own" -- New's colour for "the icon's own colours" (Host and Lead pass it when the caller gave none)
PixelIcon.Art = PixelIcon.Art or {}
PixelIcon.SheetCells = PixelIcon.SheetCells or {}
local DROP_COLOUR = Color3.fromRGB(59, 36, 18) -- Theme.Sign.Text: the drop shadow, at 30 %
local DROP_T = 0.7
local GREY_TO = { 243, 230, 200 } -- Theme.Sign.Well: a greyed colour is its luminance a third of the way to it

-- the merged rectangles of an Art glyph, { x, y, w, h, letter } in cells (0-based; the drop shadow "~" in row / column 9
-- too): each row's runs of one letter, merged down while the next row has the same run. nil for a name with no Art
local artCache = {}
function PixelIcon.ArtRuns(name)
	if artCache[name] then
		return artCache[name]
	end
	local a = PixelIcon.Art[name]
	if type(a) ~= "table" or type(a.R) ~= "string" then
		return nil
	end
	-- (P2 icons review r1, major 6) the generated draw list: the glyph in layers, bottom first (the drop shadow, then one
	-- colour at a time over the colours drawn after it; tools/build_upload_sheets.py), 23 - 35 Frames where one Frame per
	-- run of one colour cost up to 51. Five characters a Frame: x, y, w, h in base 36 and the letter
	if type(a.L) == "string" and #a.L > 0 and #a.L % 5 == 0 then
		local rects = {}
		for i = 1, #a.L, 5 do
			rects[#rects + 1] = {
				tonumber(a.L:sub(i, i), 36), tonumber(a.L:sub(i + 1, i + 1), 36), tonumber(a.L:sub(i + 2, i + 2), 36),
				tonumber(a.L:sub(i + 3, i + 3), 36), a.L:sub(i + 4, i + 4),
			}
		end
		artCache[name] = rects
		return rects
	end
	local rects, open, y = {}, {}, 0
	for row in (a.R .. "/"):gmatch("([^/]*)/") do
		local nextOpen = {}
		local x = 1
		while x <= #row do
			local ch = row:sub(x, x)
			if ch ~= "." then
				local s = x
				while x <= #row and row:sub(x, x) == ch do
					x = x + 1
				end
				local key = ch .. (s - 1) .. ":" .. (x - s)
				local r = open[key]
				if r then
					r[4] = r[4] + 1
				else
					r = { s - 1, y, x - s, 1, ch }
					rects[#rects + 1] = r
				end
				nextOpen[key] = r
			else
				x = x + 1
			end
		end
		open = nextOpen
		y = y + 1
	end
	artCache[name] = rects
	return rects
end

-- (P2 icons review r1, major 7: on the navy top bar the gear's dark outline melted into the plank, a grey smudge) the
-- draw list of an Art glyph in a keyline: first its silhouette grown one cell every way (8 neighbours) as letter "@" (the
-- key colour: New draws it under the glyph, so only a 1-cell ring of it shows), then the glyph's layers without the drop
-- shadow (the mock-up's top bar: make_item9.keyline, no drop on a dark plate). Cells run -1 .. 10. nil with no Art
local keyCache = {}
function PixelIcon.KeyRuns(name)
	if keyCache[name] then
		return keyCache[name]
	end
	local art = PixelIcon.ArtRuns(name)
	if not art then
		return nil
	end
	local solid = {}
	for _, r in ipairs(art) do
		if r[5] ~= "~" then
			for y = r[2], r[2] + r[4] - 1 do
				for x = r[1], r[1] + r[3] - 1 do
					solid[y * 16 + x] = true
				end
			end
		end
	end
	local function grown(x, y)
		for dy = -1, 1 do
			for dx = -1, 1 do
				local xx, yy = x + dx, y + dy
				if xx >= 0 and yy >= 0 and xx <= 9 and yy <= 9 and solid[yy * 16 + xx] then
					return true
				end
			end
		end
		return false
	end
	local rects, open = {}, {}
	for y = -1, 10 do
		local nextOpen = {}
		local x = -1
		while x <= 10 do
			if grown(x, y) then
				local s = x
				while x <= 10 and grown(x, y) do
					x = x + 1
				end
				local k = s .. ":" .. (x - s)
				local r = open[k]
				if r then
					r[4] = r[4] + 1
				else
					r = { s, y, x - s, 1, "@" }
					rects[#rects + 1] = r
				end
				nextOpen[k] = r
			else
				x = x + 1
			end
		end
		open = nextOpen
	end
	for _, r in ipairs(art) do
		if r[5] ~= "~" then
			rects[#rects + 1] = r
		end
	end
	keyCache[name] = rects
	return rects
end

-- the colour of letter `ch` of Art glyph `name` (the drop shadow's for "~")
local colourCache = {}
local function artColour(name, ch)
	if ch == "~" then
		return DROP_COLOUR
	end
	local per = colourCache[name]
	if not per then
		per = {}
		colourCache[name] = per
	end
	if per[ch] == nil then
		local a = PixelIcon.Art[name]
		local n = tonumber(a and a.P and a.P[ch] or "", 16) or 0
		per[ch] = Color3.fromRGB(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
	end
	return per[ch]
end

-- a colour's greyed twin (the disabled state; the sheet's greyed row is baked with the same rule)
local function greyOf(c)
	local r, g, b = c.R * 255, c.G * 255, c.B * 255
	local lum = 0.299 * r + 0.587 * g + 0.114 * b
	local function ch(t)
		return math.floor(lum + (t - lum) * 0.35 + 0.5)
	end
	return Color3.fromRGB(ch(GREY_TO[1]), ch(GREY_TO[2]), ch(GREY_TO[3]))
end

-- a Frame's transparency under a text's: its own (BaseT: the drop shadow's 30 %) composed with t
local function composeT(f, t)
	local base = f:GetAttribute("BaseT")
	if not base then
		return t
	end
	return 1 - (1 - base) * (1 - t)
end

-- the uploaded sheet's image id (Config.IconSheet.Id, a whole number above 0), else 0. Config is read when an art-size
-- icon draws, never at load; while it is not there yet (the loading screen) the icon draws its 9 x 9 glyph
local configMod = nil -- the module once required, false when requiring it failed
local function sheetId()
	if configMod == nil then
		local ok, mod = pcall(function()
			return require(script.Parent.Config)
		end)
		if ok and type(mod) == "table" then
			configMod = mod
		elseif ok then
			configMod = false
		end
	end
	local t = configMod and configMod.IconSheet
	local id = type(t) == "table" and tonumber(t.Id) or 0
	if id and id > 0 and id == math.floor(id) then
		return id
	end
	return 0
end

-- the sheet cell an Own icon of px draws from: art sizes only (2+ px cells on the 18 grid), a name the sheet holds, an id
local function sheetCellFor(name, px)
	local c = PixelIcon.SheetCells[name]
	if type(c) ~= "table" or math.floor(px / 18) < 2 then
		return nil
	end
	if sheetId() <= 0 then
		return nil
	end
	return c
end

----------------------------------------------------------------------
-- (LOOK-ui, kitb-look1: the owner's look bar 2026-11-17, "pixel edges snapped to whole pixels at every screen size")
-- whole device px under a UIScale. A window or the HUD sits under a Fit / ViewportScale of 0.8 or 0.85 below 1080p, so a
-- 2 px design cell drew 1.6 screen px (lumpy 1-and-2 px cells in the game, soft in the renders). A part that must stay
-- on the pixel grid asks for its design px through PixelIcon.Px(n, s): the nearest whole number of screen px (at least
-- one), back in design px. PixelIcon.Whole re-runs a part's sizing whenever the rest scale above it changes.
----------------------------------------------------------------------
-- n design px under rest scale s: a whole number of screen px (at least one while n > 0), in design px
function PixelIcon.Px(n, s)
	n = tonumber(n) or 0
	s = tonumber(s) or 1
	if n <= 0 or s <= 0 then
		return n
	end
	return math.max(1, math.floor(n * s + 0.5)) / s
end

-- a UIScale that tweens and rests at 1 (a pop, a pulse, the HUD's unnamed ones) is left out of the rest scale: the
-- grid is the one the part rests on
local TRANSIENT = { Pop = true, Pulse = true, PopScale = true, FxScale = true, UIScale = true }

-- the product of the resting UIScales on `obj` and every GuiObject above it, up to its ScreenGui; `found` (optional) gets
-- each one
local function restScaleOf(obj, found)
	local s = 1
	local cur = obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			for _, ui in ipairs(cur:GetChildren()) do
				if ui:IsA("UIScale") and not TRANSIENT[ui.Name] then
					if ui.Scale > 0 then
						s = s * ui.Scale
					end
					if found then
						found[#found + 1] = ui
					end
				end
			end
		end
		cur = cur.Parent
	end
	return s
end
PixelIcon.RestScale = restScaleOf

local watched = setmetatable({}, { __mode = "k" }) -- [part] = { Fn = fn(s), S = the scale it was last sized for }
local hookedScales = setmetatable({}, { __mode = "k" }) -- [UIScale] = true once its Scale is watched
local passPending = false

local function applyWhole(part, entry, force)
	local found = {}
	local s = restScaleOf(part, found)
	for _, ui in ipairs(found) do
		if not hookedScales[ui] then
			hookedScales[ui] = true
			ui:GetPropertyChangedSignal("Scale"):Connect(function()
				if not passPending then
					passPending = true
					task.defer(function()
						passPending = false
						for p, e in pairs(watched) do
							if p.Parent then
								applyWhole(p, e, false)
							end
						end
					end)
				end
			end)
		end
	end
	if force or entry.S ~= s then
		entry.S = s
		entry.Fn(s)
	end
end

-- runs fn(s) now (s = the rest scale above `part`) and again whenever that scale changes: `part` moved under another
-- window, or a Fit / ViewportScale above it set to a new value. One watcher per part (a second call replaces fn)
function PixelIcon.Whole(part, fn)
	local entry = watched[part]
	if entry then
		entry.Fn = fn
		applyWhole(part, entry, true)
		return
	end
	entry = { Fn = fn, S = nil }
	watched[part] = entry
	applyWhole(part, entry, true)
	part.AncestryChanged:Connect(function()
		if part.Parent then
			applyWhole(part, entry, false)
		end
	end)
end

-- a stroke `n` design px thick (attribute DesignPx), drawn a whole number of screen px. Call again to change n; a
-- thickness its owner sets later (a selected card's thicker edge) is taken as the new design px and snapped too
local followed = setmetatable({}, { __mode = "k" }) -- [stroke or lip] = the value this module set last
function PixelIcon.WholeStroke(stroke, n)
	stroke:SetAttribute("DesignPx", tonumber(n) or stroke.Thickness)
	local first = followed[stroke] == nil
	followed[stroke] = -1
	PixelIcon.Whole(stroke, function(s)
		local px = PixelIcon.Px(stroke:GetAttribute("DesignPx") or 0, s)
		followed[stroke] = px
		stroke.Thickness = px
	end)
	if first then
		stroke:GetPropertyChangedSignal("Thickness"):Connect(function()
			if math.abs(stroke.Thickness - (followed[stroke] or -1)) > 1e-4 then
				PixelIcon.WholeStroke(stroke, stroke.Thickness)
			end
		end)
	end
	return stroke
end

-- a bar along an edge (a lip) `n` design px tall (attribute DesignPx; its width and position are the caller's), drawn a
-- whole number of screen px tall. Call again to change n; a height its owner sets later (a press thins the lip) is taken
-- as the new design px
function PixelIcon.WholeHeight(obj, n)
	obj:SetAttribute("DesignPx", tonumber(n) or obj.Size.Y.Offset)
	local first = followed[obj] == nil
	followed[obj] = -1
	PixelIcon.Whole(obj, function(s)
		local size = obj.Size
		local px = PixelIcon.Px(obj:GetAttribute("DesignPx") or 0, s)
		followed[obj] = px
		obj.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale, px)
	end)
	if first then
		obj:GetPropertyChangedSignal("Size"):Connect(function()
			local y = obj.Size.Y
			if y.Scale == 0 and math.abs(y.Offset - (followed[obj] or -1)) > 1e-4 then
				PixelIcon.WholeHeight(obj, y.Offset)
			end
		end)
	end
	return obj
end

-- (LOOK-ui) every kit edge (a Border UIStroke) and every kit lip (a Frame "Lip" of a fixed height) under `root`, now and
-- whenever one is added later, drawn on whole screen px (WholeStroke / WholeHeight). For a window's or the HUD's whole
-- gui, so a card built later (a list row, a pet card) stays on the grid without each builder asking. Once per root.
-- (LOOK-ui: border leaks) and no GuiObject there keeps Roblox's default 1 px dark border (BorderSizePixel 1 on a new
-- Frame / TextLabel: it showed round the Pets busy marks, the Shop's header icon, the BEST VALUE tag): kit B draws its
-- edges with strokes only
local treed = setmetatable({}, { __mode = "k" })
local function adopt(d)
	if d:IsA("GuiObject") and d.BorderSizePixel ~= 0 then
		d.BorderSizePixel = 0
	end
	if followed[d] ~= nil then
		return
	end
	if d:IsA("UIStroke") then
		if d.ApplyStrokeMode == Enum.ApplyStrokeMode.Border and d.Thickness > 0 then
			PixelIcon.WholeStroke(d, d.Thickness)
		end
	elseif d:IsA("Frame") and d.Name == "Lip" then
		local y = d.Size.Y
		if y.Scale == 0 and y.Offset > 0 then
			PixelIcon.WholeHeight(d, y.Offset)
		end
	end
end
function PixelIcon.WholeTree(root)
	if not root or treed[root] then
		return
	end
	treed[root] = true
	for _, d in ipairs(root:GetDescendants()) do
		adopt(d)
	end
	root.DescendantAdded:Connect(function(d)
		if d:IsA("GuiObject") and d.BorderSizePixel ~= 0 then
			d.BorderSizePixel = 0
		end
		if d:IsA("UIStroke") or (d:IsA("Frame") and d.Name == "Lip") then
			-- its builder names and sizes it right after parenting it: look once that is done
			task.defer(function()
				if d.Parent then
					adopt(d)
				end
			end)
		end
	end)
end

-- a face inset `e` design px from every side of its parent (`extra` px more off its height: the lip it leaves showing
-- under it), both whole screen px (attributes InsetPx, InsetExtra). Call again to change them (a plank's press)
function PixelIcon.WholeInset(face, e, extra)
	face:SetAttribute("InsetPx", tonumber(e) or 0)
	face:SetAttribute("InsetExtra", tonumber(extra) or 0)
	PixelIcon.Whole(face, function(s)
		local px = PixelIcon.Px(face:GetAttribute("InsetPx") or 0, s)
		local more = PixelIcon.Px(face:GetAttribute("InsetExtra") or 0, s)
		face.Position = UDim2.fromOffset(px, px)
		face.Size = UDim2.new(1, -2 * px, 1, -(2 * px + more))
	end)
	return face
end


-- (U9-7 look) the cells on whole SCREEN pixels under a window's or a HUD's UIScale. A dock at 0.8 drew a 27 px icon's 3 px
-- cells 2.4 px wide (Roblox rounds each Frame's edges to the pixel, so the columns came out 2 and 3 px: uneven) and an
-- 18 px icon's 1.6 px wide. A cell is now round(cell x scale) screen px (a half rounds down, never under 2 for a 2+ px
-- cell; at 0.7 - 0.8 both sizes draw 2 px cells: one pixel size on a phone), centred in the icon's box, which keeps its
-- design size (the layout is unchanged; PixelIcon.Lead keeps its gap to the text past what draws outside the box).
-- The short tweens on top (a press, a pop, a pulse) are not counted. Fitted when the icon is parented under a ScreenGui
-- (here, or when it or an ancestor moves there) and again when one of the UIScales above it changes. At scale 1 the
-- cells are exactly the old ones. Attribute CellPx = the screen px of a cell
local TWEEN_SCALES = { Pop = true, PopScale = true, FxScale = true, Punch = true, Pulse = true, Swell = true, Bounce = true }
local scaleSets = setmetatable({}, { __mode = "k" }) -- [UIScale] = { [icon] = true } (weak both ways)
local scaleConns = setmetatable({}, { __mode = "k" })

-- the product of the layout UIScales on `obj` and above it, the list of them, and whether it reached a ScreenGui
local function layoutScale(obj)
	local s, scales = 1, {}
	local cur = obj
	while cur do
		if cur:IsA("LayerCollector") then
			return s, scales, true
		end
		if cur:IsA("GuiObject") then
			local ui = cur:FindFirstChildOfClass("UIScale")
			if ui and ui.Scale > 0 and not TWEEN_SCALES[ui.Name] then
				s = s * ui.Scale
				scales[#scales + 1] = ui
			end
		end
		cur = cur.Parent
	end
	return s, scales, false
end

-- the screen px of a cell of `cell` design px under scale s: the nearest whole px (a half rounds up, as PixelIcon.Px and
-- PixelCrisp.Px: one rounding for every cell of a screen), and never under
-- 2 for a cell of 2 or more, so an 18 px icon stays legible and every icon of a phone screen (0.7 - 0.8) draws 2 px cells
local function screenCellOf(cell, s)
	return math.max(1, math.min(cell, 2), math.floor(cell * s + 0.5))
end

-- design px an icon of px draws past each side of its box under scale s (0 when it draws inside it)
local function overflowOf(px, s)
	local sc = screenCellOf(math.floor(px / 9), s)
	return math.max(0, (9 * sc / s - px) / 2)
end

local fitCells
local function watchScale(scale)
	if scaleConns[scale] then
		return scaleSets[scale]
	end
	local set = setmetatable({}, { __mode = "k" })
	scaleSets[scale] = set
	scaleConns[scale] = scale:GetPropertyChangedSignal("Scale"):Connect(function()
		for icon in pairs(set) do
			if icon.Parent then
				fitCells(icon)
			end
		end
	end)
	return set
end

fitCells = function(icon)
	if icon:GetAttribute("Sheet") then
		-- (Pitch 2 item 9 B) the sheet's art: 18 cells of px / 18, each a whole number of screen px (as below), centred.
		-- (P2 icons review r1, major 1) a FromSheet drawing: Grid cells (9) of px / Grid, its ArtW x ArtH cut
		local art = icon:FindFirstChild("Art")
		local s, scales, rooted = layoutScale(icon)
		if not (art and rooted) then
			return
		end
		local grid = icon:GetAttribute("Grid") or 18
		local px = icon.Size.X.Offset
		local screenCell = screenCellOf(math.floor(px / grid), s)
		local dc = screenCell / s
		local pad = math.floor((px * s - grid * screenCell) / 2) / s
		art.Position = UDim2.fromOffset(pad, pad)
		art.Size = UDim2.fromOffset((icon:GetAttribute("ArtW") or 19) * dc, (icon:GetAttribute("ArtH") or 19) * dc)
		icon:SetAttribute("CellPx", screenCell)
		for _, scale in ipairs(scales) do
			watchScale(scale)[icon] = true
		end
		return
	end
	local name = icon:GetAttribute("PixelIcon")
	local rects = (icon:GetAttribute("Key") and PixelIcon.KeyRuns(name)) or (icon:GetAttribute("Own") and PixelIcon.ArtRuns(name)) or PixelIcon.Runs(name)
	if not rects then
		return
	end
	-- (merge kitb-look1 x U9-9) from the icon itself: its own UIScale scales its cells too (PixelCrisp's "Crisp" on an
	-- icon it adopted; counted from above only, the cells were fitted twice and drew 2.5 px)
	local s, scales, rooted = layoutScale(icon)
	if not rooted then
		return
	end
	local px = icon.Size.X.Offset
	local cell = math.floor(px / 9)
	local screenCell = screenCellOf(cell, s)
	local dc = screenCell / s
	local pad = math.floor((px * s - 9 * screenCell) / 2) / s
	for i, r in ipairs(rects) do
		local f = icon:FindFirstChild("R" .. i)
		if f then
			f.Position = UDim2.fromOffset(pad + r[1] * dc, pad + r[2] * dc)
			f.Size = UDim2.fromOffset(r[3] * dc, r[4] * dc)
		end
	end
	icon:SetAttribute("CellPx", screenCell)
	for _, scale in ipairs(scales) do
		watchScale(scale)[icon] = true
	end
end

-- (merge kitb-look1 x U9-9) fits `root` and everything under it again now: every whole-px part (Whole) and every icon
-- (New). For a UIScale this module did not watch yet: client/UI/PixelCrisp's "Crisp" correction added on a Lead box
-- after Lead sized it (the box then drew its 2 px cells 2.5 px wide). From then on the new scale is watched
function PixelIcon.Refit(root)
	if not root then
		return
	end
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	for _, d in ipairs(list) do
		local entry = watched[d]
		if entry and d.Parent then
			applyWhole(d, entry, false)
		end
		if d:GetAttribute("PixelIcon") and d:GetAttribute("Cell") then
			fitCells(d)
		end
	end
end

-- (U9-7 look) fits an icon made by PixelIcon.New to the UIScales above it now (New and a move do it by themselves)
function PixelIcon.Fit(icon)
	if icon and icon:GetAttribute("PixelIcon") then
		fitCells(icon)
	end
end

-- (kit-b prep, the leak hunt) while frozen (PixelIcon.SetFrozen, below), New, Host and Lead connect nothing
local frozen = false

-- draws icon `name` at px x px in `colour` into `parent`; nil for an unknown name. (Pitch 2 item 9 B) colour =
-- PixelIcon.Own: an Art icon in its own colours (an art size from the uploaded sheet once it has an id). (P2 icons review
-- r1) `key` (a Color3, own colours only): the glyph in a 1-cell keyline ring of it, no drop shadow (a dark plate: the
-- top bar), attribute Key; always the 9 x 9 Frames
function PixelIcon.New(parent, name, px, colour, key)
	local own = colour == PixelIcon.Own and PixelIcon.Art[name] ~= nil
	if colour == PixelIcon.Own and not own then
		colour = nil -- a one-ink glyph has no colours of its own: white, as with no colour
	end
	if not (own and typeof(key) == "Color3") then
		key = nil
	end
	local rects = (key and PixelIcon.KeyRuns(name)) or (own and PixelIcon.ArtRuns(name)) or PixelIcon.Runs(name)
	if not rects then
		return nil
	end
	px = math.max(9, math.floor(tonumber(px) or 18)) -- under 9 px a cell would be under a pixel: one px a cell
	if px % 9 ~= 0 and not PixelIcon.Warned[px] then
		PixelIcon.Warned[px] = 1
		warn("[PixelIcon] " .. px .. " px is not a multiple of 9: the cells draw at " .. (9 * math.floor(px / 9)) .. " px in a padded box")
	end
	local cell = math.floor(px / 9)
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(px, px)
	icon:SetAttribute("PixelIcon", name)
	icon:SetAttribute("Cell", cell)
	if own then
		icon:SetAttribute("Own", true)
	end
	if key then
		icon:SetAttribute("Key", true)
	end
	local sheetCell = own and not key and sheetCellFor(name, px)
	if sheetCell then
		-- (Pitch 2 item 9 B) the 18 x 18 art cut from the uploaded sheet: one ImageLabel, never a blurry scale
		icon:SetAttribute("Sheet", true)
		local dc = math.floor(px / 18)
		local pad = math.floor((px - 18 * dc) / 2)
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.BorderSizePixel = 0
		art.Image = "rbxassetid://" .. string.format("%d", sheetId())
		art.ImageRectOffset = Vector2.new(sheetCell[1], sheetCell[2])
		art.ImageRectSize = Vector2.new(PixelIcon.SheetCells.Art or 19, PixelIcon.SheetCells.Art or 19)
		art.ResampleMode = Enum.ResamplerMode.Pixelated
		art.ScaleType = Enum.ScaleType.Stretch
		art.Position = UDim2.fromOffset(pad, pad)
		art.Size = UDim2.fromOffset(19 * dc, 19 * dc)
		art.Parent = icon
		icon.Parent = parent
		fitCells(icon)
		if not frozen then
			icon.AncestryChanged:Connect(function()
				fitCells(icon)
			end)
		end
		return icon
	end
	local cells = {}
	for i, r in ipairs(rects) do
		local f = Instance.new("Frame")
		f.Name = "R" .. i
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 0
		if own and r[5] == "@" then
			f.BackgroundColor3 = key
		elseif own then
			f.BackgroundColor3 = artColour(name, r[5])
			if r[5] == "~" then
				f.BackgroundTransparency = DROP_T
				f:SetAttribute("BaseT", DROP_T)
			end
		else
			f.BackgroundColor3 = colour or Color3.new(1, 1, 1)
		end
		f.Parent = icon
		cells[i] = f
	end
	local function lay(s)
		local dc = (math.abs(s - 1) < 1e-4) and cell or PixelIcon.Px(cell, s)
		-- the cells centred in the box, their origin on a whole screen px of the box
		local pad = math.floor((px - 9 * dc) / 2 * s + 1e-6) / s
		for i, r in ipairs(rects) do
			cells[i].Position = UDim2.fromOffset(pad + r[1] * dc, pad + r[2] * dc)
			cells[i].Size = UDim2.fromOffset(r[3] * dc, r[4] * dc)
		end
	end
	icon.Parent = parent
	-- (merge kitb-look1 x kitb-ui2) the design layout first (lay at scale 1), then fitCells puts the cells on whole
	-- screen px under the UIScales above (U9-7 look), now and whenever it lands under a ScreenGui
	lay(1)
	-- (U9-7 look) whole screen pixels under the UIScales above it, now and whenever it lands under a ScreenGui
	fitCells(icon)
	-- (kit-b gate U9 r4, the leak) a frozen build (a cached template that is only ever cloned: SetFrozen below) gets no
	-- follow listener here either; Host and Lead already skipped theirs, but this one sat on every template icon
	if not frozen then
		icon.AncestryChanged:Connect(function()
			fitCells(icon)
		end)
	end
	return icon
end

-- (P2 icons review r1, major 1: the odds chips under the pixel machines drew a smooth vector egg) a 9 x 9 drawing cut from
-- an uploaded sheet other than the icon sheet (item 10's odds chip eggs, the machines sheet's egg row): icon `name` at px
-- x px, ONE ImageLabel "Art" of image id `image` cut by `rect` { x, y, w, h } (the 9 x 9 cells + the drop shadow: 10 x
-- 10), ResampleMode Pixelated, px / 9 a cell on whole screen px under the UIScales above it (as New's). Attributes as
-- New's sheet icons (PixelIcon, Cell, Own, Sheet, CellPx) + Grid 9. nil without a whole image id above 0 or a rect
function PixelIcon.FromSheet(parent, name, px, image, rect)
	image = tonumber(image) or 0
	if not (image > 0 and image == math.floor(image) and type(rect) == "table" and tonumber(rect[3]) and tonumber(rect[4])) then
		return nil
	end
	px = math.max(9, math.floor(tonumber(px) or 18))
	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Size = UDim2.fromOffset(px, px)
	icon:SetAttribute("PixelIcon", name)
	icon:SetAttribute("Cell", math.floor(px / 9))
	icon:SetAttribute("Own", true)
	icon:SetAttribute("Sheet", true)
	icon:SetAttribute("Grid", 9)
	icon:SetAttribute("ArtW", rect[3])
	icon:SetAttribute("ArtH", rect[4])
	local dc = math.floor(px / 9)
	local pad = math.floor((px - 9 * dc) / 2)
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Image = "rbxassetid://" .. string.format("%d", image)
	art.ImageRectOffset = Vector2.new(rect[1], rect[2])
	art.ImageRectSize = Vector2.new(rect[3], rect[4])
	art.ResampleMode = Enum.ResamplerMode.Pixelated
	art.ScaleType = Enum.ScaleType.Stretch
	art.Position = UDim2.fromOffset(pad, pad)
	art.Size = UDim2.fromOffset(rect[3] * dc, rect[4] * dc)
	art.Parent = icon
	icon.Parent = parent
	fitCells(icon)
	if not frozen then
		icon.AncestryChanged:Connect(function()
			fitCells(icon)
		end)
	end
	return icon
end

-- (P2 icons review r1, major 2) the icon sheet's image id (Config.IconSheet.Id), 0 while nothing is uploaded: a caller
-- that caches its drawn art keys it with this, so the art redraws when a sheet is set (render_gui --sheets, the tests)
PixelIcon.SheetId = function()
	return sheetId()
end

-- (LOOK-ui, kitb-look1: the host from the snapped icon, not the icon from the host) the design px a box needs round icon
-- `px` with `margin` screen px of face on each side, under rest scale s: 9 whole-px cells plus the margins (22 screen px
-- for a 2 px cell, 31 for 3), back in design px. A box sized from its host (a 16 px chip at 0.8 under an 18 px icon) let
-- the icon hang over its edge
function PixelIcon.BoxPx(px, margin, s)
	s = (tonumber(s) or 1) > 0 and s or 1
	local cell = math.floor(math.max(9, tonumber(px) or 18) / 9)
	return (9 * screenCellOf(cell, s) + 2 * (tonumber(margin) or 2)) / s -- (merge) the cell rule of fitCells (New)
end

-- (LOOK-ui) icon `name` at px (its cell size) in `chip`, a square the caller places: the chip is sized from the icon's
-- whole-px cells (PixelIcon.BoxPx: `margin` screen px of face round them, default 2) and the cells start `margin` px in,
-- again whenever the rest scale above changes. Returns the icon (nil for an unknown name)
function PixelIcon.Chip(chip, name, px, colour, margin)
	px = math.max(9, math.floor(tonumber(px) or 18))
	margin = tonumber(margin) or 2
	local icon = PixelIcon.New(chip, name, px, colour)
	if not icon then
		return nil
	end
	local cell = math.floor(px / 9)
	PixelIcon.Whole(chip, function(s)
		local sc = screenCellOf(cell, s)
		local side = PixelIcon.BoxPx(px, margin, s)
		chip.Size = UDim2.fromOffset(side, side)
		-- New centres its cells in the px box with this inset (fitCells; negative when they overflow it): undo it,
		-- then the margin
		local pad = math.floor((px * s - 9 * sc) / 2) / s
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromOffset(margin / s - pad, margin / s - pad)
	end)
	chip:SetAttribute("IconChip", name)
	return icon
end

-- recolours an icon made by PixelIcon.New (an own-colour glyph: every cell but its drop shadow, in one ink)
function PixelIcon.Tint(icon, colour)
	for _, f in ipairs(icon and icon:GetChildren() or {}) do
		if f:IsA("Frame") and not f:GetAttribute("BaseT") then
			f.BackgroundColor3 = colour
		end
	end
end

-- (Pitch 2 item 9 B) the disabled state of an own-colour icon: on, the sheet's greyed row (an ImageLabel icon) or every
-- cell's grey twin (the 9 x 9 glyph; the drop shadow stays); off, its colours again. Attribute Grey. A one-ink icon is
-- left as it is (its caller tints it)
function PixelIcon.Grey(icon, on)
	if not icon then
		return
	end
	on = on == true
	local name = icon:GetAttribute("PixelIcon")
	if icon:GetAttribute("Sheet") then
		local art, c = icon:FindFirstChild("Art"), PixelIcon.SheetCells[name]
		if art and type(c) == "table" then
			art.ImageRectOffset = Vector2.new(c[1], c[2] + (on and (PixelIcon.SheetCells.GreyY or 0) or 0))
		end
	elseif icon:GetAttribute("Own") then
		local list = icon:GetAttribute("Key") and PixelIcon.KeyRuns(name) or PixelIcon.ArtRuns(name)
		for i, r in ipairs(list or {}) do
			local f = icon:FindFirstChild("R" .. i)
			if f and r[5] ~= "~" and r[5] ~= "@" then
				local c = artColour(name, r[5])
				f.BackgroundColor3 = on and greyOf(c) or c
			end
		end
	else
		return
	end
	icon:SetAttribute("Grey", on)
end

-- (U7a) the multiple of 9 nearest to px (at least 9): the size an icon standing in for a glyph of px draws at
function PixelIcon.Snap(px)
	return math.max(9, math.floor((tonumber(px) or 18) / 9 + 0.5) * 9)
end

-- (U7a) icon `name` of about px px centred in `host` (a text object): it takes the host's TextColor3 (unless `colour` is
-- given), TextTransparency and ZIndex and follows later changes to them, so a caller that tints, fades or layers the text
-- moves the icon with it. px nil: the icon is 0.9 x the host's TextSize and is redrawn when that changes (a glyph label
-- a layout resizes). Returns the icon Frame (attribute PixelIcon = name; a redraw replaces it); nil for an unknown name.
-- Hosting again on the same host drops the old icon and its connections first (a mark that changes, a coin resized).
local hosted = setmetatable({}, { __mode = "k" }) -- [host] = { icon = Frame, conns = { connections } }
local scaleOf -- (below, with Lead: the UIScales over an object)

-- (U9-4 look review 2: whole pixels) the host's padded box in its own px: its laid-out AbsoluteSize (a grid cell or an
-- aspect constraint can size it other than its Size), else, before its first layout, its Size where that is a fixed
-- offset; nil for a scaled host not laid out yet. A UIPadding insets the icon as it insets the text
local function hostBox(host)
	local size = host.Size
	local w, h = nil, nil
	local a, s = host.AbsoluteSize, scaleOf(host)
	if a.X > 0 and a.Y > 0 and s > 0 then
		w, h = math.floor(a.X / s + 0.5), math.floor(a.Y / s + 0.5)
	elseif size.X.Scale == 0 and size.Y.Scale == 0 and host.AutomaticSize == Enum.AutomaticSize.None then
		w, h = size.X.Offset, size.Y.Offset
	end
	if not w then
		return nil
	end
	local pad = host:FindFirstChildOfClass("UIPadding")
	if pad then
		w = w - pad.PaddingLeft.Offset - pad.PaddingRight.Offset - (pad.PaddingLeft.Scale + pad.PaddingRight.Scale) * w
		h = h - pad.PaddingTop.Offset - pad.PaddingBottom.Offset - (pad.PaddingTop.Scale + pad.PaddingBottom.Scale) * h
	end
	return w, h
end

-- the icon centred in its host by a whole-px offset (an AnchorPoint of 0.5 put it on a half pixel wherever the host and
-- the icon differ by an odd number of px); before a scaled host's first layout, centred by scale
local function centreIn(icon, host)
	local w, h = hostBox(host)
	local px = icon.Size.X.Offset
	if w then
		icon.AnchorPoint = Vector2.new(0, 0)
		icon.Position = UDim2.fromOffset(math.floor((w - px) / 2), math.floor((h - px) / 2))
	else
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
	end
end

-- (kit-b prep, the leak hunt) while frozen, Host and Lead draw and place the icon once and connect nothing: for a tree
-- that is only ever cloned (HomeBuilder's cached station templates; Clone copies no connections), where a follow
-- listener would only sit on the template for the server's life. SetFrozen(on) -> the previous setting
function PixelIcon.SetFrozen(on)
	local was = frozen
	frozen = on == true
	return was
end

function PixelIcon.Host(host, name, px, colour)
	local old = hosted[host]
	if old then
		hosted[host] = nil
		for _, c in ipairs(old.conns) do
			c:Disconnect()
		end
		if old.icon then
			old.icon:Destroy()
		end
	end
	if not PixelIcon.Bitmaps[name] then
		return nil
	end
	local entry = { icon = nil, conns = {} }
	hosted[host] = entry
	local icon = nil
	-- (Pitch 2 item 9 B) no colour given and the icon has its own: it keeps them (the text's colour does not tint it)
	local own = colour == nil and PixelIcon.Art[name] ~= nil
	local function sync()
		if not icon then
			return
		end
		icon.ZIndex = host.ZIndex
		for _, f in ipairs(icon:GetChildren()) do
			if f:IsA("Frame") then
				if not own then
					f.BackgroundColor3 = colour or host.TextColor3
				end
				f.BackgroundTransparency = composeT(f, host.TextTransparency)
				f.ZIndex = host.ZIndex
			elseif f:IsA("ImageLabel") then
				f.ImageTransparency = host.TextTransparency
				f.ZIndex = host.ZIndex
			end
		end
	end
	local function draw()
		if icon then
			icon:Destroy()
		end
		-- (P2 icons review r1, major 7) a host's IconKey attribute (a Color3: the top bar's pill buttons) draws its own-colour
		-- icon in that keyline
		local key = own and host:GetAttribute("IconKey") or nil
		icon = PixelIcon.New(host, name, PixelIcon.Snap(px or (tonumber(host.TextSize) or 18) * 0.9), own and PixelIcon.Own or (colour or host.TextColor3), key)
		centreIn(icon, host)
		entry.icon = icon
		sync()
	end
	local function recentre()
		if icon then
			centreIn(icon, host)
		end
	end
	draw()
	if frozen then
		return icon
	end
	local conns = entry.conns
	conns[#conns + 1] = host:GetPropertyChangedSignal("TextColor3"):Connect(sync)
	conns[#conns + 1] = host:GetPropertyChangedSignal("TextTransparency"):Connect(sync)
	conns[#conns + 1] = host:GetPropertyChangedSignal("ZIndex"):Connect(sync)
	-- (U9-4 look review 2) a resized host keeps its icon on whole px
	conns[#conns + 1] = host:GetPropertyChangedSignal("Size"):Connect(recentre)
	conns[#conns + 1] = host:GetPropertyChangedSignal("AbsoluteSize"):Connect(recentre)
	if px == nil then
		conns[#conns + 1] = host:GetPropertyChangedSignal("TextSize"):Connect(function()
			if icon and icon.Size.X.Offset ~= PixelIcon.Snap((tonumber(host.TextSize) or 18) * 0.9) then
				draw()
			end
		end)
	end
	return icon
end

local leadConns = setmetatable({}, { __mode = "k" }) -- [label] = { [childName] = { connections } } (a re-call drops the old)

-- (U7a review) the product of the UIScales on `obj` and every GuiObject above it, up to its ScreenGui: Roblox's
-- TextBounds is screen px (after all of them), a Position offset is the object's own px. A HUD panel's ScreenFactor
-- (0.8 on a phone, up to 1.25) and a token pop (about 1.7) are among them
function scaleOf(obj)
	local s = 1
	local cur = obj
	while cur and not cur:IsA("LayerCollector") do
		if cur:IsA("GuiObject") then
			local ui = cur:FindFirstChildOfClass("UIScale")
			if ui and ui.Scale > 0 then
				s = s * ui.Scale
			end
		end
		cur = cur.Parent
	end
	return s
end

-- (U7b review) the width of a label's text in its own px, for when TextBounds has none: Theme.MeasureLabel (TextService
-- with the label's font; a Nunito face, whose .Font reads Unknown, on its role's Enum font with the role's spare
-- widening, so it runs wide, never short). A Roblox server lays out no text (TextBounds reads 0 there), and the world
-- signs Lead on the server, where the icon's place is set once (no client places it again). Theme is required here, on
-- first use, not at load: PixelIcon loads without it (the loading screen draws icons before Theme arrives)
local function measuredWidth(label)
	local text = tostring(label.Text or "")
	if text == "" then
		return 0
	end
	local ok, v = pcall(function()
		local Theme = require(script.Parent.Theme)
		return Theme.MeasureLabel(label)
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return math.ceil(v.X)
	end
	return math.ceil(#text * (tonumber(label.TextSize) or 14) * 0.6)
end

function PixelIcon.Lead(label, name, opts)
	opts = opts or {}
	if not PixelIcon.Bitmaps[name] then
		return nil
	end
	local after = opts.After == true
	local childName = opts.Name or (after and "TrailIcon" or "LeadIcon")
	local old = label:FindFirstChild(childName)
	if old then
		old:Destroy()
	end
	leadConns[label] = leadConns[label] or {}
	for _, c in ipairs(leadConns[label][childName] or {}) do
		c:Disconnect()
	end
	local px = PixelIcon.Snap(opts.Px or (tonumber(label.TextSize) or 18) * 0.9)
	local cell = math.floor(px / 9)
	local count = math.max(0, math.floor(tonumber(opts.Count) or 1))
	local of = math.max(count, math.floor(tonumber(opts.Of) or count), 1)
	-- (LOOK-ui, kitb-look1: the box from the snapped icon, not the icon from the box) under a 0.8 Fit a 2 px cell draws 2
	-- screen px (2.5 design), so an 18 px icon spans 22.5 design px: a box of 18 let it run into the label ("+Put in team",
	-- 0 px apart). The box is 9 whole-px cells wide per icon and the gap a whole 6 screen px (opts.Gap: design px, snapped),
	-- both again whenever the rest scale changes (metrics)
	local w, iconW, dc = of * px + (of - 1) * cell, px, cell
	local gap = tonumber(opts.Gap) or 6 -- (U7b) opts.Gap: px between the text and the icons
	local pad = label:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = label
	end
	-- the label's own insets, read once (a second call measures from them, not from the first icon's)
	local baseL, baseR = label:GetAttribute("LeadInsetL"), label:GetAttribute("LeadInsetR")
	if baseL == nil then
		baseL, baseR = pad.PaddingLeft.Offset, pad.PaddingRight.Offset
		label:SetAttribute("LeadInsetL", baseL)
		label:SetAttribute("LeadInsetR", baseR)
	end
	local box = Instance.new("Frame")
	box.Name = childName
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(w, px)
	box:SetAttribute("PixelIcon", name)
	box:SetAttribute("IconCount", count)
	local icons = {}
	-- (Pitch 2 item 9 B) no opts.Colour and the icon has its own: it keeps them (the label's colour does not tint it)
	local own = opts.Colour == nil and PixelIcon.Art[name] ~= nil
	for i = 1, of do
		local icon = PixelIcon.New(box, name, px, own and PixelIcon.Own or (opts.Colour or label.TextColor3))
		icon.Position = UDim2.fromOffset((i - 1) * (px + cell), 0)
		icons[i] = icon
	end
	local gapPx = gap
	-- the box, the icons in it and the gap for rest scale s: each icon's cells from the box's left, a cell apart
	local function metrics(s)
		s = (s and s > 0) and s or 1
		dc = screenCellOf(cell, s) / s -- (merge) the cell New draws (fitCells)
		iconW = 9 * dc
		w = of * iconW + (of - 1) * dc
		gap = opts.Gap and PixelIcon.Px(gapPx, s) or (gapPx / s)
		box.Size = UDim2.fromOffset(w, iconW)
		-- New centres its cells in its px box (a negative inset when they overflow it): undone here
		local inset = math.floor((px - 9 * dc) / 2 * s + 1e-6) / s
		for i, icon in ipairs(icons) do
			icon.Position = UDim2.fromOffset((i - 1) * (iconW + dc) - inset, -inset)
		end
	end
	metrics(restScaleOf(label))
	local function sync()
		box.ZIndex = label.ZIndex
		for i, icon in ipairs(icons) do
			icon.ZIndex = label.ZIndex
			-- an unlit icon of a rating is the same colour at a third of its strength
			local t = label.TextTransparency
			if i > count then
				t = 1 - (1 - t) * 0.35
			end
			for _, f in ipairs(icon:GetChildren()) do
				if f:IsA("Frame") then
					if not own then
						f.BackgroundColor3 = opts.Colour or label.TextColor3
					end
					f.BackgroundTransparency = composeT(f, t)
					f.ZIndex = label.ZIndex
				elseif f:IsA("ImageLabel") then
					f.ImageTransparency = t
					f.ZIndex = label.ZIndex
				end
			end
		end
	end
	local align = label.TextXAlignment
	-- (U9-7 look) the icon a whole design px from the label's padded box: its height from a fixed Size or, laid out, from
	-- AbsoluteSize (the label's own px), so the top is floor((h - px) / 2) and a centred text's icon floor(w / 2 ...) (half
	-- of an odd height or width put an icon on a half pixel); before the first layout the 0.5 scales
	local function padded()
		local s = scaleOf(label)
		local a = label.AbsoluteSize
		local pw, ph = nil, nil
		if a.X > 0 and a.Y > 0 and s > 0 then
			pw = math.floor(a.X / s + 0.5) - pad.PaddingLeft.Offset - pad.PaddingRight.Offset
			ph = math.floor(a.Y / s + 0.5) - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		local sy = label.Size.Y
		local auto = label.AutomaticSize == Enum.AutomaticSize.Y or label.AutomaticSize == Enum.AutomaticSize.XY
		if sy.Scale == 0 and sy.Offset > 0 and not auto then
			ph = sy.Offset - pad.PaddingTop.Offset - pad.PaddingBottom.Offset
		end
		return pw, ph
	end
	local function vertical(ph)
		-- (merge kitb-look1 x U9-9) a box PixelCrisp adopted (its own UIScale "Crisp" grows it round its AnchorPoint and
		-- snaps its origin) stays centred: from its top it grew down onto the block's lip
		if ph and not box:FindFirstChild("Crisp") then
			-- (LOOK-ui) the snapped icon's height, its top on a whole screen px of the padded box
			local s = restScaleOf(label)
			s = s > 0 and s or 1
			return 0, UDim.new(0, math.floor((ph - iconW) / 2 * s + 1e-6) / s)
		end
		return 0.5, UDim.new(0.5, 0)
	end
	-- a UIPadding insets the label's children as it insets the text, so the icon is placed in the same padded box as the
	-- letters: scale 0 / 0.5 / 1 are the text area's left edge, centre and right edge. TextBounds is screen px: back to
	-- the label's own px (a UIScale tween changes TextBounds, so a pop re-places it at the new scale). (U7b review) No
	-- bounds for a text that has letters (the server; a client before its first layout, which re-places on TextBounds):
	-- measured (measuredWidth)
	local function place()
		local textW = label.TextBounds.X / scaleOf(label)
		if textW <= 0 and label.Text ~= "" then
			textW = measuredWidth(label)
		end
		if opts.Room == true and after and align == Enum.TextXAlignment.Left then
			-- (render gate) a truncated text's bounds can run past its text area: the icons start at that area's end at most
			local okA, boxW = pcall(function()
				return label.AbsoluteSize.X / scaleOf(label)
			end)
			if okA and type(boxW) == "number" and boxW > 0 then
				textW = math.min(textW, boxW - pad.PaddingLeft.Offset - pad.PaddingRight.Offset)
			end
		end
		local rawW = textW
		textW = math.ceil(textW - 0.01) -- (U9-7 look) the icon a whole px from the text's measured end
		local pw, ph = padded()
		local ay, y = vertical(ph)
		box.AnchorPoint = Vector2.new(after and 0 or 1, ay)
		if align == Enum.TextXAlignment.Right then
			box.Position = after and UDim2.new(1, gap, y.Scale, y.Offset) or UDim2.new(1, -(textW + gap), y.Scale, y.Offset)
		elseif align == Enum.TextXAlignment.Center and label.Text == "" and not after then
			-- (U7b) icons alone on an empty centred label (a rating badge): centred in the label (the left inset moved the
			-- text area's centre right by half of w + gap)
			box.AnchorPoint = Vector2.new(0.5, ay)
			box.Position = UDim2.new(0.5, -math.floor((w + gap) / 2), y.Scale, y.Offset)
			if pw then
				box.AnchorPoint = Vector2.new(0, ay)
				box.Position = UDim2.new(0, math.floor(pw / 2 - (w + gap) / 2 - w / 2), y.Scale, y.Offset)
			end
		elseif align == Enum.TextXAlignment.Center then
			box.Position = UDim2.new(0.5, math.floor(after and (textW / 2 + gap) or -(textW / 2 + gap)), y.Scale, y.Offset)
			if pw then
				-- (LOOK-ui) the text's end snapped outward to a whole screen px, then the whole-px gap: never closer than it.
				-- (merge kitb-look1 x U9-7) whole px at REST: a window's entrance Pop (0.9 when it placed) left the icon
				-- 7.78 px from its label once the pop ended
				local s = restScaleOf(label)
				s = s > 0 and s or 1
				local edge = after and math.ceil((pw / 2 + rawW / 2) * s - 1e-6) / s or math.floor((pw / 2 - rawW / 2) * s + 1e-6) / s
				box.Position = UDim2.new(0, after and edge + gap or edge - gap, y.Scale, y.Offset)
			end
		else
			box.Position = after and UDim2.new(0, textW + gap, y.Scale, y.Offset) or UDim2.new(0, -gap, y.Scale, y.Offset)
		end
	end
	local function inset()
		if not after and align ~= Enum.TextXAlignment.Right then
			pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL + w + gap)
		elseif after and (align ~= Enum.TextXAlignment.Left or opts.Room == true) then
			pad.PaddingRight = UDim.new(pad.PaddingRight.Scale, baseR + w + gap)
		end
	end
	inset()
	sync()
	place()
	box.Parent = label
	if frozen then
		leadConns[label][childName] = nil
		return box
	end
	-- (LOOK-ui) a new rest scale (the window's Fit) sizes the box, the gap and the text's inset again
	PixelIcon.Whole(box, function(s)
		if box.Parent then
			metrics(s)
			inset()
			place()
		end
	end)
	leadConns[label][childName] = {
		label:GetPropertyChangedSignal("TextColor3"):Connect(sync),
		label:GetPropertyChangedSignal("TextTransparency"):Connect(sync),
		label:GetPropertyChangedSignal("ZIndex"):Connect(sync),
		label:GetPropertyChangedSignal("TextBounds"):Connect(place),
		label:GetPropertyChangedSignal("Text"):Connect(place),
		label:GetPropertyChangedSignal("Size"):Connect(place), -- (U9-7 look) a new height moves the icon's whole-px top
	}
	-- (U9-7 look) a laid-out size places the icon on whole px (padded()): every lead follows its label's AbsoluteSize
	table.insert(leadConns[label][childName], label:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	return box
end

-- (U7b) a status line's mark set on every refresh: PixelIcon.Lead only when the mark (name, Count, Of) changed since the
-- last call (the label's attribute Mark_<child>), PixelIcon.Clear when name is nil. Cheap to call each frame
function PixelIcon.Mark(label, name, opts)
	opts = opts or {}
	local attr = "Mark_" .. (opts.Name or (opts.After == true and "TrailIcon" or "LeadIcon"))
	local key = name and (name .. ":" .. tostring(opts.Count or "") .. ":" .. tostring(opts.Of or "")) or ""
	if label:GetAttribute(attr) == key then
		return
	end
	label:SetAttribute(attr, key)
	if name then
		PixelIcon.Lead(label, name, opts)
	else
		PixelIcon.Clear(label, opts)
	end
end

-- (U7b) PixelIcon.Host only when the icon changed since the last call (the host's attribute HostMark); nil or an
-- unknown name drops the icon. For a glyph label a refresh rewrites (a ready tick, a lock badge that comes and goes)
function PixelIcon.Set(host, name, px, colour)
	local key = (name and PixelIcon.Bitmaps[name]) and (name .. ":" .. tostring(px or "")) or ""
	if host:GetAttribute("HostMark") == key then
		return
	end
	host:SetAttribute("HostMark", key)
	host.Text = ""
	PixelIcon.Host(host, key ~= "" and name or "", px, colour)
end

-- (U7b) takes the icon PixelIcon.Lead put on `label` off again (opts.After / opts.Name as given to Lead) and puts the
-- label's own insets back: a row whose mark comes and goes (a pet that stops training, a rating that drops to none)
function PixelIcon.Clear(label, opts)
	opts = opts or {}
	local after = opts.After == true
	local childName = opts.Name or (after and "TrailIcon" or "LeadIcon")
	local old = label:FindFirstChild(childName)
	if old then
		old:Destroy()
	end
	if leadConns[label] then
		for _, c in ipairs(leadConns[label][childName] or {}) do
			c:Disconnect()
		end
		leadConns[label][childName] = nil
	end
	local pad = label:FindFirstChildOfClass("UIPadding")
	local baseL, baseR = label:GetAttribute("LeadInsetL"), label:GetAttribute("LeadInsetR")
	if pad and baseL ~= nil then
		if after then
			pad.PaddingRight = UDim.new(pad.PaddingRight.Scale, baseR)
		else
			pad.PaddingLeft = UDim.new(pad.PaddingLeft.Scale, baseL)
		end
	end
end

return PixelIcon
