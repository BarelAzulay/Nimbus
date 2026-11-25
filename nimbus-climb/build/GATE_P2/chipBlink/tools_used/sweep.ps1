param([string[]]$Holds, [string]$Fps = "30")
# the hold sweep: set GUIDE_SIGN_DWELL (TutorialController) and CLEAR (the pin) to each value, run travel_guide_plank once
$s = "C:\Users\elmoz\AppData\Local\Temp\claude\720d721f86976893\16505500-acfa-419a-a670-3d03d6c73e6b\scratchpad"
$w = "C:\Users\elmoz\OneDrive\שולחן העבודה\Projects Main\Nimbus\.worktrees\kitb-chip-blink\nimbus-climb"
$tc = Join-Path $w "src\client\Controllers\TutorialController.lua"
$sm = Join-Path $w "tools\smoke_kitb_world.lua"
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($h in $Holds) {
    $a = [IO.File]::ReadAllText($tc, $utf8)
    $a = [regex]::Replace($a, 'GUIDE_SIGN_DWELL = [\d.]+,', "GUIDE_SIGN_DWELL = $h,")
    [IO.File]::WriteAllText($tc, $a, $utf8)
    $b = [IO.File]::ReadAllText($sm, $utf8)
    $b = [regex]::Replace($b, 'local KEEP, HOLD, DWELL, READ, CLEAR = 6, 12, 0\.5, 1 / 15, [\d.]+', "local KEEP, HOLD, DWELL, READ, CLEAR = 6, 12, 0.5, 1 / 15, $h")
    [IO.File]::WriteAllText($sm, $b, $utf8)
    $tag = "hold" + ($h -replace '\.', '') + "_fps" + $Fps
    & "$s\run1.ps1" ($tag + "_travel_guide_plank") "$w\build\GATE_P2\chipBlink\hold_sweep" $w py -3.12 tools/smoke.py --only travel_guide_plank --fps $Fps -v
    $l = Get-Content "$w\build\GATE_P2\chipBlink\hold_sweep\$($tag)_travel_guide_plank.txt"
    $l | Select-String "^\s*FAIL" | ForEach-Object { $_.Line.Substring(0, [math]::Min(260, $_.Line.Length)) }
}
