# everything after the last source edit, one run at a time (run1.ps1 checks free memory before each)
$s = "C:\Users\elmoz\AppData\Local\Temp\claude\720d721f86976893\16505500-acfa-419a-a670-3d03d6c73e6b\scratchpad"
$w = "C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\kitb-chip-blink\nimbus-climb"
$tree = "$s\tree_58a4c0e\nimbus-climb"
$o = "$w\build\GATE_P2\chipBlink"
$sizes = "640x360,667x375,720x405,800x450,844x390,960x540,1024x768,1280x720,1920x1080,2560x1440"
$states = "guidechip:lobby,guidechip:boosts,guidechip:toasts,guidechip:tutorial:3,guidechip:tutorial:3:fold,guidechip:mousehint,guidechip:party,guidechip:party:leader,guidechip:match:4,guidechip:countdown,guidechip:away,guidechip:here,guidechip:dungeon,guidechip:arenaside,guidechip:npc,guidechip:window,worldui:guide,worldui:guideahead,worldui:guidehere,worldui:guidenear,worldui:guidetilt"
# 1. the final pin at 58a4c0e's source (red)
& "$s\run1.ps1" red_final_pin_at_58a4c0e "$o\red" $tree py -3.12 tools/smoke.py --only travel_guide_plank -v
# 2. the verification lists at HEAD
& "$s\queue_verify.ps1"
# 3. the guide stills, landscape and PC, before (58a4c0e) and after (HEAD), then the pixel compare
& "$s\run1.ps1" render_before_58a4c0e "$o\pixels" $w py -3.12 "$s\tools_mine\sweep.py" $tree "$o\pixels\before" $sizes $states
& "$s\run1.ps1" render_after_HEAD "$o\pixels" $w py -3.12 "$s\tools_mine\sweep.py" $w "$o\pixels\after" $sizes $states
& "$s\run1.ps1" pixel_compare "$o\pixels" $w py -3.12 "$s\tools_mine\cmp_sweeps.py" "$o\pixels\before" "$o\pixels\after"
& "$s\run1.ps1" pixel_compare_selftest "$o\pixels" $w py -3.12 "$s\tools_mine\cmp_selftest.py" "$o\pixels\after"
Write-Output "ALL DONE"
