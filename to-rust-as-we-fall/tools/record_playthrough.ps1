param(
    [string]$Output = "playthrough.trwfplay",
    [string]$Godot = "",
    [string]$GeneratedCase = ""
)

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
