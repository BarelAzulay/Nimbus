param([string]$Name, [string]$OutDir, [string]$Root)
$Cmd = $args
# one run, one at a time: free memory first (below 2 GB: wait 120 s, up to 10 times), then the command, its output to <OutDir>\<Name>.txt
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = Join-Path $OutDir "runs_memory.txt"
$free = 0
for ($i = 0; $i -lt 11; $i++) {
    $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
    if ($free -ge 2) { break }
    if ($i -eq 10) { Add-Content $log ("{0} free {1} GB before {2}: STILL LOW after 10 waits, not run" -f (Get-Date -Format HH:mm:ss), $free, $Name); Write-Output "LOWMEM $free"; exit 99 }
    Add-Content $log ("{0} free {1} GB before {2}: low, waiting 120 s" -f (Get-Date -Format HH:mm:ss), $free, $Name)
    Start-Sleep 120
}
Add-Content $log ("{0} free {1} GB before {2}" -f (Get-Date -Format HH:mm:ss), $free, $Name)
Set-Location $Root
$sw = [Diagnostics.Stopwatch]::StartNew()
$exe = $Cmd[0]
$rest = @()
if ($Cmd.Count -gt 1) { $rest = $Cmd[1..($Cmd.Count - 1)] }
$out = Join-Path $OutDir ($Name + ".txt")
& $exe @rest *> $out
$code = $LASTEXITCODE
$sw.Stop()
$last = (Get-Content $out -Tail 3 | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 1)
Add-Content $log ("{0} {1}: exit {2}, {3:N0} s: {4}" -f (Get-Date -Format HH:mm:ss), $Name, $code, $sw.Elapsed.TotalSeconds, $last)
Write-Output ("{0}: exit {1}, {2:N0} s: {3}" -f $Name, $code, $sw.Elapsed.TotalSeconds, $last)

