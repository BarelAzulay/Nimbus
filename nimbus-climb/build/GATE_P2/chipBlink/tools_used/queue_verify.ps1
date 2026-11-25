param([string]$Only = "")
# the verification queue after the last source edit: one run at a time, free memory checked before each (run1.ps1)
$s = "C:\Users\elmoz\AppData\Local\Temp\claude\720d721f86976893\16505500-acfa-419a-a670-3d03d6c73e6b\scratchpad"
$w = "C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\kitb-chip-blink\nimbus-climb"
$o = "$w\build\GATE_P2\chipBlink\verify"
$walk = "travel_guide_walk,travel_guide_walk_pans,travel_guide_walk_pans_b,travel_guide_walk_looks"
$pins = "guide_pins,guide_pins_walks,guide_pins_turns,guide_pins_pan6,guide_pins_pan6_b,guide_pins_pan6_c,guide_pins_pan12,guide_pins_pan12_b,guide_pins_pans,guide_pins_sways,guide_pins_looks"
$jobs = @(
    @("smoke_travel_guide_plank", "py", "-3.12", "tools/smoke.py", "--only", "travel_guide_plank", "-v"),
    @("smoke_travel_guide_plank_wide", "py", "-3.12", "tools/smoke.py", "--only", "travel_guide_plank_wide"),
    @("smoke_travel_guide_clear", "py", "-3.12", "tools/smoke.py", "--only", "travel_guide_clear"),
    @("smoke_travel_shows_way", "py", "-3.12", "tools/smoke.py", "--only", "travel_shows_way"),
    @("smoke_tutorial_dock_b", "py", "-3.12", "tools/smoke.py", "--only", "tutorial_dock_b"),
    @("smoke_tutorial_fits_phone", "py", "-3.12", "tools/smoke.py", "--only", "tutorial_fits_phone"),
    @("smoke_tutorial_signboard_skin", "py", "-3.12", "tools/smoke.py", "--only", "tutorial_signboard_skin"),
    @("smoke_tutorial_pointer_kitb", "py", "-3.12", "tools/smoke.py", "--only", "tutorial_pointer_kitb"),
    @("smoke_client_bug2tut_portrait", "py", "-3.12", "tools/smoke.py", "--only", "client_bug2tut_portrait"),
    @("smoke_client_bug2tut_raidnext", "py", "-3.12", "tools/smoke.py", "--only", "client_bug2tut_raidnext"),
    @("smoke_client_bug2tut_mouse", "py", "-3.12", "tools/smoke.py", "--only", "client_bug2tut_mouse"),
    @("smoke_client_p3fixcli_tutorial", "py", "-3.12", "tools/smoke.py", "--only", "client_p3fixcli_tutorial"),
    @("check_mjs", "node", "tools/check.mjs"),
    @("smoke_travel_guide_walk_lists", "py", "-3.12", "tools/smoke.py", "--only", $walk),
    @("smoke_guide_pins_lists", "py", "-3.12", "tools/smoke.py", "--only", $pins),
    @("battle_hud_no_overlap", "py", "-3.12", "tools/battle_hud_no_overlap.py"),
    @("stroke_walk_grid_neon", "py", "-3.12", "tools/stroke_walk.py", "--grid", "--neon"),
    @("look_pins_all", "py", "-3.12", "tools/look_pins.py")
)
foreach ($j in $jobs) {
    if ($Only -ne "" -and ($Only.Split(",") -notcontains $j[0])) { continue }
    $rest = $j[1..($j.Count - 1)]
    & "$s\run1.ps1" $j[0] $o $w @rest
    if ($LASTEXITCODE -eq 99) { Write-Output "QUEUE STOPPED: low memory"; break }
}
Add-Content "$o\runs_memory.txt" ("{0} QUEUE DONE" -f (Get-Date -Format HH:mm:ss))
Write-Output "QUEUE DONE"
