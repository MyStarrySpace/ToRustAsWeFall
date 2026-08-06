param(
    [string]$Output = "playthrough.trwfplay",
    [string]$Godot = "",
    [string]$GeneratedCase = "",
    [switch]$AllowVisibleWindow
)

# This is the human recording launcher: the player must be able to see and
# control the game. It is deliberately not an automated-test entry point.
# Requiring an explicit Windows opt-in prevents an agent or background job from
# accidentally treating Start-Process -WindowStyle Hidden as gameplay-window
# isolation. That switch hides the console host, not Godot's GUI child.
if ($env:OS -eq "Windows_NT" -and -not $AllowVisibleWindow) {
    throw @"
record_playthrough.ps1 intentionally opens a visible gameplay window on Windows.
Pass -AllowVisibleWindow only for an attended human recording. Automated tests,
persona playthroughs, and approval evidence must use scripts/test-gate.ps1 so the
reviewed hidden-owner window contract is applied before Godot creates its window.
"@
}

$project = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Godot)) {
    $candidates = @(
        (Join-Path (Split-Path -Parent $project) "Godot_v4.7-stable_win64_console.exe"),
        (Join-Path (Split-Path -Parent $project) "Godot_v4.6.1-stable_win64_console.exe")
    )
    $Godot = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($Godot) -or -not (Test-Path -LiteralPath $Godot)) {
    throw "Godot console executable not found. Pass -Godot with its full path."
}

$outputPath = [System.IO.Path]::GetFullPath($Output)
$logDir = Join-Path $project ".qa-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir "record-playthrough.log"
Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
$userArgs = @("--record-playthrough", $outputPath)
if (-not [string]::IsNullOrWhiteSpace($GeneratedCase)) {
    $userArgs += @("--autoplay-generated-case", $GeneratedCase)
}
$arguments = @("--log-file", "`"$logPath`"", "--path", "`"$project`"", "--")
$arguments += $userArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
exit $process.ExitCode
