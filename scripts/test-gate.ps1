[CmdletBinding()]
param(
    [ValidateSet('Headless', 'Windowed', 'Web', 'Release', 'All')]
    [string[]] $Tier = @('Headless'),
    [string] $GodotPath,
    [string] $BrowserPath,
    [string] $ProjectPath,
    [string] $ArtifactDirectory,
    [ValidateRange(1, 86400)]
    [int] $TimeoutSeconds = 3600,
    [switch] $WebDependenciesReady,
    [string] $FocusedHeadlessTest,
    [string] $FocusedWindowedTest,
    [string] $PersonaDistillationRequest,
    [switch] $RegenerateGeneratedBaselines,
    [switch] $SelfTest,
    [int] $SyntheticChildExitCode = -1,
    [switch] $SyntheticSkip,
    [switch] $SyntheticHang,
    [switch] $SyntheticRuntimeError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:FocusedHeadlessRequested =
    $PSBoundParameters.ContainsKey('FocusedHeadlessTest')
$script:FocusedWindowedRequested =
    $PSBoundParameters.ContainsKey('FocusedWindowedTest')
$script:FocusedDiagnosticRequested =
    $script:FocusedHeadlessRequested -or $script:FocusedWindowedRequested
$script:PersonaDistillationRequested =
    $PSBoundParameters.ContainsKey('PersonaDistillationRequest')
$script:GeneratedBaselineRegenerationRequested =
    $PSBoundParameters.ContainsKey('RegenerateGeneratedBaselines')

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $RepoRoot 'to-rust-as-we-fall'
}
$ProjectPath = [System.IO.Path]::GetFullPath($ProjectPath)
if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    $ArtifactDirectory = Join-Path $RepoRoot '.test-gate'
}
$ArtifactDirectory = [System.IO.Path]::GetFullPath($ArtifactDirectory)
$RunId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $PID
$RunArtifactDirectory = Join-Path $ArtifactDirectory $RunId
New-Item -ItemType Directory -Force -Path $RunArtifactDirectory | Out-Null

$script:InvocationIndex = 0
$script:WindowedOffscreenPosition = '20000,20000'

# Required by every release tier before tier-specific work begins. Keeping this
# verifier in a shared preflight manifest makes a combined Windowed+Web launch
# run it once rather than relying on a separate Headless launch or duplicating
# it in both platform tiers.
$script:GatePreflightManifest = [ordered] @{
    AgentPlayerInputBoundary = [PSCustomObject] @{
        Label = 'preflight-agent-player-input-boundary'
        LaunchMode = 'Headless'
        EntryPoint = 'res://tools/verify_agent_player_input_boundary.gd'
        TestArguments = @()
    }
}

# This manifest is the single source of truth for tier-specific required gate
# invocations. Runtime dispatch consumes it directly, while -SelfTest validates
# its exact contract (including argument order) and the package.json Web
# resolution.
$script:GateTierManifest = [ordered] @{
    Headless = [PSCustomObject] @{
        Kind = 'Native'
        Invocations = @(
            [PSCustomObject] @{
                Label = 'headless-test-all'
                LaunchMode = 'Headless'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-all', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'headless-aster-drink-authority'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_aster_drink_authority.gd'
                TestArguments = @()
            }
            [PSCustomObject] @{
                Label = 'headless-persona-decision-pipeline'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_persona_decision_pipeline.gd'
                TestArguments = @()
            }
            [PSCustomObject] @{
                Label = 'headless-generated-actionable-approaches'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_generated_actionable_approaches.gd'
                TestArguments = @()
            }
        )
    }
    Windowed = [PSCustomObject] @{
        Kind = 'Native'
        Invocations = @(
            [PSCustomObject] @{
                Label = 'windowed-player-contract'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-player-contract', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-player-observation'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-player-observation', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-basin-player-journey'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-basin-player-journey', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-persona-probe'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-persona-probe', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-player-surface-matrix'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-generated-player-surface-matrix', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-stretch-playtest-loop'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-generated-stretch-playtest-loop', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-interaction-truth'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://tools/verify_generated_interaction_truth.gd'
                TestArguments = @()
            }
        )
    }
    Web = [PSCustomObject] @{
        Kind = 'Web'
        NpmScript = 'test:web:basin'
        ExpectedNpmCommand = 'playwright test tests/web/basin-fill-proof.spec.mjs --repeat-each=2'
        PlaywrightSpec = 'tests/web/basin-fill-proof.spec.mjs'
    }
}

function Write-GateError {
    param([Parameter(Mandatory = $true)][string] $Message)
    [Console]::Error.WriteLine("[GATE] ERROR: $Message")
}

function Test-FocusedTestFlag {
    param([AllowEmptyString()][string] $Value)

    # Do not use PowerShell's -match operator here: it is case-insensitive by
    # default. This is deliberately a one-token, lowercase-only CLI surface;
    # no value, whitespace, '=' payload, second flag, path, or script argument
    # may cross from an agent command into Godot.
    return $null -ne $Value -and [regex]::IsMatch(
        $Value,
        '^--test-[a-z0-9-]+$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

if ($script:FocusedHeadlessRequested) {
    if (-not (Test-FocusedTestFlag -Value $FocusedHeadlessTest)) {
        Write-GateError (
            'FocusedHeadlessTest must be exactly one lowercase ' +
            '--test-[a-z0-9-]+ token.')
        exit 64
    }
    if ($PSBoundParameters.ContainsKey('Tier') -or $SelfTest -or
            $script:FocusedWindowedRequested -or
            $script:PersonaDistillationRequested -or
            $script:GeneratedBaselineRegenerationRequested -or
            $SyntheticChildExitCode -ge 0 -or $SyntheticSkip -or
            $SyntheticHang -or $SyntheticRuntimeError -or
            $WebDependenciesReady) {
        Write-GateError (
            'FocusedHeadlessTest is an exclusive diagnostic mode and cannot ' +
            'be combined with Tier, SelfTest, WebDependenciesReady, persona ' +
            'distillation, another focused runtime, or synthetic self-test legs.')
        exit 64
    }
}

if ($script:FocusedWindowedRequested) {
    if (-not (Test-FocusedTestFlag -Value $FocusedWindowedTest)) {
        Write-GateError (
            'FocusedWindowedTest must be exactly one lowercase ' +
            '--test-[a-z0-9-]+ token.')
        exit 64
    }
    if ($PSBoundParameters.ContainsKey('Tier') -or $SelfTest -or
            $script:FocusedHeadlessRequested -or
            $script:PersonaDistillationRequested -or
            $script:GeneratedBaselineRegenerationRequested -or
            $SyntheticChildExitCode -ge 0 -or $SyntheticSkip -or
            $SyntheticHang -or $SyntheticRuntimeError -or
            $WebDependenciesReady) {
        Write-GateError (
            'FocusedWindowedTest is an exclusive diagnostic mode and cannot ' +
            'be combined with Tier, SelfTest, WebDependenciesReady, persona ' +
            'distillation, another focused runtime, or synthetic self-test legs.')
        exit 64
    }
}

if ($script:PersonaDistillationRequested -and
        ($PSBoundParameters.ContainsKey('Tier') -or $SelfTest -or
         $script:FocusedDiagnosticRequested -or
         $script:GeneratedBaselineRegenerationRequested -or
         $SyntheticChildExitCode -ge 0 -or $SyntheticSkip -or
         $SyntheticHang -or $SyntheticRuntimeError -or
         $WebDependenciesReady)) {
    Write-GateError (
        'PersonaDistillationRequest is an exclusive internal contained-Godot mode.')
    exit 64
}

if ($script:GeneratedBaselineRegenerationRequested -and
        ($PSBoundParameters.ContainsKey('Tier') -or $SelfTest -or
         $script:FocusedDiagnosticRequested -or
         $script:PersonaDistillationRequested -or
         $SyntheticChildExitCode -ge 0 -or $SyntheticSkip -or
         $SyntheticHang -or $SyntheticRuntimeError -or
         $WebDependenciesReady)) {
    Write-GateError (
        'RegenerateGeneratedBaselines is an exclusive contained-Godot maintenance mode.')
    exit 64
}

function ConvertTo-NativeArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    # Windows' CommandLineToArgvW quoting rules. The same quoting is harmless on
    # PowerShell 7/Unix, and lets Start-Process preserve arguments containing spaces.
    $builder = New-Object System.Text.StringBuilder
    [void] $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes += 1
            continue
        }
        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                [void] $builder.Append((('\' * ($backslashes * 2)) -join ''))
            }
            [void] $builder.Append('\"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void] $builder.Append((('\' * $backslashes) -join ''))
            $backslashes = 0
        }
        [void] $builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void] $builder.Append((('\' * ($backslashes * 2)) -join ''))
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function Get-NativeGodotArguments {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Headless', 'Windowed')]
        [string] $LaunchMode,
        [Parameter(Mandatory = $true)][string] $EntryPoint,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $TestArguments,
        [string] $EmbeddedWindowId = '',
        [string] $OffscreenPosition = $script:WindowedOffscreenPosition
    )

    $engineArguments = if ($LaunchMode -eq 'Headless') {
        @('--headless', '--path', $ProjectPath)
    } else {
        if ($env:OS -eq 'Windows_NT' -and [string]::IsNullOrWhiteSpace($EmbeddedWindowId)) {
            throw 'A Windows Windowed test requires a never-shown parent HWND for --wid embedding.'
        }
        @(
            '--path', $ProjectPath,
            # On Windows, --wid makes Godot create its render HWND as a child of
            # the launcher's never-shown parent. The far-edge request remains a
            # non-Windows and defense-in-depth fallback; Windows itself clamps it.
            $(if (-not [string]::IsNullOrWhiteSpace($EmbeddedWindowId)) { '--wid' }),
            $(if (-not [string]::IsNullOrWhiteSpace($EmbeddedWindowId)) { $EmbeddedWindowId }),
            '--windowed',
            '--position', $OffscreenPosition,
            # Native popup windows consult desktop cursor/focus state. Embed
            # them so app-local InputEvents remain the only input authority.
            '--single-window',
            '--rendering-method', 'gl_compatibility',
            '--audio-driver', 'Dummy'
        )
    }
    if ($EntryPoint.EndsWith('.gd', [System.StringComparison]::OrdinalIgnoreCase)) {
        $scriptArguments = @($engineArguments) + @('--script', $EntryPoint)
        if ($TestArguments.Count -gt 0) {
            $scriptArguments += @('--') + @($TestArguments)
        }
        return $scriptArguments
    }
    return @($engineArguments) + @($EntryPoint, '--') + @($TestArguments)
}

function Test-PathWithinDirectory {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Directory
    )

    $candidate = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($Directory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    return $candidate.StartsWith($root, $comparison)
}

function Read-PersonaDistillationRequest {
    param([Parameter(Mandatory = $true)][string] $RequestPath)

    if (-not [System.IO.Path]::IsPathRooted($RequestPath)) {
        throw 'Persona distillation request path must be absolute.'
    }
    $resolvedRequestPath = [System.IO.Path]::GetFullPath($RequestPath)
    if (-not (Test-PathWithinDirectory -Path $resolvedRequestPath `
                -Directory $ArtifactDirectory) -or
            -not (Test-Path -LiteralPath $resolvedRequestPath -PathType Leaf)) {
        throw 'Persona distillation request must be an existing artifact-owned file.'
    }
    try {
        $request = Get-Content -LiteralPath $resolvedRequestPath -Raw |
            ConvertFrom-Json
    } catch {
        throw "Persona distillation request is not valid JSON: $_"
    }
    if ($null -eq $request -or $request -is [System.Array]) {
        throw 'Persona distillation request must be one JSON object.'
    }
    $propertyNames = @($request.PSObject.Properties.Name | Sort-Object)
    $expectedPropertyNames = @('output', 'schema', 'traces')
    if (($propertyNames -join "`0") -cne
            ($expectedPropertyNames -join "`0") -or
            [string] $request.schema -cne
                'persona_distillation_request_v1') {
        throw 'Persona distillation request has an unexpected schema or property set.'
    }
    $traceValues = @($request.traces)
    if ($traceValues.Count -ne 4) {
        throw 'Persona distillation request must name exactly four trace files.'
    }
    $tracePaths = New-Object System.Collections.Generic.List[string]
    foreach ($traceValue in $traceValues) {
        if ($traceValue -isnot [string] -or
                -not [System.IO.Path]::IsPathRooted($traceValue)) {
            throw 'Every persona distillation trace path must be an absolute string.'
        }
        $tracePath = [System.IO.Path]::GetFullPath([string] $traceValue)
        if (-not (Test-PathWithinDirectory -Path $tracePath `
                    -Directory $ArtifactDirectory) -or
                -not (Test-Path -LiteralPath $tracePath -PathType Leaf)) {
            throw "Persona distillation trace is not an artifact-owned file: $tracePath"
        }
        [void] $tracePaths.Add($tracePath)
    }
    if (@($tracePaths | Select-Object -Unique).Count -ne 4) {
        throw 'Persona distillation request trace paths must be unique.'
    }
    if ($request.output -isnot [string] -or
            -not [System.IO.Path]::IsPathRooted([string] $request.output)) {
        throw 'Persona distillation output path must be an absolute string.'
    }
    $outputPath = [System.IO.Path]::GetFullPath([string] $request.output)
    if (-not (Test-PathWithinDirectory -Path $outputPath `
                -Directory $ArtifactDirectory) -or
            [System.IO.Path]::GetExtension($outputPath) -cne '.json' -or
            (Test-Path -LiteralPath $outputPath)) {
        throw 'Persona distillation output must be a new artifact-owned .json path.'
    }
    if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName(
                    $outputPath)) -PathType Container)) {
        throw 'Persona distillation output parent directory does not exist.'
    }
    return [PSCustomObject] @{
        RequestPath = $resolvedRequestPath
        TracePaths = @($tracePaths)
        OutputPath = $outputPath
    }
}

function Get-ProjectExecutableTestSourceFiles {
    param([Parameter(Mandatory = $true)][string] $Directory)

    $sourceExtensions = @(
        '.gd', '.cs', '.c', '.cc', '.cpp', '.h', '.hh', '.hpp',
        '.py', '.ps1', '.bat', '.cmd', '.sh', '.js', '.mjs', '.ts'
    )
    Get-ChildItem -LiteralPath $Directory -File -ErrorAction Stop | Where-Object {
        $sourceExtensions -contains $_.Extension.ToLowerInvariant()
    }
    foreach ($childDirectory in @(Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction Stop)) {
        if ($childDirectory.Name -in @('.godot', 'Godot', 'node_modules', 'build')) {
            continue
        }
        Get-ProjectExecutableTestSourceFiles -Directory $childDirectory.FullName
    }
}

function Get-ProjectRelativeSourcePath {
    param([Parameter(Mandatory = $true)][string] $FullPath)

    $normalizedRoot = $ProjectPath.TrimEnd('\', '/')
    $normalizedPath = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $normalizedPath.StartsWith(
            $normalizedRoot + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path is outside the project root: $normalizedPath"
    }
    return $normalizedPath.Substring($normalizedRoot.Length + 1).Replace('\', '/')
}

function Test-AutomatedInputSourcePath {
    param([Parameter(Mandatory = $true)][string] $RelativePath)

    $normalized = $RelativePath.Replace('\', '/').TrimStart('/')
    if ($normalized.StartsWith('tools/', [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith('tests/', [System.StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith('scripts/testing/', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $normalized -in @(
        'scripts/test_runner_cli.gd',
        'scripts/test_bootstrap.gd',
        'scripts/generation/stretch_generation_playtest_loop.gd',
        'scripts/fragments/preview_web_e2e_controller.gd',
        'scripts/system/playthrough_session.gd'
    )
}

function Test-ConstructedIdentifier {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory = $true)][string] $IdentifierWithoutUnderscores
    )

    # Detect identifier strings assembled from two or more literal fragments,
    # including GDScript StringName's `&"..."` spelling. Restrict each fragment
    # to identifier characters so unrelated prose or adjacent strings cannot
    # create a false positive when their punctuation is compacted.
    $literalChainPattern =
        '(?is)(?:&?["''][A-Za-z0-9_]+["'']\s*\+\s*)+&?["''][A-Za-z0-9_]+["'']'
    foreach ($literalChain in [regex]::Matches($Source, $literalChainPattern)) {
        $compact = [regex]::Replace(
            $literalChain.Value, '[_\s"''&+]', '').ToLowerInvariant()
        if ($compact.Contains($IdentifierWithoutUnderscores.ToLowerInvariant())) {
            return $true
        }
    }
    return $false
}

function Get-CursorIsolationPolicyViolations {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Source,
        [Parameter(Mandatory = $true)][string] $RelativePath
    )

    $violations = New-Object System.Collections.Generic.List[string]
    $identifierCompactSource = $Source.Replace('_', '')
    if ($identifierCompactSource.IndexOf(
            'warpmouse', [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            (Test-ConstructedIdentifier -Source $Source `
                -IdentifierWithoutUnderscores 'warpmouse')) {
        [void] $violations.Add('cursor-warp-symbol')
    }

    $isAutomatedInputSource = Test-AutomatedInputSourcePath -RelativePath $RelativePath
    if ($isAutomatedInputSource) {
        foreach ($forbiddenAutomationSymbol in @(
            'set_mouse_mode',
            'mouse_set_mode',
            'MOUSE_MODE_CAPTURED',
            'MOUSE_MODE_CONFINED',
            'MOUSE_MODE_CONFINED_HIDDEN',
            'MouseModeEnum.Captured',
            'MouseModeEnum.Confined',
            'MouseModeEnum.ConfinedHidden',
            'SetCursorPos',
            'SetPhysicalCursorPos',
            'ClipCursor',
            'SetCapture',
            'ReleaseCapture',
            'SendInput',
            'mouse_event',
            'CGWarpMouseCursorPosition',
            'CGAssociateMouseAndMouseCursorPosition',
            'XWarpPointer',
            'XGrabPointer',
            'SDL_WarpMouse',
            'SDL_SetRelativeMouseMode',
            'SDL_CaptureMouse',
            'glfwSetCursorPos',
            'GLFW_CURSOR_DISABLED',
            'GLFW_CURSOR_CAPTURED',
            'Cursor.Position',
            'Cursor]::Position',
            'pyautogui',
            'AutoIt',
            'pynput',
            'robotjs'
        )) {
            if ($Source.IndexOf(
                    $forbiddenAutomationSymbol,
                    [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void] $violations.Add("automated-os-pointer:$forbiddenAutomationSymbol")
            }
        }
    }

    $normalizedPath = $RelativePath.Replace('\', '/').TrimStart('/')
    if ($normalizedPath -ine 'tools/offscreen_window.gd') {
        foreach ($forbiddenWindowSymbol in @(
            'window_set_position',
            'window_move_to_foreground',
            'window_set_mode'
        )) {
            $compactWindowSymbol = $forbiddenWindowSymbol.Replace('_', '')
            if ($identifierCompactSource.IndexOf(
                    $compactWindowSymbol,
                    [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    (Test-ConstructedIdentifier -Source $Source `
                        -IdentifierWithoutUnderscores $compactWindowSymbol)) {
                [void] $violations.Add("window-lifetime:$forbiddenWindowSymbol")
            }
        }
        $typedWindowIdentifiers = New-Object System.Collections.Generic.List[string]
        $typedWindowPattern = '(?im)(?:\bvar\s+)?(?<gd>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*Window\b|\bWindow\s+(?<cs>[A-Za-z_][A-Za-z0-9_]*)\b'
        foreach ($typedWindowMatch in [regex]::Matches($Source, $typedWindowPattern)) {
            $typedWindowIdentifier = if ($typedWindowMatch.Groups['gd'].Success) {
                $typedWindowMatch.Groups['gd'].Value
            } else {
                $typedWindowMatch.Groups['cs'].Value
            }
            if (-not [string]::IsNullOrWhiteSpace($typedWindowIdentifier)) {
                [void] $typedWindowIdentifiers.Add(
                    [regex]::Escape($typedWindowIdentifier))
            }
        }
        $windowAliasPattern = '(?im)^[ \t]*(?:@onready[ \t]+)?(?:var[ \t]+)?(?<alias>[A-Za-z_][A-Za-z0-9_]*)[ \t]*(?::=|=)[ \t]*(?:(?:get_?window|window)[ \t]*\([ \t]*\)|get_viewport[ \t]*\([ \t]*\)[ \t]*\.[ \t]*get_?window[ \t]*\([ \t]*\)|get_tree[ \t]*\([ \t]*\)[ \t]*\.[ \t]*root)[ \t]*;?[ \t]*(?:(?:#|//).*)?$'
        foreach ($windowAliasMatch in [regex]::Matches($Source, $windowAliasPattern)) {
            $windowAliasIdentifier = $windowAliasMatch.Groups['alias'].Value
            if (-not [string]::IsNullOrWhiteSpace($windowAliasIdentifier)) {
                [void] $typedWindowIdentifiers.Add(
                    [regex]::Escape($windowAliasIdentifier))
            }
        }
        $typedReceiverSuffix = if ($typedWindowIdentifiers.Count -gt 0) {
            '|\b(?:' + (($typedWindowIdentifiers | Select-Object -Unique) -join '|') + ')\b'
        } else {
            ''
        }
        $windowReceiverPattern = '(?:\bWindow\b|\b(?:get_?window|window)\s*\(\s*\)|\bget_viewport\s*\(\s*\)\s*\.\s*get_?window\s*\(\s*\)|\bget_tree\s*\(\s*\)\s*\.\s*root|\b[A-Za-z_][A-Za-z0-9_]*window[A-Za-z0-9_]*' + $typedReceiverSuffix + ')'
        foreach ($windowAlternative in @(
            [PSCustomObject] @{
                Token = 'Window.position'
                Pattern = "(?im)$windowReceiverPattern\s*\.\s*position\s*="
            }
            [PSCustomObject] @{
                Token = 'Window.position'
                Pattern = "(?im)$windowReceiverPattern\s*\.\s*set_?position\s*\("
            }
            [PSCustomObject] @{
                Token = 'Window.position'
                Pattern = '(?im)' + $windowReceiverPattern + '\s*\.\s*(?:set|set_deferred|call)\s*\(\s*(?:StringName\s*\(\s*)?&?["''](?:set_?)?position["'']'
            }
            [PSCustomObject] @{
                Token = 'Window.mode'
                Pattern = "(?im)$windowReceiverPattern\s*\.\s*mode\s*="
            }
            [PSCustomObject] @{
                Token = 'Window.mode'
                Pattern = "(?im)$windowReceiverPattern\s*\.\s*set_?mode\s*\("
            }
            [PSCustomObject] @{
                Token = 'Window.mode'
                Pattern = '(?im)' + $windowReceiverPattern + '\s*\.\s*(?:set|set_deferred|call)\s*\(\s*(?:StringName\s*\(\s*)?&?["''](?:set_?)?mode["'']'
            }
            [PSCustomObject] @{
                Token = 'Window.move_to_foreground'
                Pattern = "(?im)$windowReceiverPattern\s*\.\s*move_?to_?foreground\s*\("
            }
            [PSCustomObject] @{
                Token = 'Window.move_to_foreground'
                Pattern = '(?im)' + $windowReceiverPattern + '\s*\.\s*call\s*\(\s*(?:StringName\s*\(\s*)?&?["'']move_?to_?foreground["'']'
            }
        )) {
            if ([regex]::IsMatch($Source, $windowAlternative.Pattern)) {
                [void] $violations.Add("window-lifetime:$($windowAlternative.Token)")
            }
        }
    }
    return @($violations)
}

function Initialize-HiddenWindowHostInterop {
    if ($env:OS -ne 'Windows_NT' -or
            $null -ne ('TrawfTestGate.HiddenWindowHostSession' -as [type])) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace TrawfTestGate
{
    public sealed class WindowIsolationSnapshot
    {
        public bool PrivateDesktopExists { get; set; }
        public bool PrivateDesktopNameMatches { get; set; }
        public bool PrivateDesktopIsInput { get; set; }
        public bool ParentEnumeratedOnPrivateDesktop { get; set; }
        public bool ParentThreadUsesPrivateDesktop { get; set; }
        public bool ParentExists { get; set; }
        public bool ParentVisible { get; set; }
        public bool ParentHasPopupStyle { get; set; }
        public bool ParentHasToolWindowStyle { get; set; }
        public bool ParentHasNoActivateStyle { get; set; }
        public bool ParentHasVisibleStyle { get; set; }
        public bool ParentHasAppWindowStyle { get; set; }
        public bool SawEmbeddedChild { get; set; }
        public bool EmbeddedChildVisible { get; set; }
        public bool ParentOutsideVirtualDesktop { get; set; }
        public bool EmbeddedChildrenOutsideVirtualDesktop { get; set; }
        public bool EmbeddedChildrenHaveVisibleStyle { get; set; }
        public bool EmbeddedChildrenInputDisabled { get; set; }
        public bool EmbeddedChildHasAppWindowStyle { get; set; }
        public bool ParentForeground { get; set; }
        public bool ParentOrDescendantForeground { get; set; }
        public bool DescendantTopLevelVisible { get; set; }
        public bool HostedAuxiliaryUnsafe { get; set; }
        public int EmbeddedChildCount { get; set; }
        public int DescendantTopLevelCount { get; set; }
        public int StartupProbeTopLevelCount { get; set; }
        public int SystemAuxiliaryTopLevelCount { get; set; }
        public int CurrentOwnerImeBindingCount { get; set; }
        public int DetachedOwnerImeBindingCount { get; set; }
        public bool ExactJobMembership { get; set; }
        public bool JobContainsRootProcess { get; set; }
        public int ExactJobProcessCount { get; set; }
        public bool InputDesktopExists { get; set; }
        public bool InputDesktopNameMatches { get; set; }
        public bool InputDesktopIsCurrent { get; set; }
        public bool InputDesktopIsPrivate { get; set; }
        public bool InputDesktopEnumerated { get; set; }
        public bool InputDesktopEscapeUnsafe { get; set; }
        public int InputDesktopProcessWindowCount { get; set; }
        public long[] EmbeddedWindowHandles { get; set; }
        public string Summary { get; set; }
    }

    public sealed class HiddenWindowHostSession : IDisposable
    {
        private readonly ManualResetEvent ready = new ManualResetEvent(false);
        private readonly Thread pumpThread;
        private readonly uint creatorThreadId;
        private IntPtr handle;
        private IntPtr desktop;
        private string desktopName;
        private string desktopPath;
        private IntPtr inputDesktop;
        private string inputDesktopName;
        private string inputDesktopPath;
        private uint pumpThreadId;
        private int startupError;
        private Exception startupException;
        private volatile bool stopped;
        private bool disposed;

        public HiddenWindowHostSession(int width, int height)
        {
            creatorThreadId = HiddenWindowHost.CurrentThreadId();
            pumpThread = new Thread(delegate() { Run(width, height); });
            pumpThread.IsBackground = true;
            pumpThread.Name = "TRAWF hidden Windowed-test host";
            try
            {
                // Retain the desktop which was receiving user input before the
                // private render desktop exists. Monitoring this exact handle
                // closes the gap where a job process explicitly creates a
                // second HWND on Default instead of its inherited desktop.
                inputDesktop = HiddenWindowHost.OpenCurrentInputDesktop();
                if (inputDesktop == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not retain the original input desktop for Windowed-test monitoring.");
                }
                inputDesktopName = HiddenWindowHost.DesktopObjectName(inputDesktop);
                if (string.IsNullOrEmpty(inputDesktopName))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not identify the original input desktop.");
                }
                inputDesktopPath = HiddenWindowHost.CurrentWindowStationName() +
                    "\\" + inputDesktopName;
                pumpThread.Start();
                if (!ready.WaitOne(5000))
                {
                    throw new TimeoutException(
                        "Timed out creating the dedicated hidden Windowed-test parent HWND.");
                }
                if (startupException != null)
                {
                    throw new InvalidOperationException(
                        "Hidden Windowed-test host thread failed during startup.",
                        startupException);
                }
                if (handle == IntPtr.Zero)
                {
                    throw new InvalidOperationException(string.Format(
                        "Could not create the never-shown Windowed-test parent HWND (Win32 error {0}).",
                        startupError));
                }
            }
            catch (Exception constructionFailure)
            {
                bool stoppedCleanly = Stop(5000) || Stop(5000);
                if (stoppedCleanly)
                {
                    ready.Dispose();
                    disposed = true;
                    throw;
                }
                throw new InvalidOperationException(
                    "Hidden Windowed-test host construction failed and its " +
                    "pump could not be disposed within two bounded attempts.",
                    constructionFailure);
            }
        }

        public IntPtr Handle
        {
            get { return handle; }
        }

        public IntPtr DesktopHandle
        {
            get { return desktop; }
        }

        public string DesktopName
        {
            get { return desktopName; }
        }

        public string DesktopPath
        {
            get { return desktopPath; }
        }

        public IntPtr InputDesktopHandle
        {
            get { return inputDesktop; }
        }

        public string InputDesktopName
        {
            get { return inputDesktopName; }
        }

        public string InputDesktopPath
        {
            get { return inputDesktopPath; }
        }

        public uint PumpThreadId
        {
            get { return pumpThreadId; }
        }

        public uint CreatorThreadId
        {
            get { return creatorThreadId; }
        }

        public bool PumpThreadAlive
        {
            get { return pumpThread.IsAlive; }
        }

        public bool Stop(int timeoutMilliseconds)
        {
            if (!stopped)
            {
                stopped = true;
            }
            uint threadId = pumpThreadId;
            if (threadId != 0)
            {
                HiddenWindowHost.RequestStop(threadId);
            }
            bool joined = !pumpThread.IsAlive || pumpThread.Join(timeoutMilliseconds);
            if (joined && desktop != IntPtr.Zero)
            {
                IntPtr ownedDesktop = desktop;
                if (!HiddenWindowHost.ClosePrivateDesktop(ownedDesktop))
                {
                    return false;
                }
                desktop = IntPtr.Zero;
            }
            if (joined && inputDesktop != IntPtr.Zero)
            {
                IntPtr ownedInputDesktop = inputDesktop;
                if (!HiddenWindowHost.ClosePrivateDesktop(ownedInputDesktop))
                {
                    return false;
                }
                inputDesktop = IntPtr.Zero;
            }
            return joined;
        }

        public void Dispose()
        {
            if (disposed)
            {
                return;
            }
            bool stoppedCleanly = Stop(5000) || Stop(5000);
            if (!stoppedCleanly)
            {
                throw new TimeoutException(
                    "The dedicated hidden Windowed-test host did not dispose " +
                    "cleanly within two bounded attempts.");
            }
            ready.Dispose();
            disposed = true;
        }

        private void Run(int width, int height)
        {
            bool announced = false;
            try
            {
                pumpThreadId = HiddenWindowHost.CurrentThreadId();
                if (stopped)
                {
                    ready.Set();
                    announced = true;
                    return;
                }
                desktopName = string.Format(
                    "TRAWF-Test-{0}-{1}",
                    System.Diagnostics.Process.GetCurrentProcess().Id,
                    Guid.NewGuid().ToString("N"));
                desktop = HiddenWindowHost.CreatePrivateDesktop(desktopName);
                if (desktop == IntPtr.Zero)
                {
                    startupError = Marshal.GetLastWin32Error();
                }
                else if (!HiddenWindowHost.AttachCurrentThreadToDesktop(desktop))
                {
                    startupError = Marshal.GetLastWin32Error();
                }
                else
                {
                    desktopPath = HiddenWindowHost.CurrentWindowStationName() +
                        "\\" + desktopName;
                }
                if (startupError != 0)
                {
                    ready.Set();
                    announced = true;
                    return;
                }
                handle = HiddenWindowHost.CreateOnCurrentThread(width, height);
                if (handle == IntPtr.Zero)
                {
                    startupError = Marshal.GetLastWin32Error();
                }
                ready.Set();
                announced = true;
                if (handle != IntPtr.Zero && !stopped)
                {
                    HiddenWindowHost.RunMessageLoop();
                }
            }
            catch (Exception exception)
            {
                startupException = exception;
                if (!announced)
                {
                    ready.Set();
                    announced = true;
                }
            }
            finally
            {
                if (!announced)
                {
                    ready.Set();
                }
                IntPtr ownedHandle = handle;
                if (ownedHandle != IntPtr.Zero)
                {
                    HiddenWindowHost.DestroyOnOwnerThread(ownedHandle);
                    handle = IntPtr.Zero;
                }
            }
        }
    }

    public sealed class SuspendedProcessSession : IDisposable
    {
        private IntPtr processHandle;
        private IntPtr primaryThreadHandle;
        private IntPtr jobHandle;
        private bool resumed;

        internal SuspendedProcessSession(
            IntPtr p_process_handle,
            IntPtr p_primary_thread_handle,
            IntPtr p_job_handle,
            int p_process_id)
        {
            processHandle = p_process_handle;
            primaryThreadHandle = p_primary_thread_handle;
            jobHandle = p_job_handle;
            ProcessId = p_process_id;
        }

        public int ProcessId { get; private set; }

        public bool IsResumed
        {
            get { return resumed; }
        }

        public void Resume()
        {
            if (resumed)
            {
                return;
            }
            if (primaryThreadHandle == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "The suspended process has no primary-thread handle.");
            }
            uint previousSuspendCount = HiddenWindowHost.ResumeNativeThread(
                primaryThreadHandle);
            if (previousSuspendCount == UInt32.MaxValue)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not resume the isolated Windowed process.");
            }
            if (previousSuspendCount != 1)
            {
                throw new InvalidOperationException(string.Format(
                    "The isolated Windowed primary thread had unexpected " +
                    "suspend count {0}; it was not safely resumed.",
                    previousSuspendCount));
            }
            resumed = true;
            HiddenWindowHost.CloseNativeHandle(primaryThreadHandle);
            primaryThreadHandle = IntPtr.Zero;
        }

        public void Terminate(uint exitCode)
        {
            if (jobHandle != IntPtr.Zero)
            {
                if (!HiddenWindowHost.TerminateNativeJob(jobHandle, exitCode))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not terminate the isolated Windowed process tree.");
                }
            }
            else if (processHandle != IntPtr.Zero)
            {
                if (!HiddenWindowHost.TerminateNativeProcess(
                        processHandle, exitCode))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not terminate the isolated Windowed process.");
                }
            }
        }

        public bool WaitForTreeExit(int timeoutMilliseconds)
        {
            if (jobHandle == IntPtr.Zero)
            {
                throw new ObjectDisposedException(
                    "SuspendedProcessSession",
                    "The native process job handle is no longer available.");
            }
            return HiddenWindowHost.WaitForNativeJobExit(
                jobHandle, timeoutMilliseconds);
        }

        public int GetExitCode()
        {
            if (processHandle == IntPtr.Zero)
            {
                throw new ObjectDisposedException(
                    "SuspendedProcessSession",
                    "The native process handle is no longer available.");
            }
            return HiddenWindowHost.ReadNativeProcessExitCode(processHandle);
        }

        public int[] GetProcessIds()
        {
            if (jobHandle == IntPtr.Zero)
            {
                throw new ObjectDisposedException(
                    "SuspendedProcessSession",
                    "The native process job handle is no longer available.");
            }
            return HiddenWindowHost.ReadNativeJobProcessIds(jobHandle);
        }

        public void Dispose()
        {
            if (jobHandle != IntPtr.Zero)
            {
                // Close the kill-on-close job first so exceptional teardown
                // cannot leave descendants alive after observability handles
                // are released.
                HiddenWindowHost.CloseNativeHandle(jobHandle);
                jobHandle = IntPtr.Zero;
            }
            if (primaryThreadHandle != IntPtr.Zero)
            {
                HiddenWindowHost.CloseNativeHandle(primaryThreadHandle);
                primaryThreadHandle = IntPtr.Zero;
            }
            if (processHandle != IntPtr.Zero)
            {
                HiddenWindowHost.CloseNativeHandle(processHandle);
                processHandle = IntPtr.Zero;
            }
        }
    }

    public static class HiddenWindowHost
    {
        private const uint WS_POPUP = 0x80000000;
        private const uint WS_DISABLED = 0x08000000;
        private const uint WS_EX_TOOLWINDOW = 0x00000080;
        private const uint WS_EX_NOACTIVATE = 0x08000000;
        private const uint WM_QUIT = 0x0012;
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private const uint DESKTOP_READOBJECTS = 0x0001;
        private const uint DESKTOP_CREATEWINDOW = 0x0002;
        private const uint DESKTOP_ENUMERATE = 0x0040;
        private const uint DESKTOP_WRITEOBJECTS = 0x0080;
        private const uint PRIVATE_DESKTOP_ACCESS = DESKTOP_READOBJECTS |
            DESKTOP_CREATEWINDOW | DESKTOP_ENUMERATE | DESKTOP_WRITEOBJECTS;
        private const int UOI_NAME = 2;
        private const int SW_SHOWNOACTIVATE = 4;
        private const uint STARTF_USESHOWWINDOW = 0x00000001;
        private const uint STARTF_USESTDHANDLES = 0x00000100;
        private const short SW_HIDE = 0;
        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const uint CREATE_NO_WINDOW = 0x08000000;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION = 1;
        private const int JOB_OBJECT_BASIC_PROCESS_ID_LIST = 3;
        private const int JOB_OBJECT_BASIC_UI_RESTRICTIONS = 4;
        private const int JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9;
        private const uint JOB_OBJECT_UILIMIT_DESKTOP = 0x00000040;
        private const int ERROR_MORE_DATA = 234;
        private const uint GENERIC_READ = 0x80000000;
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint CREATE_ALWAYS = 2;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const int GWL_EXSTYLE = -20;
        private const int GWL_STYLE = -16;
        private const long WS_EX_APPWINDOW = 0x00040000L;
        private const long WS_VISIBLE = 0x10000000L;
        private const int SM_XVIRTUALSCREEN = 76;
        private const int SM_YVIRTUALSCREEN = 77;
        private const int SM_CXVIRTUALSCREEN = 78;
        private const int SM_CYVIRTUALSCREEN = 79;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr Hwnd;
            public uint Message;
            public UIntPtr WParam;
            public IntPtr LParam;
            public uint Time;
            public POINT Point;
            public uint Private;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PROCESSENTRY32
        {
            public uint Size;
            public uint Usage;
            public uint ProcessId;
            public UIntPtr DefaultHeapId;
            public uint ModuleId;
            public uint Threads;
            public uint ParentProcessId;
            public int BasePriority;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string ExeFile;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES
        {
            public int Length;
            public IntPtr SecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)]
            public bool InheritHandle;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct STARTUPINFO
        {
            public int Size;
            public string Reserved;
            public string Desktop;
            public string Title;
            public int X;
            public int Y;
            public int XSize;
            public int YSize;
            public int XCountChars;
            public int YCountChars;
            public int FillAttribute;
            public uint Flags;
            public short ShowWindow;
            public short Reserved2Size;
            public IntPtr Reserved2;
            public IntPtr StandardInput;
            public IntPtr StandardOutput;
            public IntPtr StandardError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr Process;
            public IntPtr Thread;
            public uint ProcessId;
            public uint ThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public long PerProcessUserTimeLimit;
            public long PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass;
            public uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION
        {
            public long TotalUserTime;
            public long TotalKernelTime;
            public long ThisPeriodTotalUserTime;
            public long ThisPeriodTotalKernelTime;
            public uint TotalPageFaultCount;
            public uint TotalProcesses;
            public uint ActiveProcesses;
            public uint TotalTerminatedProcesses;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_UI_RESTRICTIONS
        {
            public uint UIRestrictionsClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount;
            public ulong WriteOperationCount;
            public ulong OtherOperationCount;
            public ulong ReadTransferCount;
            public ulong WriteTransferCount;
            public ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowExW(
            uint exStyle, string className, string windowName, uint style,
            int x, int y, int width, int height, IntPtr parent, IntPtr menu,
            IntPtr instance, IntPtr parameter);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowEnabled(IntPtr hwnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnableWindow(IntPtr hwnd, bool enable);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetParent(IntPtr hwnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("imm32.dll")]
        private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassNameW(
            IntPtr hwnd, StringBuilder className, int maximumCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextW(
            IntPtr hwnd, StringBuilder windowText, int maximumCount);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hwnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong32(IntPtr hwnd, int index);

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumDesktopWindows(
            IntPtr desktop, EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumChildWindows(
            IntPtr parent, EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern int GetMessageW(
            out MSG message, IntPtr hwnd, uint min, uint max);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PostThreadMessageW(
            uint threadId, uint message, UIntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref MSG message);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessageW(ref MSG message);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateDesktopW(
            string desktopName, IntPtr device, IntPtr deviceMode,
            uint flags, uint desiredAccess, IntPtr securityAttributes);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetThreadDesktop(IntPtr desktop);

        [DllImport("user32.dll")]
        private static extern IntPtr GetThreadDesktop(uint threadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseDesktop(IntPtr desktop);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(
            uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit,
            uint desiredAccess);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetUserObjectInformationW(
            IntPtr obj, int index, StringBuilder information,
            int length, out int needed);

        [DllImport("user32.dll")]
        private static extern IntPtr GetProcessWindowStation();

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr hwnd, int command);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName,
            StringBuilder commandLine,
            IntPtr processAttributes,
            IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags,
            IntPtr environment,
            string currentDirectory,
            ref STARTUPINFO startupInfo,
            out PROCESS_INFORMATION processInformation);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateFileW(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            ref SECURITY_ATTRIBUTES securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(
            IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObjectW(
            IntPtr jobAttributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job, int informationClass,
            ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION information,
            uint informationLength);

        [DllImport("kernel32.dll", EntryPoint = "SetInformationJobObject",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObjectUi(
            IntPtr job, int informationClass,
            ref JOBOBJECT_BASIC_UI_RESTRICTIONS information,
            uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(
            IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(
            IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(
            IntPtr job, int informationClass,
            out JOBOBJECT_BASIC_ACCOUNTING_INFORMATION information,
            uint informationLength, IntPtr returnLength);

        [DllImport("kernel32.dll", EntryPoint = "QueryInformationJobObject",
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObjectBuffer(
            IntPtr job, int informationClass,
            IntPtr information, uint informationLength,
            out uint returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(
            IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32FirstW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Process32NextW(IntPtr snapshot, ref PROCESSENTRY32 entry);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        internal static IntPtr CreatePrivateDesktop(string desktopName)
        {
            if (string.IsNullOrEmpty(desktopName))
            {
                return IntPtr.Zero;
            }
            return CreateDesktopW(
                desktopName, IntPtr.Zero, IntPtr.Zero, 0,
                PRIVATE_DESKTOP_ACCESS, IntPtr.Zero);
        }

        internal static IntPtr OpenCurrentInputDesktop()
        {
            return OpenInputDesktop(
                0, false, DESKTOP_READOBJECTS | DESKTOP_ENUMERATE);
        }

        internal static string DesktopObjectName(IntPtr desktop)
        {
            return UserObjectName(desktop);
        }

        internal static bool AttachCurrentThreadToDesktop(IntPtr desktop)
        {
            return desktop != IntPtr.Zero && SetThreadDesktop(desktop);
        }

        internal static bool ClosePrivateDesktop(IntPtr desktop)
        {
            return desktop == IntPtr.Zero || CloseDesktop(desktop);
        }

        internal static string CurrentWindowStationName()
        {
            string name = UserObjectName(GetProcessWindowStation());
            if (string.IsNullOrEmpty(name))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not resolve the current Windows window station.");
            }
            return name;
        }

        public static bool IsPrivateDesktopNotInput(
            IntPtr privateDesktop, string expectedDesktopName)
        {
            if (privateDesktop == IntPtr.Zero ||
                    string.IsNullOrEmpty(expectedDesktopName) ||
                    !string.Equals(
                        UserObjectName(privateDesktop), expectedDesktopName,
                        StringComparison.Ordinal))
            {
                return false;
            }
            IntPtr inputDesktop = OpenInputDesktop(
                0, false, DESKTOP_READOBJECTS);
            if (inputDesktop == IntPtr.Zero)
            {
                return false;
            }
            try
            {
                string inputName = UserObjectName(inputDesktop);
                return !string.IsNullOrEmpty(inputName) &&
                    !string.Equals(
                        inputName, expectedDesktopName,
                        StringComparison.Ordinal);
            }
            finally
            {
                CloseDesktop(inputDesktop);
            }
        }

        private static bool IsNamedDesktopCurrent(string expectedDesktopName)
        {
            if (string.IsNullOrEmpty(expectedDesktopName))
            {
                return false;
            }
            IntPtr currentInputDesktop = OpenInputDesktop(
                0, false, DESKTOP_READOBJECTS);
            if (currentInputDesktop == IntPtr.Zero)
            {
                return false;
            }
            try
            {
                return string.Equals(
                    UserObjectName(currentInputDesktop),
                    expectedDesktopName,
                    StringComparison.Ordinal);
            }
            finally
            {
                CloseDesktop(currentInputDesktop);
            }
        }

        public static SuspendedProcessSession StartSuspendedProcess(
            string applicationPath,
            string argumentLine,
            string workingDirectory,
            string desktopPath,
            string stdoutPath,
            string stderrPath)
        {
            if (string.IsNullOrEmpty(applicationPath) ||
                    string.IsNullOrEmpty(workingDirectory) ||
                    string.IsNullOrEmpty(desktopPath) ||
                    string.IsNullOrEmpty(stdoutPath) ||
                    string.IsNullOrEmpty(stderrPath))
            {
                throw new ArgumentException(
                    "The suspended process launch contract is incomplete.");
            }

            SECURITY_ATTRIBUTES inheritable = new SECURITY_ATTRIBUTES();
            inheritable.Length = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
            inheritable.InheritHandle = true;
            IntPtr stdoutHandle = IntPtr.Zero;
            IntPtr stderrHandle = IntPtr.Zero;
            IntPtr stdinHandle = IntPtr.Zero;
            IntPtr jobHandle = IntPtr.Zero;
            PROCESS_INFORMATION processInformation = new PROCESS_INFORMATION();
            bool processCreated = false;
            bool ownershipTransferred = false;
            try
            {
                jobHandle = CreateKillOnCloseJob();
                stdoutHandle = CreateFileW(
                    stdoutPath, GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    ref inheritable, CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
                ThrowIfInvalidFileHandle(stdoutHandle, "stdout");
                stderrHandle = CreateFileW(
                    stderrPath, GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    ref inheritable, CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
                ThrowIfInvalidFileHandle(stderrHandle, "stderr");
                stdinHandle = CreateFileW(
                    "NUL", GENERIC_READ,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    ref inheritable, OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
                ThrowIfInvalidFileHandle(stdinHandle, "stdin");

                STARTUPINFO startupInfo = new STARTUPINFO();
                startupInfo.Size = Marshal.SizeOf(typeof(STARTUPINFO));
                startupInfo.Desktop = desktopPath;
                startupInfo.Flags = STARTF_USESHOWWINDOW |
                    STARTF_USESTDHANDLES;
                startupInfo.ShowWindow = SW_HIDE;
                startupInfo.StandardInput = stdinHandle;
                startupInfo.StandardOutput = stdoutHandle;
                startupInfo.StandardError = stderrHandle;

                string command = QuoteCommandLineArgument(applicationPath);
                if (!string.IsNullOrEmpty(argumentLine))
                {
                    command += " " + argumentLine;
                }
                StringBuilder mutableCommand = new StringBuilder(command);
                processCreated = CreateProcessW(
                    applicationPath,
                    mutableCommand,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    true,
                    CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT |
                        CREATE_NO_WINDOW,
                    IntPtr.Zero,
                    workingDirectory,
                    ref startupInfo,
                    out processInformation);
                if (!processCreated)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not create the isolated Windowed process suspended.");
                }
                if (!AssignProcessToJobObject(
                        jobHandle, processInformation.Process))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not bind the suspended Windowed process to its " +
                        "kill-on-close process-tree job.");
                }
                SuspendedProcessSession session =
                    new SuspendedProcessSession(
                    processInformation.Process,
                    processInformation.Thread,
                    jobHandle,
                    checked((int)processInformation.ProcessId));
                ownershipTransferred = true;
                return session;
            }
            finally
            {
                CloseFileHandle(stdoutHandle);
                CloseFileHandle(stderrHandle);
                CloseFileHandle(stdinHandle);
                if (!ownershipTransferred)
                {
                    if (processCreated &&
                            processInformation.Process != IntPtr.Zero)
                    {
                        TerminateProcess(processInformation.Process, 66);
                        WaitForSingleObject(
                            processInformation.Process, 5000);
                    }
                    CloseFileHandle(processInformation.Thread);
                    CloseFileHandle(processInformation.Process);
                    CloseFileHandle(jobHandle);
                }
            }
        }

        internal static uint ResumeNativeThread(IntPtr thread)
        {
            return ResumeThread(thread);
        }

        internal static bool TerminateNativeProcess(
            IntPtr process, uint exitCode)
        {
            return process != IntPtr.Zero && TerminateProcess(process, exitCode);
        }

        internal static bool TerminateNativeJob(
            IntPtr job, uint exitCode)
        {
            return job != IntPtr.Zero && TerminateJobObject(job, exitCode);
        }

        internal static bool WaitForNativeJobExit(
            IntPtr job, int timeoutMilliseconds)
        {
            if (job == IntPtr.Zero || timeoutMilliseconds < 0)
            {
                throw new ArgumentOutOfRangeException("timeoutMilliseconds");
            }
            Stopwatch timer = Stopwatch.StartNew();
            while (true)
            {
                JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
                if (!QueryInformationJobObject(
                        job, JOB_OBJECT_BASIC_ACCOUNTING_INFORMATION,
                        out accounting,
                        checked((uint)Marshal.SizeOf(typeof(
                            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION))),
                        IntPtr.Zero))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(),
                        "Could not inspect the isolated Windowed process tree.");
                }
                if (accounting.ActiveProcesses == 0)
                {
                    return true;
                }
                int remaining = timeoutMilliseconds -
                    checked((int)Math.Min(
                        timer.ElapsedMilliseconds, Int32.MaxValue));
                if (remaining <= 0)
                {
                    return false;
                }
                Thread.Sleep(Math.Min(25, remaining));
            }
        }

        private static IntPtr CreateKillOnCloseJob()
        {
            IntPtr job = CreateJobObjectW(IntPtr.Zero, null);
            if (job == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not create the isolated Windowed process job.");
            }
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits =
                new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            limits.BasicLimitInformation.LimitFlags =
                JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if (!SetInformationJobObject(
                    job, JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                    ref limits,
                    checked((uint)Marshal.SizeOf(
                        typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)))))
            {
                int error = Marshal.GetLastWin32Error();
                CloseHandle(job);
                throw new Win32Exception(error,
                    "Could not configure kill-on-close process-tree isolation.");
            }
            JOBOBJECT_BASIC_UI_RESTRICTIONS uiRestrictions =
                new JOBOBJECT_BASIC_UI_RESTRICTIONS();
            // Defense in depth: this blocks CreateDesktop/SwitchDesktop for
            // every job process. It deliberately does not replace retained
            // input-desktop enumeration because Windows does not document this
            // flag as blocking OpenDesktop/SetThreadDesktop.
            uiRestrictions.UIRestrictionsClass = JOB_OBJECT_UILIMIT_DESKTOP;
            if (!SetInformationJobObjectUi(
                    job, JOB_OBJECT_BASIC_UI_RESTRICTIONS,
                    ref uiRestrictions,
                    checked((uint)Marshal.SizeOf(typeof(
                        JOBOBJECT_BASIC_UI_RESTRICTIONS)))))
            {
                int error = Marshal.GetLastWin32Error();
                CloseHandle(job);
                throw new Win32Exception(error,
                    "Could not configure process-job desktop UI isolation.");
            }
            return job;
        }

        internal static int ReadNativeProcessExitCode(IntPtr process)
        {
            uint exitCode;
            if (process == IntPtr.Zero ||
                    !GetExitCodeProcess(process, out exitCode))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not read the isolated Windowed process exit code.");
            }
            return unchecked((int)exitCode);
        }

        internal static int[] ReadNativeJobProcessIds(IntPtr job)
        {
            if (job == IntPtr.Zero)
            {
                throw new ObjectDisposedException(
                    "job", "The native process job handle is unavailable.");
            }
            int capacity = 16;
            for (int attempt = 0; attempt < 8; attempt++)
            {
                int byteCount = checked(8 + capacity * IntPtr.Size);
                IntPtr buffer = Marshal.AllocHGlobal(byteCount);
                try
                {
                    for (int offset = 0; offset < byteCount; offset += 4)
                    {
                        Marshal.WriteInt32(buffer, offset, 0);
                    }
                    uint returned;
                    bool succeeded = QueryInformationJobObjectBuffer(
                        job, JOB_OBJECT_BASIC_PROCESS_ID_LIST,
                        buffer, checked((uint)byteCount), out returned);
                    int assigned = Math.Max(0, Marshal.ReadInt32(buffer, 0));
                    int listed = Math.Max(0, Marshal.ReadInt32(buffer, 4));
                    if (succeeded)
                    {
                        if (listed > capacity || listed > assigned)
                        {
                            throw new InvalidOperationException(
                                "The native process job returned an invalid PID list.");
                        }
                        if (listed != assigned)
                        {
                            capacity = Math.Max(
                                capacity * 2, Math.Max(assigned, listed) + 8);
                            continue;
                        }
                        List<int> result = new List<int>(listed);
                        HashSet<uint> unique = new HashSet<uint>();
                        for (int index = 0; index < listed; index++)
                        {
                            long raw = IntPtr.Size == 8
                                ? Marshal.ReadInt64(buffer, 8 + index * IntPtr.Size)
                                : (long)(uint)Marshal.ReadInt32(
                                    buffer, 8 + index * IntPtr.Size);
                            if (raw <= 0 || raw > UInt32.MaxValue)
                            {
                                throw new InvalidOperationException(
                                    "The native process job returned an invalid PID.");
                            }
                            uint processId = (uint)raw;
                            if (!unique.Add(processId))
                            {
                                throw new InvalidOperationException(
                                    "The native process job returned a duplicate PID.");
                            }
                            result.Add(unchecked((int)processId));
                        }
                        result.Sort();
                        return result.ToArray();
                    }
                    int error = Marshal.GetLastWin32Error();
                    if (error != ERROR_MORE_DATA)
                    {
                        throw new Win32Exception(error,
                            "Could not read the exact isolated process-job PID list.");
                    }
                    capacity = Math.Max(capacity * 2, Math.Max(assigned, listed) + 8);
                }
                finally
                {
                    Marshal.FreeHGlobal(buffer);
                }
            }
            throw new InvalidOperationException(
                "The isolated process-job PID list did not stabilize within the bounded query.");
        }

        internal static bool CloseNativeHandle(IntPtr handle)
        {
            return handle == IntPtr.Zero || handle == INVALID_HANDLE_VALUE ||
                CloseHandle(handle);
        }

        public static bool RevealDisabledWindowWithoutActivation(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd) ||
                    IsWindowEnabled(hwnd))
            {
                return false;
            }
            // STARTUPINFO supplies SW_HIDE, so Windows can consume the first
            // ShowWindow request regardless of the caller's command. Two
            // no-activate requests establish a visible-style real swapchain
            // only after the private-desktop/geometry/input checks pass.
            ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            ShowWindow(hwnd, SW_SHOWNOACTIVATE);
            return IsWindowVisible(hwnd) && !IsWindowEnabled(hwnd) &&
                (GetWindowStyle(hwnd, GWL_STYLE) & WS_VISIBLE) != 0;
        }

        public static bool WindowHasNonEmptyTitle(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
            {
                return false;
            }
            StringBuilder title = new StringBuilder(512);
            GetWindowTextW(hwnd, title, title.Capacity);
            return title.Length > 0;
        }

        private static void ThrowIfInvalidFileHandle(
            IntPtr handle, string streamName)
        {
            if (handle == IntPtr.Zero || handle == INVALID_HANDLE_VALUE)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not create inherited " + streamName +
                    " for the isolated Windowed process.");
            }
        }

        private static void CloseFileHandle(IntPtr handle)
        {
            if (handle != IntPtr.Zero && handle != INVALID_HANDLE_VALUE)
            {
                CloseHandle(handle);
            }
        }

        private static string QuoteCommandLineArgument(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        private static string UserObjectName(IntPtr obj)
        {
            if (obj == IntPtr.Zero)
            {
                return string.Empty;
            }
            int needed;
            GetUserObjectInformationW(
                obj, UOI_NAME, null, 0, out needed);
            if (needed <= 0)
            {
                return string.Empty;
            }
            StringBuilder name = new StringBuilder(
                Math.Max(needed / 2, 2));
            if (!GetUserObjectInformationW(
                    obj, UOI_NAME, name,
                    name.Capacity * 2, out needed))
            {
                return string.Empty;
            }
            return name.ToString();
        }

        internal static IntPtr CreateOnCurrentThread(int width, int height)
        {
            RECT desktop = VirtualDesktopRect();
            return CreateWindowExW(
                WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                "STATIC",
                "TRAWF Hidden Test Host",
                WS_POPUP | WS_DISABLED,
                desktop.Left,
                desktop.Bottom + 512,
                width,
                height,
                IntPtr.Zero,
                IntPtr.Zero,
                IntPtr.Zero,
                IntPtr.Zero);
        }

        public static string OffscreenPosition()
        {
            RECT desktop = VirtualDesktopRect();
            // Godot normalizes screen coordinates by subtracting the virtual
            // desktop's minimum origin, then adds that origin again inside its
            // Windows backend. Feed it normalized coordinates: using the raw
            // physical bottom is wrong when monitors extend above the primary
            // display and can put the render HWND back on-screen.
            int normalizedDesktopHeight = checked(desktop.Bottom - desktop.Top);
            return string.Format("0,{0}", checked(normalizedDesktopHeight + 512));
        }

        public static bool IntersectionSemanticsPassSelfTest()
        {
            RECT desktop = VirtualDesktopRect();
            if (desktop.Right <= desktop.Left || desktop.Bottom <= desktop.Top)
            {
                return false;
            }
            RECT onePixelOverlap = new RECT();
            onePixelOverlap.Left = desktop.Right - 1;
            onePixelOverlap.Top = desktop.Bottom - 1;
            onePixelOverlap.Right = desktop.Right + 31;
            onePixelOverlap.Bottom = desktop.Bottom + 31;
            RECT edgeTouchOnly = new RECT();
            edgeTouchOnly.Left = desktop.Right;
            edgeTouchOnly.Top = desktop.Bottom;
            edgeTouchOnly.Right = desktop.Right + 32;
            edgeTouchOnly.Bottom = desktop.Bottom + 32;
            return Intersects(onePixelOverlap, desktop) &&
                !Intersects(edgeTouchOnly, desktop);
        }

        internal static bool DestroyOnOwnerThread(IntPtr hwnd)
        {
            return hwnd == IntPtr.Zero || !IsWindow(hwnd) || DestroyWindow(hwnd);
        }

        internal static uint CurrentThreadId()
        {
            return GetCurrentThreadId();
        }

        internal static void RunMessageLoop()
        {
            MSG message;
            int result;
            while ((result = GetMessageW(out message, IntPtr.Zero, 0, 0)) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessageW(ref message);
            }
            if (result < 0)
            {
                throw new InvalidOperationException(
                    "The hidden Windowed-test host message pump failed.");
            }
        }

        internal static bool RequestStop(uint threadId)
        {
            return PostThreadMessageW(
                threadId, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        }

        public static WindowIsolationSnapshot Inspect(
            IntPtr privateDesktop,
            string expectedDesktopName,
            IntPtr parent,
            int rootProcessId)
        {
            return InspectCore(
                privateDesktop, expectedDesktopName,
                IntPtr.Zero, string.Empty,
                parent, rootProcessId,
                DescendantProcessIds(rootProcessId), false);
        }

        public static WindowIsolationSnapshot InspectJob(
            IntPtr privateDesktop,
            string expectedDesktopName,
            IntPtr inputDesktop,
            string expectedInputDesktopName,
            IntPtr parent,
            SuspendedProcessSession processSession,
            bool suppressImePrebindingForSelfTest)
        {
            if (processSession == null)
            {
                throw new ArgumentNullException("processSession");
            }
            int rootProcessId = processSession.ProcessId;
            return InspectCore(
                privateDesktop, expectedDesktopName,
                inputDesktop, expectedInputDesktopName,
                parent, rootProcessId,
                new HashSet<int>(processSession.GetProcessIds()), true,
                suppressImePrebindingForSelfTest);
        }

        private static WindowIsolationSnapshot InspectCore(
            IntPtr privateDesktop,
            string expectedDesktopName,
            IntPtr inputDesktop,
            string expectedInputDesktopName,
            IntPtr parent,
            int rootProcessId,
            HashSet<int> processIds,
            bool exactJobMembership,
            bool suppressImePrebindingForSelfTest = false)
        {
            List<string> embedded = new List<string>();
            List<long> embeddedHandles = new List<long>();
            List<string> hostedAuxiliary = new List<string>();
            List<string> startupProbes = new List<string>();
            List<string> systemAuxiliary = new List<string>();
            List<string> topLevels = new List<string>();
            List<string> inputDesktopWindows = new List<string>();
            WindowIsolationSnapshot result = new WindowIsolationSnapshot();
            result.EmbeddedWindowHandles = new long[0];
            result.ExactJobMembership = exactJobMembership;
            result.JobContainsRootProcess = processIds.Contains(rootProcessId);
            result.ExactJobProcessCount = processIds.Count;
            string observedDesktopName = UserObjectName(privateDesktop);
            result.PrivateDesktopExists = privateDesktop != IntPtr.Zero &&
                !string.IsNullOrEmpty(observedDesktopName);
            result.PrivateDesktopNameMatches = result.PrivateDesktopExists &&
                string.Equals(
                    observedDesktopName, expectedDesktopName,
                    StringComparison.Ordinal);
            result.PrivateDesktopIsInput =
                !IsPrivateDesktopNotInput(
                    privateDesktop, expectedDesktopName);
            result.ParentExists = parent != IntPtr.Zero && IsWindow(parent);
            if (result.ParentExists)
            {
                uint parentProcessId;
                uint parentThreadId = GetWindowThreadProcessId(
                    parent, out parentProcessId);
                result.ParentThreadUsesPrivateDesktop = string.Equals(
                    UserObjectName(GetThreadDesktop(parentThreadId)),
                    expectedDesktopName,
                    StringComparison.Ordinal);
            }
            result.ParentVisible = result.ParentExists && IsWindowVisible(parent);
            long parentStyle = result.ParentExists
                ? GetWindowStyle(parent, GWL_STYLE)
                : 0;
            long parentExtendedStyle = result.ParentExists
                ? GetWindowStyle(parent, GWL_EXSTYLE)
                : 0;
            result.ParentHasPopupStyle = (parentStyle & WS_POPUP) != 0;
            result.ParentHasToolWindowStyle =
                (parentExtendedStyle & WS_EX_TOOLWINDOW) != 0;
            result.ParentHasNoActivateStyle =
                (parentExtendedStyle & WS_EX_NOACTIVATE) != 0;
            result.ParentHasVisibleStyle = (parentStyle & WS_VISIBLE) != 0;
            result.ParentHasAppWindowStyle =
                (parentExtendedStyle & WS_EX_APPWINDOW) != 0;
            RECT desktopRect = VirtualDesktopRect();
            RECT inspectedParentRect;
            result.ParentOutsideVirtualDesktop = result.ParentExists &&
                GetWindowRect(parent, out inspectedParentRect) &&
                !Intersects(inspectedParentRect, desktopRect);
            result.EmbeddedChildrenOutsideVirtualDesktop = true;
            result.EmbeddedChildrenHaveVisibleStyle = true;
            result.EmbeddedChildrenInputDisabled = true;
            IntPtr foreground = GetForegroundWindow();
            result.ParentForeground = foreground == parent;
            result.ParentOrDescendantForeground = result.ParentForeground;

            string observedInputDesktopName = UserObjectName(inputDesktop);
            result.InputDesktopExists = inputDesktop != IntPtr.Zero &&
                !string.IsNullOrEmpty(observedInputDesktopName);
            result.InputDesktopNameMatches = result.InputDesktopExists &&
                string.Equals(
                    observedInputDesktopName, expectedInputDesktopName,
                    StringComparison.Ordinal);
            result.InputDesktopIsPrivate = result.InputDesktopExists &&
                string.Equals(
                    observedInputDesktopName, observedDesktopName,
                    StringComparison.Ordinal);
            result.InputDesktopIsCurrent = result.InputDesktopExists &&
                IsNamedDesktopCurrent(observedInputDesktopName);
            if (result.InputDesktopExists)
            {
                EnumWindowsProc inputDesktopCallback = delegate(
                    IntPtr hwnd, IntPtr ignored)
                {
                    if (!IsWindow(hwnd))
                    {
                        return true;
                    }
                    uint processId;
                    GetWindowThreadProcessId(hwnd, out processId);
                    if (!processIds.Contains((int)processId))
                    {
                        return true;
                    }
                    long style = GetWindowStyle(hwnd, GWL_STYLE);
                    long extendedStyle = GetWindowStyle(hwnd, GWL_EXSTYLE);
                    bool visible = IsWindowVisible(hwnd);
                    bool visibleStyle = (style & WS_VISIBLE) != 0;
                    bool appWindow =
                        (extendedStyle & WS_EX_APPWINDOW) != 0;
                    bool isForeground = foreground == hwnd;
                    RECT rect;
                    bool hasRect = GetWindowRect(hwnd, out rect);
                    bool positiveArea = hasRect &&
                        rect.Right > rect.Left && rect.Bottom > rect.Top;
                    // No process in the exact job is permitted to own any
                    // top-level HWND on the user's original input desktop.
                    // Geometry/style details remain in the ledger for diagnosis,
                    // but hidden and zero-area helpers fail closed as well.
                    bool unsafeEscape = true;
                    result.InputDesktopProcessWindowCount += 1;
                    result.InputDesktopEscapeUnsafe |= unsafeEscape;
                    inputDesktopWindows.Add(
                        DescribeWindow(hwnd, processId, visible) +
                        string.Format(
                            ",positive_area={0},visible_style={1},appwindow={2},foreground={3},unsafe={4}",
                            positiveArea, visibleStyle, appWindow,
                            isForeground, unsafeEscape));
                    return true;
                };
                result.InputDesktopEnumerated = EnumDesktopWindows(
                    inputDesktop, inputDesktopCallback, IntPtr.Zero);
            }

            Action<IntPtr, uint, bool> inspectEmbedded = delegate(
                IntPtr hwnd, uint processId, bool visible)
            {
                RECT childRect;
                bool childOutside = GetWindowRect(hwnd, out childRect) &&
                    !Intersects(childRect, desktopRect);
                result.SawEmbeddedChild = true;
                result.EmbeddedChildCount += 1;
                result.EmbeddedChildVisible |= visible;
                result.EmbeddedChildrenOutsideVirtualDesktop &= childOutside;
                result.EmbeddedChildrenHaveVisibleStyle &=
                    (GetWindowStyle(hwnd, GWL_STYLE) & WS_VISIBLE) != 0;
                result.EmbeddedChildrenInputDisabled &= !IsWindowEnabled(hwnd);
                result.EmbeddedChildHasAppWindowStyle |=
                    (GetWindowStyle(hwnd, GWL_EXSTYLE) & WS_EX_APPWINDOW) != 0;
                result.ParentOrDescendantForeground |= foreground == hwnd;
                embeddedHandles.Add(hwnd.ToInt64());
                embedded.Add(DescribeWindow(hwnd, processId, visible));
            };

            if (result.ParentExists)
            {
                EnumWindowsProc childCallback = delegate(IntPtr hwnd, IntPtr ignored)
                {
                    if (!IsWindow(hwnd))
                    {
                        return true;
                    }
                    uint processId;
                    GetWindowThreadProcessId(hwnd, out processId);
                    if (!processIds.Contains((int)processId))
                    {
                        return true;
                    }
                    if (!IsExactRenderWindow(
                            hwnd, parent, processId, rootProcessId))
                    {
                        return true;
                    }
                    bool visible = IsWindowVisible(hwnd);
                    inspectEmbedded(hwnd, processId, visible);
                    return true;
                };
                EnumChildWindows(parent, childCallback, IntPtr.Zero);
            }
            Dictionary<long, ulong> acceptedDefaultImeBindings =
                suppressImePrebindingForSelfTest
                    ? new Dictionary<long, ulong>()
                    : DefaultImeBindingsForAcceptedWindows(
                        privateDesktop, parent, rootProcessId,
                        processIds, foreground);
            EnumWindowsProc topLevelCallback = delegate(IntPtr hwnd, IntPtr ignored)
            {
                if (!IsWindow(hwnd))
                {
                    return true;
                }
                if (hwnd == parent)
                {
                    result.ParentEnumeratedOnPrivateDesktop = true;
                    return true;
                }
                uint processId;
                GetWindowThreadProcessId(hwnd, out processId);
                if (!processIds.Contains((int)processId))
                {
                    return true;
                }
                bool visible = IsWindowVisible(hwnd);
                if (IsExactRenderWindow(
                        hwnd, parent, processId, rootProcessId))
                {
                    // Godot's Windows --wid implementation deliberately creates
                    // a WS_POPUP owned by the supplied HWND, not a WS_CHILD.
                    inspectEmbedded(hwnd, processId, visible);
                    return true;
                }
                bool usedCurrentOwnerImeBinding;
                bool usedDetachedOwnerImeBinding;
                if (IsExactHiddenImeAuxiliary(
                         hwnd, desktopRect, foreground,
                         acceptedDefaultImeBindings, parent, rootProcessId,
                         out usedCurrentOwnerImeBinding,
                         out usedDetachedOwnerImeBinding))
                {
                    // Windows creates one of these disabled, zero-area top-level
                    // helpers for a GUI thread's default input context. It is not
                    // Godot's render surface and cannot be shown or focused under
                    // the conditions enforced by IsExactHiddenImeAuxiliary.
                    result.SystemAuxiliaryTopLevelCount += 1;
                    if (usedCurrentOwnerImeBinding)
                    {
                        result.CurrentOwnerImeBindingCount += 1;
                    }
                    if (usedDetachedOwnerImeBinding)
                    {
                        result.DetachedOwnerImeBindingCount += 1;
                    }
                    systemAuxiliary.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                if (IsExactHiddenMsctfImeAuxiliary(
                        hwnd, desktopRect, foreground,
                        acceptedDefaultImeBindings, parent, rootProcessId))
                {
                    // Text services may add this exact disabled zero-area child
                    // to an already-accepted Default IME window. Its identity,
                    // owner, process/thread binding and inert geometry all have
                    // to match; a near miss remains a forbidden top-level.
                    result.SystemAuxiliaryTopLevelCount += 1;
                    systemAuxiliary.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                if (IsExactHiddenTextServicesAuxiliary(
                        hwnd, processId, rootProcessId, foreground))
                {
                    // The CLR and Windows text services can create an exact
                    // disabled CicLoader/Cicero owner chain on a fresh private
                    // desktop. Every accepted member remains hidden,
                    // no-AppWindow and process-local; any visible, focused,
                    // style-mutated or differently-owned form fails closed.
                    result.SystemAuxiliaryTopLevelCount += 1;
                    systemAuxiliary.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                if (IsExactInputIndicatorAuxiliary(
                        hwnd, processId, rootProcessId, foreground))
                {
                    // Windows input services may create these exact zero-area,
                    // no-activate overlay helpers when a GUI thread begins
                    // pumping messages. They cannot paint a pixel or activate;
                    // any geometry, focus, AppWindow or identity change falls
                    // through to the disallowed-top-level failure.
                    result.SystemAuxiliaryTopLevelCount += 1;
                    systemAuxiliary.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                if (IsOwnedBy(hwnd, parent))
                {
                    // Known owner-bound system helpers were classified above.
                    // Any remaining top-level is unknown and therefore unsafe,
                    // even when hidden or zero-area.
                    result.HostedAuxiliaryUnsafe = true;
                    result.ParentOrDescendantForeground |= foreground == hwnd;
                    hostedAuxiliary.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                if (IsOwnedByWglDetectionWindow(hwnd) && !visible &&
                        foreground != hwnd &&
                        (GetWindowStyle(hwnd, GWL_STYLE) & WS_VISIBLE) == 0)
                {
                    result.StartupProbeTopLevelCount += 1;
                    startupProbes.Add(DescribeWindow(hwnd, processId, visible));
                    return true;
                }
                result.DescendantTopLevelCount += 1;
                result.DescendantTopLevelVisible |= visible;
                result.ParentOrDescendantForeground |= foreground == hwnd;
                topLevels.Add(DescribeWindow(hwnd, processId, visible));
                return true;
            };
            if (!EnumDesktopWindows(
                    privateDesktop, topLevelCallback, IntPtr.Zero))
            {
                result.PrivateDesktopExists = false;
            }
            embeddedHandles.Sort();
            result.EmbeddedWindowHandles = embeddedHandles.ToArray();

            RECT parentRect;
            string parentGeometry = GetWindowRect(parent, out parentRect)
                ? DescribeRect(parentRect)
                : "<unavailable>";
            List<int> sortedProcessIds = new List<int>(processIds);
            sortedProcessIds.Sort();
            result.Summary = string.Format(
                "private_desktop={0} private_exists={1} private_name_matches={2} private_is_input={3} parent_enumerated={4} parent_thread_private={5} parent=0x{6:X} exists={7} visible={8} popup={9} toolwindow={10} noactivate={11} visible_style={12} appwindow={13} outside_desktop={14} parent_foreground={15} rect={16} desktop={17} pids=[{18}] embedded_outside={19} embedded_visible_style={20} embedded_input_disabled={21} embedded_appwindow={22} descendant_foreground={23} embedded=[{24}] hosted_aux=[{25}] startup_probes=[{26}] system_aux=[{27}] disallowed_top_levels=[{28}]",
                observedDesktopName,
                result.PrivateDesktopExists,
                result.PrivateDesktopNameMatches,
                result.PrivateDesktopIsInput,
                result.ParentEnumeratedOnPrivateDesktop,
                result.ParentThreadUsesPrivateDesktop,
                parent.ToInt64(),
                result.ParentExists,
                result.ParentVisible,
                result.ParentHasPopupStyle,
                result.ParentHasToolWindowStyle,
                result.ParentHasNoActivateStyle,
                result.ParentHasVisibleStyle,
                result.ParentHasAppWindowStyle,
                result.ParentOutsideVirtualDesktop,
                result.ParentForeground,
                parentGeometry,
                DescribeRect(desktopRect),
                string.Join(",", sortedProcessIds),
                result.EmbeddedChildrenOutsideVirtualDesktop,
                result.EmbeddedChildrenHaveVisibleStyle,
                result.EmbeddedChildrenInputDisabled,
                result.EmbeddedChildHasAppWindowStyle,
                result.ParentOrDescendantForeground,
                string.Join(";", embedded.ToArray()),
                string.Join(";", hostedAuxiliary.ToArray()),
                string.Join(";", startupProbes.ToArray()),
                string.Join(";", systemAuxiliary.ToArray()),
                string.Join(";", topLevels.ToArray()));
            result.Summary += string.Format(
                " current_owner_ime_bindings={0} detached_owner_ime_bindings={1}",
                result.CurrentOwnerImeBindingCount,
                result.DetachedOwnerImeBindingCount);
            result.Summary += string.Format(
                " exact_job_membership={0} job_contains_root={1} job_process_count={2} input_desktop={3} input_exists={4} input_name_matches={5} input_is_current={6} input_is_private={7} input_enumerated={8} input_process_windows={9} input_escape_unsafe={10} input_windows=[{11}]",
                result.ExactJobMembership,
                result.JobContainsRootProcess,
                result.ExactJobProcessCount,
                observedInputDesktopName,
                result.InputDesktopExists,
                result.InputDesktopNameMatches,
                result.InputDesktopIsCurrent,
                result.InputDesktopIsPrivate,
                result.InputDesktopEnumerated,
                result.InputDesktopProcessWindowCount,
                result.InputDesktopEscapeUnsafe,
                string.Join(";", inputDesktopWindows.ToArray()));
            return result;
        }

        public static bool DisableWindowInput(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
            {
                return false;
            }
            if (!IsWindowEnabled(hwnd))
            {
                // EnableWindow sends WM_ENABLE synchronously across threads.
                // Once verified disabled, never re-enter a potentially hung UI
                // thread merely to reassert the same postcondition.
                return true;
            }
            EnableWindow(hwnd, false);
            return !IsWindowEnabled(hwnd);
        }

        private static HashSet<int> DescendantProcessIds(int rootProcessId)
        {
            HashSet<int> result = new HashSet<int>();
            result.Add(rootProcessId);
            List<PROCESSENTRY32> entries = new List<PROCESSENTRY32>();
            IntPtr snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == INVALID_HANDLE_VALUE)
            {
                return result;
            }
            try
            {
                PROCESSENTRY32 entry = new PROCESSENTRY32();
                entry.Size = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                if (Process32FirstW(snapshot, ref entry))
                {
                    do
                    {
                        entries.Add(entry);
                        entry = new PROCESSENTRY32();
                        entry.Size = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32));
                    }
                    while (Process32NextW(snapshot, ref entry));
                }
            }
            finally
            {
                CloseHandle(snapshot);
            }

            bool changed = true;
            while (changed)
            {
                changed = false;
                foreach (PROCESSENTRY32 entry in entries)
                {
                    if (result.Contains((int)entry.ParentProcessId) &&
                            result.Add((int)entry.ProcessId))
                    {
                        changed = true;
                    }
                }
            }
            return result;
        }

        private static string DescribeWindow(IntPtr hwnd, uint processId, bool visible)
        {
            RECT rect;
            string geometry = GetWindowRect(hwnd, out rect)
                ? DescribeRect(rect)
                : "<unavailable>";
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            StringBuilder windowText = new StringBuilder(512);
            GetWindowTextW(hwnd, windowText, windowText.Capacity);
            return string.Format(
                "hwnd=0x{0:X},pid={1},visible={2},parent=0x{3:X},style=0x{4:X},exstyle=0x{5:X},class={6},title={7},rect={8}",
                hwnd.ToInt64(), processId, visible, GetParent(hwnd).ToInt64(),
                GetWindowStyle(hwnd, GWL_STYLE), GetWindowStyle(hwnd, GWL_EXSTYLE),
                className.ToString(), windowText.ToString(), geometry);
        }

        private static bool IsOwnedBy(IntPtr hwnd, IntPtr expectedOwner)
        {
            IntPtr current = GetParent(hwnd);
            for (int depth = 0; depth < 32 && current != IntPtr.Zero; depth++)
            {
                if (current == expectedOwner)
                {
                    return true;
                }
                current = GetParent(current);
            }
            return false;
        }

        private static bool IsOwnedByWglDetectionWindow(IntPtr hwnd)
        {
            IntPtr current = hwnd;
            for (int depth = 0; depth < 32 && current != IntPtr.Zero; depth++)
            {
                StringBuilder className = new StringBuilder(256);
                GetClassNameW(current, className, className.Capacity);
                if (string.Equals(
                        className.ToString(), "EngineWGLDetect",
                        StringComparison.Ordinal))
                {
                    return true;
                }
                if (string.Equals(
                        className.ToString(), "NVOpenGLPbuffer",
                        StringComparison.Ordinal))
                {
                    StringBuilder title = new StringBuilder(256);
                    GetWindowTextW(current, title, title.Capacity);
                    if (string.Equals(
                            title.ToString(), "__wglDummyWindowFodder",
                            StringComparison.Ordinal))
                    {
                        return true;
                    }
                }
                current = GetParent(current);
            }
            return false;
        }

        private static Dictionary<long, ulong> DefaultImeBindingsForAcceptedWindows(
            IntPtr privateDesktop,
            IntPtr parent,
            int rootProcessId,
            HashSet<int> processIds,
            IntPtr foreground)
        {
            Dictionary<long, ulong> result = new Dictionary<long, ulong>();
            EnumWindowsProc callback = delegate(IntPtr hwnd, IntPtr ignored)
            {
                uint processId;
                uint threadId = GetWindowThreadProcessId(hwnd, out processId);
                if (!processIds.Contains((int)processId))
                {
                    return true;
                }
                bool acceptedRender = IsExactRenderWindow(
                    hwnd, parent, processId, rootProcessId);
                bool acceptedWglProbe = processId == (uint)rootProcessId &&
                    IsExactWglDetectionWindow(hwnd) &&
                    !IsWindowVisible(hwnd) && foreground != hwnd &&
                    (GetWindowStyle(hwnd, GWL_STYLE) & WS_VISIBLE) == 0 &&
                    (GetWindowStyle(hwnd, GWL_EXSTYLE) & WS_EX_APPWINDOW) == 0;
                if (!acceptedRender && !acceptedWglProbe)
                {
                    return true;
                }
                IntPtr ime = ImmGetDefaultIMEWnd(hwnd);
                if (ime == IntPtr.Zero || !IsWindow(ime))
                {
                    return true;
                }
                uint imeProcessId;
                uint imeThreadId = GetWindowThreadProcessId(ime, out imeProcessId);
                if (imeProcessId == processId && imeThreadId == threadId)
                {
                    result[ime.ToInt64()] =
                        ((ulong)imeProcessId << 32) | (ulong)imeThreadId;
                }
                return true;
            };
            EnumDesktopWindows(privateDesktop, callback, IntPtr.Zero);
            return result;
        }

        private static bool IsExactHiddenImeAuxiliary(
            IntPtr hwnd,
            RECT desktopRect,
            IntPtr foreground,
            Dictionary<long, ulong> acceptedDefaultImeBindings,
            IntPtr renderOwner,
            int rootProcessId,
            out bool usedCurrentOwnerBinding,
            out bool usedDetachedOwnerBinding)
        {
            usedCurrentOwnerBinding = false;
            usedDetachedOwnerBinding = false;
            if (!IsWindow(hwnd) || foreground == hwnd || IsWindowVisible(hwnd))
            {
                return false;
            }
            uint processId;
            uint threadId = GetWindowThreadProcessId(hwnd, out processId);
            if (processId == 0 || threadId == 0)
            {
                return false;
            }
            ulong expectedBinding;
            bool hadPrebinding = acceptedDefaultImeBindings.TryGetValue(
                hwnd.ToInt64(), out expectedBinding);
            ulong currentBinding = ((ulong)processId << 32) | (ulong)threadId;
            if ((hadPrebinding && currentBinding != expectedBinding) ||
                    ImmGetDefaultIMEWnd(hwnd) != hwnd)
            {
                return false;
            }
            IntPtr owner = GetParent(hwnd);
            if (owner == IntPtr.Zero)
            {
                // Windows can clear the HWND owner from a thread's exact
                // Default IME after an established render surface hides during
                // shutdown, while ImmGetDefaultIMEWnd(render) still returns
                // that same IME in this very sample. Accept only that current
                // live binding; an earlier observation is never authority.
                if (!hadPrebinding)
                {
                    return false;
                }
            }
            else
            {
                if (!IsWindow(owner))
                {
                    return false;
                }
                uint ownerProcessId;
                uint ownerThreadId = GetWindowThreadProcessId(
                    owner, out ownerProcessId);
                if (ownerProcessId != processId || ownerThreadId != threadId ||
                        ImmGetDefaultIMEWnd(owner) != hwnd)
                {
                    return false;
                }
                RECT renderRect;
                bool exactRenderOwner = IsExactRenderWindow(
                        owner, renderOwner, ownerProcessId, rootProcessId) &&
                    foreground != owner &&
                    GetWindowRect(owner, out renderRect) &&
                    !Intersects(renderRect, desktopRect) &&
                    (GetWindowStyle(owner, GWL_EXSTYLE) & WS_EX_APPWINDOW) == 0;
                bool exactWglOwner =
                    ownerProcessId == (uint)rootProcessId &&
                    IsExactWglDetectionWindow(owner) &&
                    !IsWindowVisible(owner) && foreground != owner &&
                    (GetWindowStyle(owner, GWL_STYLE) & WS_VISIBLE) == 0 &&
                    (GetWindowStyle(owner, GWL_EXSTYLE) & WS_EX_APPWINDOW) == 0;
                if (!exactRenderOwner && !exactWglOwner)
                {
                    return false;
                }
            }
            long style = GetWindowStyle(hwnd, GWL_STYLE);
            long extendedStyle = GetWindowStyle(hwnd, GWL_EXSTYLE);
            if ((style & WS_POPUP) == 0 || (style & WS_VISIBLE) != 0 ||
                    (style & WS_DISABLED) == 0 ||
                    (extendedStyle & WS_EX_APPWINDOW) != 0 ||
                    IsWindowEnabled(hwnd))
            {
                return false;
            }
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            StringBuilder title = new StringBuilder(256);
            GetWindowTextW(hwnd, title, title.Capacity);
            if (!string.Equals(className.ToString(), "IME", StringComparison.Ordinal) ||
                    !string.Equals(title.ToString(), "Default IME", StringComparison.Ordinal))
            {
                return false;
            }
            RECT rect;
            bool exactGeometry = GetWindowRect(hwnd, out rect) &&
                rect.Left == rect.Right && rect.Top == rect.Bottom &&
                !Intersects(rect, desktopRect);
            usedCurrentOwnerBinding = exactGeometry && !hadPrebinding;
            usedDetachedOwnerBinding = exactGeometry && hadPrebinding &&
                owner == IntPtr.Zero;
            return exactGeometry;
        }

        private static bool IsExactHiddenMsctfImeAuxiliary(
            IntPtr hwnd,
            RECT desktopRect,
            IntPtr foreground,
            Dictionary<long, ulong> acceptedDefaultImeBindings,
            IntPtr renderOwner,
            int rootProcessId)
        {
            IntPtr defaultIme = GetParent(hwnd);
            bool ignoredCurrentOwnerBinding;
            bool ignoredDetachedOwnerBinding;
            if (defaultIme == IntPtr.Zero || foreground == hwnd ||
                    IsWindowVisible(hwnd) ||
                    !IsExactHiddenImeAuxiliary(
                        defaultIme, desktopRect, foreground,
                        acceptedDefaultImeBindings, renderOwner, rootProcessId,
                        out ignoredCurrentOwnerBinding,
                        out ignoredDetachedOwnerBinding))
            {
                return false;
            }
            uint processId;
            uint threadId = GetWindowThreadProcessId(hwnd, out processId);
            uint defaultImeProcessId;
            uint defaultImeThreadId = GetWindowThreadProcessId(
                defaultIme, out defaultImeProcessId);
            if (processId != defaultImeProcessId ||
                    threadId != defaultImeThreadId)
            {
                return false;
            }
            long style = GetWindowStyle(hwnd, GWL_STYLE);
            long extendedStyle = GetWindowStyle(hwnd, GWL_EXSTYLE);
            if ((style & WS_POPUP) == 0 || (style & WS_VISIBLE) != 0 ||
                    (style & WS_DISABLED) == 0 ||
                    (extendedStyle & WS_EX_APPWINDOW) != 0 ||
                    IsWindowEnabled(hwnd))
            {
                return false;
            }
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            StringBuilder title = new StringBuilder(256);
            GetWindowTextW(hwnd, title, title.Capacity);
            if (!string.Equals(
                        className.ToString(), "MSCTFIME UI",
                        StringComparison.Ordinal) ||
                    !string.Equals(
                        title.ToString(), "MSCTFIME UI",
                        StringComparison.Ordinal))
            {
                return false;
            }
            RECT rect;
            return GetWindowRect(hwnd, out rect) &&
                rect.Left == rect.Right && rect.Top == rect.Bottom &&
                !Intersects(rect, desktopRect);
        }

        private static bool IsExactHiddenTextServicesAuxiliary(
            IntPtr hwnd,
            uint processId,
            int rootProcessId,
            IntPtr foreground)
        {
            if (processId != (uint)rootProcessId || foreground == hwnd ||
                    IsWindowVisible(hwnd))
            {
                return false;
            }
            long style = GetWindowStyle(hwnd, GWL_STYLE);
            long extendedStyle = GetWindowStyle(hwnd, GWL_EXSTYLE);
            if ((style & WS_VISIBLE) != 0 || (style & WS_DISABLED) == 0 ||
                    (extendedStyle & WS_EX_APPWINDOW) != 0)
            {
                return false;
            }
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            StringBuilder title = new StringBuilder(256);
            GetWindowTextW(hwnd, title, title.Capacity);
            string observedClass = className.ToString();
            string observedTitle = title.ToString();
            if (string.Equals(
                    observedClass, "CicLoaderWndClass",
                    StringComparison.Ordinal))
            {
                return GetParent(hwnd) == IntPtr.Zero &&
                    observedTitle.Length == 0;
            }
            if (!IsExactHiddenCiceroFrame(
                    observedClass, observedTitle, extendedStyle))
            {
                return false;
            }

            IntPtr owner = GetParent(hwnd);
            for (int depth = 0; depth < 8 && owner != IntPtr.Zero; depth++)
            {
                uint ownerProcessId;
                GetWindowThreadProcessId(owner, out ownerProcessId);
                if (ownerProcessId != (uint)rootProcessId ||
                        foreground == owner || IsWindowVisible(owner))
                {
                    return false;
                }
                long ownerStyle = GetWindowStyle(owner, GWL_STYLE);
                long ownerExtendedStyle =
                    GetWindowStyle(owner, GWL_EXSTYLE);
                if ((ownerStyle & WS_VISIBLE) != 0 ||
                        (ownerStyle & WS_DISABLED) == 0 ||
                        (ownerExtendedStyle & WS_EX_APPWINDOW) != 0)
                {
                    return false;
                }
                StringBuilder ownerClass = new StringBuilder(256);
                GetClassNameW(owner, ownerClass, ownerClass.Capacity);
                StringBuilder ownerTitle = new StringBuilder(256);
                GetWindowTextW(owner, ownerTitle, ownerTitle.Capacity);
                if (string.Equals(
                        ownerClass.ToString(), "CicLoaderWndClass",
                        StringComparison.Ordinal))
                {
                    return GetParent(owner) == IntPtr.Zero &&
                        ownerTitle.Length == 0;
                }
                if (!IsExactHiddenCiceroFrame(
                        ownerClass.ToString(), ownerTitle.ToString(),
                        ownerExtendedStyle))
                {
                    return false;
                }
                owner = GetParent(owner);
            }
            return false;
        }

        private static bool IsExactHiddenCiceroFrame(
            string className,
            string title,
            long extendedStyle)
        {
            if (!string.Equals(
                    className, "CiceroUIWndFrame", StringComparison.Ordinal) ||
                    (extendedStyle & WS_EX_TOOLWINDOW) == 0 ||
                    (extendedStyle & WS_EX_NOACTIVATE) == 0)
            {
                return false;
            }
            return string.Equals(
                    title, "CiceroUIWndFrame", StringComparison.Ordinal) ||
                string.Equals(
                    title, "TF_FloatingLangBar_WndTitle",
                    StringComparison.Ordinal);
        }

        private static bool IsExactInputIndicatorAuxiliary(
            IntPtr hwnd,
            uint processId,
            int rootProcessId,
            IntPtr foreground)
        {
            if (processId != (uint)rootProcessId || foreground == hwnd)
            {
                return false;
            }
            long style = GetWindowStyle(hwnd, GWL_STYLE);
            long extendedStyle = GetWindowStyle(hwnd, GWL_EXSTYLE);
            if ((style & WS_POPUP) == 0 ||
                    (extendedStyle & WS_EX_NOACTIVATE) == 0 ||
                    (extendedStyle & WS_EX_APPWINDOW) != 0)
            {
                return false;
            }
            RECT rect;
            if (!GetWindowRect(hwnd, out rect) ||
                    rect.Left != rect.Right || rect.Top != rect.Bottom)
            {
                return false;
            }
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            StringBuilder title = new StringBuilder(256);
            GetWindowTextW(hwnd, title, title.Capacity);
            string observedClass = className.ToString();
            string observedTitle = title.ToString();
            if ((string.Equals(
                        observedClass, "UAC_InputIndicatorOverlayWnd",
                        StringComparison.Ordinal) ||
                    string.Equals(
                        observedClass, "UAC Input Indicator",
                        StringComparison.Ordinal)) &&
                    observedTitle.Length == 0 &&
                    GetParent(hwnd) == IntPtr.Zero &&
                    IsWindowVisible(hwnd) ==
                        ((style & WS_VISIBLE) != 0))
            {
                return true;
            }
            if (!string.Equals(
                        observedClass, "Touch Tooltip Window",
                        StringComparison.Ordinal) ||
                    !string.Equals(
                        observedTitle, "Tooltip", StringComparison.Ordinal) ||
                    IsWindowVisible(hwnd) || (style & WS_VISIBLE) != 0 ||
                    (extendedStyle & WS_EX_TOOLWINDOW) == 0)
            {
                return false;
            }
            IntPtr owner = GetParent(hwnd);
            if (owner == IntPtr.Zero)
            {
                return false;
            }
            uint ownerProcessId;
            GetWindowThreadProcessId(owner, out ownerProcessId);
            StringBuilder ownerClass = new StringBuilder(256);
            GetClassNameW(owner, ownerClass, ownerClass.Capacity);
            return ownerProcessId == (uint)rootProcessId &&
                string.Equals(
                    ownerClass.ToString(), "UAC_InputIndicatorOverlayWnd",
                    StringComparison.Ordinal);
        }

        private static bool IsExactWglDetectionWindow(IntPtr hwnd)
        {
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            if (string.Equals(
                    className.ToString(), "EngineWGLDetect",
                    StringComparison.Ordinal))
            {
                return true;
            }
            if (!string.Equals(
                    className.ToString(), "NVOpenGLPbuffer",
                    StringComparison.Ordinal))
            {
                return false;
            }
            StringBuilder title = new StringBuilder(256);
            GetWindowTextW(hwnd, title, title.Capacity);
            return string.Equals(
                title.ToString(), "__wglDummyWindowFodder",
                StringComparison.Ordinal);
        }

        private static bool IsExactRenderWindow(
            IntPtr hwnd, IntPtr parent, uint processId, int rootProcessId)
        {
            if (processId != (uint)rootProcessId || GetParent(hwnd) != parent)
            {
                return false;
            }
            StringBuilder className = new StringBuilder(256);
            GetClassNameW(hwnd, className, className.Capacity);
            return string.Equals(
                className.ToString(), "Engine", StringComparison.Ordinal);
        }

        private static string DescribeRect(RECT rect)
        {
            return string.Format(
                "[{0},{1},{2},{3}]",
                rect.Left,
                rect.Top,
                rect.Right - rect.Left,
                rect.Bottom - rect.Top);
        }

        private static long GetWindowStyle(IntPtr hwnd, int index)
        {
            if (IntPtr.Size == 8)
            {
                return GetWindowLongPtr64(hwnd, index).ToInt64();
            }
            return (long)(uint)GetWindowLong32(hwnd, index);
        }

        private static RECT VirtualDesktopRect()
        {
            RECT result = new RECT();
            result.Left = GetSystemMetrics(SM_XVIRTUALSCREEN);
            result.Top = GetSystemMetrics(SM_YVIRTUALSCREEN);
            result.Right = result.Left + GetSystemMetrics(SM_CXVIRTUALSCREEN);
            result.Bottom = result.Top + GetSystemMetrics(SM_CYVIRTUALSCREEN);
            return result;
        }

        private static bool Intersects(RECT first, RECT second)
        {
            return first.Left < second.Right && first.Right > second.Left &&
                first.Top < second.Bottom && first.Bottom > second.Top;
        }
    }
}
'@
}

function New-HiddenWindowHost {
    param([bool] $RequireRenderWindow = $true)

    if ($env:OS -ne 'Windows_NT') {
        return $null
    }
    Initialize-HiddenWindowHostInterop
    $session = $null
    $ownershipTransferred = $false
    try {
        $session = New-Object -TypeName TrawfTestGate.HiddenWindowHostSession `
            -ArgumentList 1152, 648
        $handle = $session.Handle
        $initial = [TrawfTestGate.HiddenWindowHost]::Inspect(
            $session.DesktopHandle, $session.DesktopName, $handle, $PID)
        if (-not $initial.PrivateDesktopExists -or
                -not $initial.PrivateDesktopNameMatches -or
                $initial.PrivateDesktopIsInput -or
                -not $initial.ParentEnumeratedOnPrivateDesktop -or
                -not $initial.ParentThreadUsesPrivateDesktop -or
                -not $initial.ParentExists -or $initial.ParentVisible -or
                -not $initial.ParentHasPopupStyle -or
                -not $initial.ParentHasToolWindowStyle -or
                -not $initial.ParentHasNoActivateStyle -or
                $initial.ParentHasVisibleStyle -or
                $initial.ParentHasAppWindowStyle -or
                -not $initial.ParentOutsideVirtualDesktop -or
                $initial.ParentForeground -or -not $session.PumpThreadAlive -or
                $session.PumpThreadId -eq 0 -or
                $session.PumpThreadId -eq $session.CreatorThreadId) {
            throw "Hidden Windowed-test parent was not created invisible/offscreen: $($initial.Summary)"
        }
        $windowHost = [PSCustomObject] @{
            Session = $session
            DesktopHandle = $session.DesktopHandle
            DesktopName = $session.DesktopName
            DesktopPath = $session.DesktopPath
            InputDesktopHandle = $session.InputDesktopHandle
            InputDesktopName = $session.InputDesktopName
            InputDesktopPath = $session.InputDesktopPath
            Handle = $handle
            Id = $handle.ToInt64().ToString([Globalization.CultureInfo]::InvariantCulture)
            PumpThreadId = $session.PumpThreadId
            CreatorThreadId = $session.CreatorThreadId
            OffscreenPosition = [TrawfTestGate.HiddenWindowHost]::OffscreenPosition()
            RequireRenderWindow = $RequireRenderWindow
            SawEmbeddedChild = $false
            SawEmbeddedVisibleStyle = $false
            InputIsolationApplied = $false
            MonitorEstablishedBeforeResume = $false
            InputIsolationReassertions = 0
            EmbeddedWindowHandle = [int64] 0
            IsolationSampleCount = [int64] 0
            DetachedOwnerImeBindingSampleCount = [int64] 0
            JobDrainSampleCount = [int64] 0
            InputDesktopWindowSampleCount = [int64] 0
            FirstInputEscapeSummary = ''
            SuppressImePrebindingForSelfTest = $false
            LastSnapshot = $initial
        }
        $ownershipTransferred = $true
        return $windowHost
    } finally {
        if (-not $ownershipTransferred -and $null -ne $session) {
            $session.Dispose()
        }
    }
}

function Remove-HiddenWindowHost {
    param($WindowHost)
    if ($null -eq $WindowHost -or $env:OS -ne 'Windows_NT') {
        return
    }
    # Dispose retries the bounded pump/desktop teardown internally and throws
    # if ownership cannot be released. Never turn containment cleanup failure
    # into a warning followed by a nominally green gate.
    $WindowHost.Session.Dispose()
}

function Get-WindowIsolationSnapshot {
    param(
        [Parameter(Mandatory = $true)] $WindowIsolation,
        [Parameter(Mandatory = $true)] $SuspendedProcess
    )
    $snapshot = [TrawfTestGate.HiddenWindowHost]::InspectJob(
        $WindowIsolation.DesktopHandle,
        $WindowIsolation.DesktopName,
        $WindowIsolation.InputDesktopHandle,
        $WindowIsolation.InputDesktopName,
        $WindowIsolation.Handle,
        $SuspendedProcess,
        [bool] $WindowIsolation.SuppressImePrebindingForSelfTest)
    $WindowIsolation.IsolationSampleCount += 1
    if ($snapshot.DetachedOwnerImeBindingCount -gt 0) {
        $WindowIsolation.DetachedOwnerImeBindingSampleCount += 1
    }
    if ($snapshot.InputDesktopProcessWindowCount -gt 0) {
        $WindowIsolation.InputDesktopWindowSampleCount += 1
    }
    if ($snapshot.InputDesktopEscapeUnsafe -and
            [string]::IsNullOrEmpty($WindowIsolation.FirstInputEscapeSummary)) {
        $WindowIsolation.FirstInputEscapeSummary = $snapshot.Summary
        # Preserve the exact violating HWND evidence even if job termination
        # destroys it before the ordinary final snapshot is assembled.
        $WindowIsolation.LastSnapshot = $snapshot
    }
    return $snapshot
}

function Wait-For-EstablishedRenderTeardown {
    param(
        [Parameter(Mandatory = $true)] $WindowIsolation,
        [Parameter(Mandatory = $true)] $SuspendedProcess,
        [Parameter(Mandatory = $true)] $Process,
        [Parameter(Mandatory = $true)][int64] $PinnedWindowHandle,
        [Parameter(Mandatory = $true)] $InitialSnapshot
    )

    # An established render HWND may clear WS_VISIBLE (and then disappear) a
    # fraction before the root process handle signals during ordinary Win32
    # teardown. Keep sampling both desktops every millisecond; accept that
    # transition only when the root actually exits inside this bounded poll.
    # A live process with a hidden, replaced, reparented, re-enabled, focused,
    # or escaped surface remains a containment failure.
    $lastSnapshot = $InitialSnapshot
    for ($teardownPoll = 0; $teardownPoll -lt 50; $teardownPoll++) {
        if ($Process.WaitForExit(1)) {
            return [pscustomobject]@{
                ProcessExited = $true
                Snapshot = $lastSnapshot
                Failure = ''
            }
        }
        $teardownSnapshot = Get-WindowIsolationSnapshot `
            -WindowIsolation $WindowIsolation `
            -SuspendedProcess $SuspendedProcess
        $lastSnapshot = $teardownSnapshot
        # The process can signal while InspectJob is enumerating its final HWND
        # and exact Job membership. Refresh the root fact before judging that
        # final sample so teardown does not need an unmonitored grace sleep.
        if ($Process.HasExited) {
            return [pscustomobject]@{
                ProcessExited = $true
                Snapshot = $lastSnapshot
                Failure = ''
            }
        }
        $teardownHandles = @($teardownSnapshot.EmbeddedWindowHandles)
        $sameHiddenPinnedSurface =
            $teardownSnapshot.SawEmbeddedChild -and
            $teardownSnapshot.EmbeddedChildCount -eq 1 -and
            $teardownHandles -contains $PinnedWindowHandle -and
            -not $teardownSnapshot.EmbeddedChildrenHaveVisibleStyle -and
            $teardownSnapshot.EmbeddedChildrenInputDisabled -and
            $teardownSnapshot.EmbeddedChildrenOutsideVirtualDesktop -and
            -not $teardownSnapshot.EmbeddedChildHasAppWindowStyle
        $finalSurfaceGone = -not $teardownSnapshot.SawEmbeddedChild
        if (-not $teardownSnapshot.PrivateDesktopExists -or
                -not $teardownSnapshot.PrivateDesktopNameMatches -or
                $teardownSnapshot.PrivateDesktopIsInput -or
                -not $teardownSnapshot.ExactJobMembership -or
                -not $teardownSnapshot.JobContainsRootProcess -or
                -not $teardownSnapshot.InputDesktopExists -or
                -not $teardownSnapshot.InputDesktopNameMatches -or
                -not $teardownSnapshot.InputDesktopIsCurrent -or
                $teardownSnapshot.InputDesktopIsPrivate -or
                -not $teardownSnapshot.InputDesktopEnumerated -or
                $teardownSnapshot.InputDesktopEscapeUnsafe -or
                -not $teardownSnapshot.ParentEnumeratedOnPrivateDesktop -or
                -not $teardownSnapshot.ParentThreadUsesPrivateDesktop -or
                -not $teardownSnapshot.ParentExists -or
                $teardownSnapshot.ParentVisible -or
                $teardownSnapshot.ParentForeground -or
                -not $teardownSnapshot.ParentHasPopupStyle -or
                -not $teardownSnapshot.ParentHasToolWindowStyle -or
                -not $teardownSnapshot.ParentHasNoActivateStyle -or
                $teardownSnapshot.ParentHasVisibleStyle -or
                $teardownSnapshot.ParentHasAppWindowStyle -or
                -not $teardownSnapshot.ParentOutsideVirtualDesktop -or
                $teardownSnapshot.HostedAuxiliaryUnsafe -or
                $teardownSnapshot.ParentOrDescendantForeground -or
                $teardownSnapshot.DescendantTopLevelCount -gt 0 -or
                (-not $sameHiddenPinnedSurface -and -not $finalSurfaceGone)) {
            return [pscustomobject]@{
                ProcessExited = $false
                Snapshot = $lastSnapshot
                Failure = (
                    'Established render teardown changed containment topology ' +
                    'while the root process remained live: ' +
                    $teardownSnapshot.Summary)
            }
        }
    }
    return [pscustomobject]@{
        ProcessExited = $false
        Snapshot = $lastSnapshot
        Failure = (
            'The established render HWND became hidden or disappeared while ' +
            'the root process remained live after the bounded teardown poll: ' +
            $lastSnapshot.Summary)
    }
}

function Resolve-Executable {
    param(
        [string] $ExplicitPath,
        [string[]] $Candidates,
        [string] $Kind
    )

    $allCandidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $allCandidates += $ExplicitPath
    }
    $allCandidates += $Candidates

    foreach ($candidate in $allCandidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
        $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            return $command.Source
        }
    }
    throw "Unable to find $Kind. Pass its explicit path or set the documented environment variable."
}

function Resolve-GodotExecutable {
    $localGodotCandidates = @(
        (Join-Path $RepoRoot 'Godot_v4.7-stable_win64_console.exe'),
        (Join-Path $RepoRoot 'Godot_v4.7-stable_win64.exe')
    )
    $localGodotCandidates += @(Get-ChildItem -LiteralPath $RepoRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Godot_v.*(?:console|linux|win64)' } |
        Sort-Object Name -Descending |
        ForEach-Object { $_.FullName })
    return Resolve-Executable -ExplicitPath $GodotPath -Kind 'Godot' -Candidates @(
        $env:GODOT_BIN
        $localGodotCandidates
        'godot4'
        'godot'
    )
}

function Resolve-WindowedGodotExecutable {
    param([Parameter(Mandatory = $true)][string] $GodotExecutable)

    $resolvedPath = [System.IO.Path]::GetFullPath($GodotExecutable)
    if ($env:OS -ne 'Windows_NT') {
        return $resolvedPath
    }

    # Official Windows downloads ship a tiny *_console.exe wrapper beside the
    # actual GUI engine. Launching the wrapper gives that extra process a chance
    # to create top-level HWNDs before the render process consumes --wid. A
    # Windowed gate must start the GUI engine itself so the hidden parent is the
    # render process's launch-time parent contract, not a forwarded hint.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    if (-not $baseName.EndsWith('_console', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $resolvedPath
    }

    $guiBaseName = $baseName.Substring(0, $baseName.Length - '_console'.Length)
    $guiCandidate = Join-Path ([System.IO.Path]::GetDirectoryName($resolvedPath)) `
        ($guiBaseName + [System.IO.Path]::GetExtension($resolvedPath))
    if (-not (Test-Path -LiteralPath $guiCandidate -PathType Leaf)) {
        throw ("Windowed tests cannot launch the console wrapper directly, and its sibling GUI engine is missing: {0}" -f
            $guiCandidate)
    }
    return [System.IO.Path]::GetFullPath($guiCandidate)
}

function Resolve-BrowserExecutable {
    param([string[]] $AdditionalCandidates = @())

    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $browserCandidates = @(
        $env:CHROME_BIN
        $AdditionalCandidates
        'google-chrome-stable'
        'google-chrome'
        'chromium'
        'chromium-browser'
        'chrome'
        'msedge'
    )
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $browserCandidates += Join-Path $programFiles 'Google\Chrome\Application\chrome.exe'
        $browserCandidates += Join-Path $programFiles 'Microsoft\Edge\Application\msedge.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $browserCandidates += Join-Path $programFilesX86 'Google\Chrome\Application\chrome.exe'
        $browserCandidates += Join-Path $programFilesX86 'Microsoft\Edge\Application\msedge.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $browserCandidates += Join-Path $localAppData 'Google\Chrome\Application\chrome.exe'
    }
    return Resolve-Executable -ExplicitPath $BrowserPath -Kind 'Chromium browser' -Candidates $browserCandidates
}

function Read-GateLogFinalized {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [int] $TimeoutMilliseconds = 5000
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastException = $null
    while ($true) {
        $stream = $null
        $reader = $null
        try {
            # Job ActiveProcesses==0 proves no in-job thread can write again.
            # FileShare.ReadWrite tolerates kernel handle-table teardown and
            # scanner handles while preserving the completed bytes; bounded
            # retries still fail closed on an unavailable artifact.
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new(
                $stream, [System.Text.Encoding]::UTF8,
                $true, 4096, $false)
            return $reader.ReadToEnd()
        } catch [System.IO.IOException] {
            $lastException = $_.Exception
        } catch [System.UnauthorizedAccessException] {
            $lastException = $_.Exception
        } finally {
            if ($null -ne $reader) {
                $reader.Dispose()
                $stream = $null
            }
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        $remaining = $TimeoutMilliseconds -
            [int] [Math]::Min($timer.ElapsedMilliseconds, [int]::MaxValue)
        if ($remaining -le 0) {
            throw [System.IO.IOException]::new(
                "Could not acquire finalized gate log '$Path' within " +
                "$TimeoutMilliseconds ms of bounded retries.",
                $lastException)
        }
        [System.Threading.Thread]::Sleep([Math]::Min(25, $remaining))
    }
}

function Write-GateLogFinalized {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Content,
        [int] $TimeoutMilliseconds = 5000
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $lastException = $null
    while ($true) {
        $stream = $null
        try {
            # The native child is already process-tree closed. FileShare.ReadWrite
            # tolerates a short-lived scanner/indexer handle without allowing a
            # still-running descendant to masquerade as successful finalization.
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Create,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::ReadWrite)
            $bytes = $encoding.GetBytes($Content)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
            return
        } catch [System.IO.IOException] {
            $lastException = $_.Exception
        } catch [System.UnauthorizedAccessException] {
            $lastException = $_.Exception
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        $remaining = $TimeoutMilliseconds -
            [int] [Math]::Min($timer.ElapsedMilliseconds, [int]::MaxValue)
        if ($remaining -le 0) {
            throw [System.IO.IOException]::new(
                "Could not finalize gate log '$Path' within " +
                "$TimeoutMilliseconds ms of bounded retries.",
                $lastException)
        }
        [System.Threading.Thread]::Sleep([Math]::Min(25, $remaining))
    }
}

function Test-GateLogHandleClosed {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [int] $TimeoutMilliseconds = 5000
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            return $true
        } catch [System.IO.IOException] {
            # Retry only until the bounded handle-closure deadline.
        } catch [System.UnauthorizedAccessException] {
            # A transient scanner may briefly deny the exclusive probe.
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        $remaining = $TimeoutMilliseconds -
            [int] [Math]::Min($timer.ElapsedMilliseconds, [int]::MaxValue)
        if ($remaining -le 0) {
            return $false
        }
        [System.Threading.Thread]::Sleep([Math]::Min(25, $remaining))
    }
}

function Invoke-GateChild {
    param(
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [int] $ChildTimeoutSeconds = $TimeoutSeconds,
        [bool] $EchoOutput = $true,
        [string] $WorkingDirectory = $RepoRoot,
        [hashtable] $Environment = @{},
        $WindowIsolation = $null
    )

    $script:InvocationIndex += 1
    $safeLabel = ($Label -replace '[^A-Za-z0-9_.-]', '-')
    $prefix = '{0:D2}-{1}' -f $script:InvocationIndex, $safeLabel
    $stdoutPath = Join-Path $RunArtifactDirectory "$prefix.stdout.log"
    $stderrPath = Join-Path $RunArtifactDirectory "$prefix.stderr.log"
    $isolationPath = Join-Path $RunArtifactDirectory `
        "$prefix.window-isolation.log"
    $argumentLine = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')

    Write-Host "`n[GATE] $Label"
    Write-Host "[GATE] $FilePath $argumentLine"

    $process = $null
    $suspendedProcess = $null
    $stdoutTask = $null
    $stderrTask = $null
    $processStarted = $false
    # ProcessStartInfo's environment getters can throw on Windows hosts that expose both Path and
    # PATH. Gate children are launched serially, so publish only the requested overrides to the
    # current process for Start(), then restore the parent environment immediately afterward.
    $previousEnvironment = @{}
    try {
    foreach ($environmentName in $Environment.Keys) {
        $previousEnvironment[$environmentName] =
            [System.Environment]::GetEnvironmentVariable(
                $environmentName, [System.EnvironmentVariableTarget]::Process)
        [System.Environment]::SetEnvironmentVariable(
            $environmentName, [string] $Environment[$environmentName],
            [System.EnvironmentVariableTarget]::Process)
    }
    try {
        if ($null -ne $WindowIsolation -and $env:OS -eq 'Windows_NT') {
            # ProcessStartInfo.WindowStyle is ignored with UseShellExecute=false
            # on Windows PowerShell 5/.NET Framework. Use CreateProcessW so the
            # GUI child receives SW_HIDE, starts suspended, and is born on the
            # already-created private desktop with inherited log handles.
            $suspendedProcess =
                [TrawfTestGate.HiddenWindowHost]::StartSuspendedProcess(
                    $FilePath, $argumentLine, $WorkingDirectory,
                    $WindowIsolation.DesktopPath, $stdoutPath, $stderrPath)
            $process = [System.Diagnostics.Process]::GetProcessById(
                $suspendedProcess.ProcessId)
            $processStarted = $true
            $preResumeSnapshot = Get-WindowIsolationSnapshot `
                -WindowIsolation $WindowIsolation `
                -SuspendedProcess $suspendedProcess
            if (-not $preResumeSnapshot.PrivateDesktopExists -or
                    -not $preResumeSnapshot.PrivateDesktopNameMatches -or
                    $preResumeSnapshot.PrivateDesktopIsInput -or
                    -not $preResumeSnapshot.ExactJobMembership -or
                    -not $preResumeSnapshot.JobContainsRootProcess -or
                    $preResumeSnapshot.ExactJobProcessCount -ne 1 -or
                    -not $preResumeSnapshot.InputDesktopExists -or
                    -not $preResumeSnapshot.InputDesktopNameMatches -or
                    -not $preResumeSnapshot.InputDesktopIsCurrent -or
                    $preResumeSnapshot.InputDesktopIsPrivate -or
                    -not $preResumeSnapshot.InputDesktopEnumerated -or
                    $preResumeSnapshot.InputDesktopEscapeUnsafe -or
                    -not $preResumeSnapshot.ParentEnumeratedOnPrivateDesktop -or
                    -not $preResumeSnapshot.ParentThreadUsesPrivateDesktop -or
                    -not $preResumeSnapshot.ParentExists -or
                    $preResumeSnapshot.ParentVisible -or
                    -not $preResumeSnapshot.ParentHasPopupStyle -or
                    -not $preResumeSnapshot.ParentHasToolWindowStyle -or
                    -not $preResumeSnapshot.ParentHasNoActivateStyle -or
                    $preResumeSnapshot.ParentHasVisibleStyle -or
                    $preResumeSnapshot.ParentHasAppWindowStyle -or
                    -not $preResumeSnapshot.ParentOutsideVirtualDesktop -or
                    $preResumeSnapshot.ParentForeground -or
                    $preResumeSnapshot.SawEmbeddedChild -or
                    $preResumeSnapshot.HostedAuxiliaryUnsafe -or
                    $preResumeSnapshot.DescendantTopLevelCount -gt 0 -or
                    -not $WindowIsolation.Session.PumpThreadAlive) {
                throw (
                    'Private-desktop monitor could not establish the isolation ' +
                    'boundary before process resume: ' +
                    $preResumeSnapshot.Summary)
            }
            $WindowIsolation.LastSnapshot = $preResumeSnapshot
            $WindowIsolation.MonitorEstablishedBeforeResume = $true
            $suspendedProcess.Resume()
        } else {
            # Use Process directly instead of Start-Process. Windows PowerShell
            # 5.1's Start-Process -PassThru can return a blank ExitCode when
            # output is redirected, turning a failed test into a false green.
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = $FilePath
            $startInfo.Arguments = $argumentLine
            $startInfo.WorkingDirectory = $WorkingDirectory
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $startInfo
            [void] $process.Start()
            $processStarted = $true
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        }
    } catch {
        $launchFailure = $_.Exception
        if ($null -ne $suspendedProcess) {
            try {
                $suspendedProcess.Terminate(66)
                [void] $suspendedProcess.WaitForTreeExit(5000)
            } catch {
                Write-Warning (
                    'Native launch-failure process-tree cleanup also ' +
                    "failed: $($_.Exception.Message)")
            }
        } elseif ($processStarted -and $null -ne $process) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) {
                        throw "Partially launched child PID $($process.Id) did not exit."
                    }
                }
            } catch {
                Write-Warning (
                    'Ordinary launch-failure child cleanup also failed: ' +
                    "$($_.Exception.Message)")
            }
        }
        throw $launchFailure
    } finally {
        foreach ($environmentName in $Environment.Keys) {
            [System.Environment]::SetEnvironmentVariable(
                $environmentName, $previousEnvironment[$environmentName],
                [System.EnvironmentVariableTarget]::Process)
        }
    }
    # Keep long release children visibly accountable even though their complete
    # stdout/stderr remains atomic and is emitted only after exit. A bounded
    # heartbeat distinguishes an active required child from a frozen launcher
    # without weakening timeout, exit-code, or log-capture semantics.
    $childStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeoutMilliseconds = [int64] $ChildTimeoutSeconds * 1000
    $nextHeartbeatMilliseconds = 30000
    $completed = $false
    $windowIsolationFailed = $false
    $windowIsolationFailure = ''
    while (-not $completed -and -not $windowIsolationFailed -and
            $childStopwatch.ElapsedMilliseconds -lt $timeoutMilliseconds) {
        $remainingMilliseconds = $timeoutMilliseconds - $childStopwatch.ElapsedMilliseconds
        $maximumWaitSlice = if ($null -eq $WindowIsolation) {
            5000
        } elseif (-not $WindowIsolation.RequireRenderWindow) {
            # Headless/export processes still receive exact desktop and Job
            # attestation, but they have no render HWND whose first ShowWindow
            # must be intercepted at sub-frame latency.
            25
        } elseif (-not $WindowIsolation.InputIsolationApplied) {
            # Secure the hidden render HWND before Godot's first ShowWindow /
            # SetForegroundWindow pair. Once disabled, ordinary 25 ms topology
            # attestation is sufficient for the rest of the run.
            1
        } else {
            25
        }
        $waitSliceMilliseconds = [int] [Math]::Min($maximumWaitSlice, $remainingMilliseconds)
        $completed = $process.WaitForExit($waitSliceMilliseconds)
        if ($null -ne $WindowIsolation -and $env:OS -eq 'Windows_NT') {
            try {
            $windowSnapshot = Get-WindowIsolationSnapshot `
                -WindowIsolation $WindowIsolation `
                -SuspendedProcess $suspendedProcess
            # A process can destroy its final HWND just before WaitForExit's
            # wait handle reports signaled. Refresh HasExited after inspection
            # so normal teardown is not misclassified as topology escape.
            $processExitedDuringInspection = $completed -or $process.HasExited
            if (-not $processExitedDuringInspection -and
                    $WindowIsolation.SawEmbeddedChild -and
                    -not $windowSnapshot.SawEmbeddedChild) {
                # Normal Win32 teardown can destroy the final HWND a fraction
                # before the process handle signals. Poll both facts together;
                # never insert a blind grace period in the desktop boundary.
                for ($teardownPoll = 0; $teardownPoll -lt 50; $teardownPoll++) {
                    if ($process.WaitForExit(1)) {
                        $processExitedDuringInspection = $true
                        break
                    }
                    $teardownSnapshot = Get-WindowIsolationSnapshot `
                        -WindowIsolation $WindowIsolation `
                        -SuspendedProcess $suspendedProcess
                    $windowSnapshot = $teardownSnapshot
                    if ($process.HasExited) {
                        $processExitedDuringInspection = $true
                        break
                    }
                    if (-not $teardownSnapshot.PrivateDesktopExists -or
                            -not $teardownSnapshot.PrivateDesktopNameMatches -or
                            $teardownSnapshot.PrivateDesktopIsInput -or
                            -not $teardownSnapshot.ExactJobMembership -or
                            -not $teardownSnapshot.JobContainsRootProcess -or
                            -not $teardownSnapshot.InputDesktopExists -or
                            -not $teardownSnapshot.InputDesktopNameMatches -or
                            -not $teardownSnapshot.InputDesktopIsCurrent -or
                            $teardownSnapshot.InputDesktopIsPrivate -or
                            -not $teardownSnapshot.InputDesktopEnumerated -or
                            $teardownSnapshot.InputDesktopEscapeUnsafe -or
                            -not $teardownSnapshot.ParentEnumeratedOnPrivateDesktop -or
                            -not $teardownSnapshot.ParentThreadUsesPrivateDesktop -or
                            -not $teardownSnapshot.ParentExists -or
                            $teardownSnapshot.SawEmbeddedChild -or
                            $teardownSnapshot.ParentVisible -or
                            $teardownSnapshot.ParentForeground -or
                            -not $teardownSnapshot.ParentHasPopupStyle -or
                            -not $teardownSnapshot.ParentHasToolWindowStyle -or
                            -not $teardownSnapshot.ParentHasNoActivateStyle -or
                            $teardownSnapshot.ParentHasVisibleStyle -or
                            $teardownSnapshot.ParentHasAppWindowStyle -or
                            -not $teardownSnapshot.ParentOutsideVirtualDesktop -or
                            $teardownSnapshot.HostedAuxiliaryUnsafe -or
                            $teardownSnapshot.ParentOrDescendantForeground -or
                            $teardownSnapshot.DescendantTopLevelCount -gt 0) {
                        break
                    }
                }
            }
            if ($processExitedDuringInspection) {
                $completed = $true
            }
            $observedEmbeddedHandles = @($windowSnapshot.EmbeddedWindowHandles)
            if ($windowSnapshot.SawEmbeddedChild) {
                if (-not $WindowIsolation.SawEmbeddedChild -and
                        $windowSnapshot.EmbeddedChildCount -eq 1) {
                    $WindowIsolation.EmbeddedWindowHandle =
                        [int64] $observedEmbeddedHandles[0]
                }
                if (-not $windowIsolationFailed -and
                        (-not $windowSnapshot.PrivateDesktopExists -or
                         -not $windowSnapshot.PrivateDesktopNameMatches -or
                         $windowSnapshot.PrivateDesktopIsInput -or
                         -not $windowSnapshot.ExactJobMembership -or
                         -not $windowSnapshot.JobContainsRootProcess -or
                         -not $windowSnapshot.InputDesktopExists -or
                         -not $windowSnapshot.InputDesktopNameMatches -or
                         -not $windowSnapshot.InputDesktopIsCurrent -or
                         $windowSnapshot.InputDesktopIsPrivate -or
                         -not $windowSnapshot.InputDesktopEnumerated -or
                         $windowSnapshot.InputDesktopEscapeUnsafe -or
                         -not $windowSnapshot.ParentEnumeratedOnPrivateDesktop -or
                         -not $windowSnapshot.ParentThreadUsesPrivateDesktop -or
                         -not $windowSnapshot.ParentExists -or
                         $windowSnapshot.ParentVisible -or
                         -not $windowSnapshot.ParentHasPopupStyle -or
                         -not $windowSnapshot.ParentHasToolWindowStyle -or
                         -not $windowSnapshot.ParentHasNoActivateStyle -or
                         $windowSnapshot.ParentHasVisibleStyle -or
                         $windowSnapshot.ParentHasAppWindowStyle -or
                         -not $windowSnapshot.ParentOutsideVirtualDesktop -or
                         $windowSnapshot.EmbeddedChildCount -ne 1 -or
                         -not $windowSnapshot.EmbeddedChildrenOutsideVirtualDesktop -or
                         $windowSnapshot.EmbeddedChildHasAppWindowStyle -or
                         $windowSnapshot.HostedAuxiliaryUnsafe -or
                         $windowSnapshot.DescendantTopLevelCount -gt 0)) {
                    $windowIsolationFailed = $true
                    $windowIsolationFailure =
                        'Private-desktop render preflight failed before reveal: ' +
                        $windowSnapshot.Summary
                }
                if (-not $windowIsolationFailed -and
                        $windowSnapshot.EmbeddedChildCount -eq 1 -and
                        $WindowIsolation.EmbeddedWindowHandle -ne 0 -and
                        $observedEmbeddedHandles -contains
                            [int64] $WindowIsolation.EmbeddedWindowHandle) {
                    $inputWasDisabled =
                        $windowSnapshot.EmbeddedChildrenInputDisabled
                    $inputIsolationSucceeded =
                        [TrawfTestGate.HiddenWindowHost]::DisableWindowInput(
                            [IntPtr] $WindowIsolation.EmbeddedWindowHandle)
                    if (-not $inputIsolationSucceeded) {
                        if ($WindowIsolation.SawEmbeddedVisibleStyle) {
                            $teardownResult = Wait-For-EstablishedRenderTeardown `
                                -WindowIsolation $WindowIsolation `
                                -SuspendedProcess $suspendedProcess `
                                -Process $process `
                                -PinnedWindowHandle ([int64] $WindowIsolation.EmbeddedWindowHandle) `
                                -InitialSnapshot $windowSnapshot
                            $windowSnapshot = $teardownResult.Snapshot
                            if ($teardownResult.ProcessExited) {
                                $processExitedDuringInspection = $true
                                $completed = $true
                            } else {
                                $windowIsolationFailed = $true
                                $windowIsolationFailure = $teardownResult.Failure
                            }
                        } else {
                            $windowIsolationFailed = $true
                            $windowIsolationFailure =
                                "Could not disable OS input/focus on the embedded render HWND."
                        }
                    } else {
                        if ($WindowIsolation.InputIsolationApplied -and
                                -not $inputWasDisabled) {
                            $WindowIsolation.InputIsolationReassertions += 1
                        }
                        $WindowIsolation.InputIsolationApplied = $true
                        # Inspect precedes this mutation by microseconds; publish
                        # the verified postcondition to the current attestation.
                        $windowSnapshot.EmbeddedChildrenInputDisabled = $true
                        if (-not $windowSnapshot.EmbeddedChildrenHaveVisibleStyle) {
                            if ($WindowIsolation.SawEmbeddedVisibleStyle) {
                                # Never conceal a mid-run visibility regression
                                # by re-revealing it. Only a root handle that
                                # signals during continuously attested teardown
                                # makes this established-surface transition valid.
                                $teardownResult = Wait-For-EstablishedRenderTeardown `
                                    -WindowIsolation $WindowIsolation `
                                    -SuspendedProcess $suspendedProcess `
                                    -Process $process `
                                    -PinnedWindowHandle ([int64] $WindowIsolation.EmbeddedWindowHandle) `
                                    -InitialSnapshot $windowSnapshot
                                $windowSnapshot = $teardownResult.Snapshot
                                if ($teardownResult.ProcessExited) {
                                    $processExitedDuringInspection = $true
                                    $completed = $true
                                } else {
                                    $windowIsolationFailed = $true
                                    $windowIsolationFailure =
                                        $teardownResult.Failure
                                }
                            } elseif ([TrawfTestGate.HiddenWindowHost]::WindowHasNonEmptyTitle(
                                        [IntPtr] $WindowIsolation.EmbeddedWindowHandle)) {
                                $revealSucceeded =
                                    [TrawfTestGate.HiddenWindowHost]::RevealDisabledWindowWithoutActivation(
                                        [IntPtr] $WindowIsolation.EmbeddedWindowHandle)
                                $privateDesktopStillIsolated =
                                    [TrawfTestGate.HiddenWindowHost]::IsPrivateDesktopNotInput(
                                        $WindowIsolation.DesktopHandle,
                                        $WindowIsolation.DesktopName)
                                if (-not $revealSucceeded -or
                                        -not $privateDesktopStillIsolated) {
                                    # Before the first proven WS_VISIBLE sample,
                                    # teardown cannot make a missing/hidden HWND
                                    # valid: a required Windowed lane must first
                                    # establish its real framebuffer.
                                    $windowIsolationFailed = $true
                                    $windowIsolationFailure =
                                        'Could not reveal the disabled render HWND ' +
                                        'without activating the private desktop.'
                                } else {
                                    $windowSnapshot.EmbeddedChildVisible = $true
                                    $windowSnapshot.EmbeddedChildrenHaveVisibleStyle = $true
                                }
                            }
                        }
                    }
                }
                $WindowIsolation.SawEmbeddedChild = $true
                if ($windowSnapshot.EmbeddedChildrenHaveVisibleStyle) {
                    $WindowIsolation.SawEmbeddedVisibleStyle = $true
                }
                $WindowIsolation.LastSnapshot = $windowSnapshot
            } elseif (-not $WindowIsolation.SawEmbeddedChild) {
                $WindowIsolation.LastSnapshot = $windowSnapshot
            }
            if (-not $windowIsolationFailed -and
                    (-not $WindowIsolation.MonitorEstablishedBeforeResume -or
                    -not $windowSnapshot.PrivateDesktopExists -or
                    -not $windowSnapshot.PrivateDesktopNameMatches -or
                    $windowSnapshot.PrivateDesktopIsInput -or
                    -not $windowSnapshot.ExactJobMembership -or
                    (-not $processExitedDuringInspection -and
                        -not $windowSnapshot.JobContainsRootProcess) -or
                    -not $windowSnapshot.InputDesktopExists -or
                    -not $windowSnapshot.InputDesktopNameMatches -or
                    -not $windowSnapshot.InputDesktopIsCurrent -or
                    $windowSnapshot.InputDesktopIsPrivate -or
                    -not $windowSnapshot.InputDesktopEnumerated -or
                    $windowSnapshot.InputDesktopEscapeUnsafe -or
                    -not $windowSnapshot.ParentEnumeratedOnPrivateDesktop -or
                    -not $windowSnapshot.ParentThreadUsesPrivateDesktop -or
                    -not $windowSnapshot.ParentExists -or
                    -not $WindowIsolation.Session.PumpThreadAlive -or
                    $windowSnapshot.ParentVisible -or
                    -not $windowSnapshot.ParentHasPopupStyle -or
                    -not $windowSnapshot.ParentHasToolWindowStyle -or
                    -not $windowSnapshot.ParentHasNoActivateStyle -or
                    $windowSnapshot.ParentHasVisibleStyle -or
                    $windowSnapshot.ParentHasAppWindowStyle -or
                    -not $windowSnapshot.ParentOutsideVirtualDesktop -or
                    ($windowSnapshot.SawEmbeddedChild -and
                        ($windowSnapshot.EmbeddedChildCount -ne 1 -or
                         -not $windowSnapshot.EmbeddedChildrenOutsideVirtualDesktop -or
                         $windowSnapshot.EmbeddedChildHasAppWindowStyle)) -or
                    ($WindowIsolation.SawEmbeddedVisibleStyle -and
                        -not $processExitedDuringInspection -and
                        $windowSnapshot.SawEmbeddedChild -and
                        -not $windowSnapshot.EmbeddedChildrenHaveVisibleStyle) -or
                    ($windowSnapshot.SawEmbeddedChild -and
                        -not $WindowIsolation.SawEmbeddedVisibleStyle -and
                        $childStopwatch.ElapsedMilliseconds -ge 5000) -or
                    ($WindowIsolation.SawEmbeddedChild -and
                        -not $processExitedDuringInspection -and
                        -not $windowSnapshot.SawEmbeddedChild) -or
                    ($WindowIsolation.EmbeddedWindowHandle -ne 0 -and
                        $windowSnapshot.SawEmbeddedChild -and
                        $observedEmbeddedHandles -notcontains
                            [int64] $WindowIsolation.EmbeddedWindowHandle) -or
                    ($WindowIsolation.InputIsolationApplied -and
                        $windowSnapshot.SawEmbeddedChild -and
                        -not $windowSnapshot.EmbeddedChildrenInputDisabled) -or
                    $windowSnapshot.HostedAuxiliaryUnsafe -or
                    $windowSnapshot.ParentOrDescendantForeground -or
                    $windowSnapshot.DescendantTopLevelCount -gt 0)) {
                $windowIsolationFailed = $true
                $windowIsolationFailure = (
                    "Native process violated private-desktop/hidden-owner topology: " +
                    "pump_thread=$($WindowIsolation.PumpThreadId) " +
                    "creator_thread=$($WindowIsolation.CreatorThreadId) " +
                    $windowSnapshot.Summary)
            }
            } catch {
                $windowIsolationFailed = $true
                $windowIsolationFailure =
                    "Window-isolation monitor failed closed: $($_.Exception.Message)"
            }
        }
        if (-not $completed -and $childStopwatch.ElapsedMilliseconds -ge $nextHeartbeatMilliseconds) {
            Write-Host ("[GATE] WAIT: {0} still running after {1:N0}s (PID {2}, timeout {3}s)." -f
                $Label, [Math]::Floor($childStopwatch.Elapsed.TotalSeconds),
                $process.Id, $ChildTimeoutSeconds)
            $nextHeartbeatMilliseconds += 30000
        }
    }
    $childStopwatch.Stop()
    $timedOut = -not $completed -and -not $windowIsolationFailed
    $mustTerminate = $timedOut -or $windowIsolationFailed
    $nativeExitCode = $null
    $nativeTreeClosed = $null -eq $suspendedProcess
    if ($mustTerminate -and $null -ne $suspendedProcess) {
        try {
            $terminationExitCode = if ($timedOut) { 124 } else { 66 }
            $suspendedProcess.Terminate([uint32] $terminationExitCode)
            $nativeTreeClosed = $suspendedProcess.WaitForTreeExit(5000)
        } catch {
            $windowIsolationFailed = $true
            if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                $windowIsolationFailure += ' '
            }
            $windowIsolationFailure +=
                "Native process-tree termination failed: $($_.Exception.Message)"
        }
        if (-not $nativeTreeClosed) {
            $windowIsolationFailed = $true
            if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                $windowIsolationFailure += ' '
            }
            $windowIsolationFailure +=
                'Native process tree remained active after the 5-second termination deadline.'
        }
        if (-not $process.HasExited -and -not $process.WaitForExit(5000)) {
            $windowIsolationFailed = $true
            if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                $windowIsolationFailure += ' '
            }
            $windowIsolationFailure +=
                "Native root PID $($process.Id) remained active after tree termination."
        }
    } elseif ($mustTerminate) {
        $treeKillSucceeded = $false
        try {
            # .NET Core can terminate the whole tree (important when Node owns
            # Chromium). Windows PowerShell 5.1 lacks this overload, and killing
            # only Godot's console wrapper leaves its engine child running. Use
            # taskkill against this exact child PID on Windows so a timed-out
            # gate cannot contaminate the next serialized test or touch an
            # unrelated editor process.
            if ($env:OS -eq 'Windows_NT') {
                $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                if (Test-Path -LiteralPath $taskkill -PathType Leaf) {
                    & $taskkill /PID $process.Id /T /F 2>$null | Out-Null
                    $treeKillSucceeded = $LASTEXITCODE -eq 0
                }
            } else {
                try {
                    $process.Kill($true)
                    $treeKillSucceeded = $true
                } catch [System.Management.Automation.MethodException] {
                    $process.Kill()
                    $treeKillSucceeded = $true
                }
            }
            if (-not $treeKillSucceeded -and -not $process.HasExited) {
                # Last-resort wrapper kill. It may not own the full tree on old
                # Windows PowerShell, so the bounded wait below still applies.
                $process.Kill()
            }
        } catch {
            Write-Warning "Could not terminate bounded/isolated child: $_"
        }
        if (-not $process.HasExited -and -not $process.WaitForExit(5000)) {
            Write-Warning "Bounded/isolated child PID $($process.Id) did not exit within the 5-second termination grace period."
        }
    } else {
        # Flush native process bookkeeping after the successful bounded wait.
        $process.WaitForExit()
    }

    if ($null -ne $suspendedProcess) {
        if ($process.HasExited) {
            try {
                # Preserve the root result from the original CreateProcessW
                # handle before any kill-on-close job/session disposal.
                $nativeExitCode = $suspendedProcess.GetExitCode()
            } catch {
                $windowIsolationFailed = $true
                if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                    $windowIsolationFailure += ' '
                }
                $windowIsolationFailure +=
                    "Native exit-code capture failed: $($_.Exception.Message)"
            }
        }
        if (-not $mustTerminate) {
            try {
                # The root can exit before an in-job descendant closes inherited
                # log handles. Keep attesting both desktops throughout that
                # drain; a descendant does not receive a blind grace interval.
                $jobDrainTimer = [System.Diagnostics.Stopwatch]::StartNew()
                $nativeTreeClosed = $false
                while ($jobDrainTimer.ElapsedMilliseconds -lt 2000) {
                    $remainingJobProcessIds = @(
                        $suspendedProcess.GetProcessIds())
                    if ($remainingJobProcessIds.Count -eq 0) {
                        $nativeTreeClosed = $true
                        break
                    }
                    $jobDrainSnapshot = Get-WindowIsolationSnapshot `
                        -WindowIsolation $WindowIsolation `
                        -SuspendedProcess $suspendedProcess
                    $WindowIsolation.JobDrainSampleCount += 1
                    if (-not $jobDrainSnapshot.ExactJobMembership -or
                            -not $jobDrainSnapshot.PrivateDesktopExists -or
                            -not $jobDrainSnapshot.PrivateDesktopNameMatches -or
                            $jobDrainSnapshot.PrivateDesktopIsInput -or
                            -not $jobDrainSnapshot.InputDesktopExists -or
                            -not $jobDrainSnapshot.InputDesktopNameMatches -or
                            -not $jobDrainSnapshot.InputDesktopIsCurrent -or
                            $jobDrainSnapshot.InputDesktopIsPrivate -or
                            -not $jobDrainSnapshot.InputDesktopEnumerated -or
                            $jobDrainSnapshot.InputDesktopEscapeUnsafe -or
                            -not $jobDrainSnapshot.ParentEnumeratedOnPrivateDesktop -or
                            -not $jobDrainSnapshot.ParentThreadUsesPrivateDesktop -or
                            -not $jobDrainSnapshot.ParentExists -or
                            $jobDrainSnapshot.ParentVisible -or
                            $jobDrainSnapshot.ParentForeground -or
                            -not $jobDrainSnapshot.ParentHasPopupStyle -or
                            -not $jobDrainSnapshot.ParentHasToolWindowStyle -or
                            -not $jobDrainSnapshot.ParentHasNoActivateStyle -or
                            $jobDrainSnapshot.ParentHasVisibleStyle -or
                            $jobDrainSnapshot.ParentHasAppWindowStyle -or
                            -not $jobDrainSnapshot.ParentOutsideVirtualDesktop -or
                            $jobDrainSnapshot.SawEmbeddedChild -or
                            $jobDrainSnapshot.HostedAuxiliaryUnsafe -or
                            $jobDrainSnapshot.ParentOrDescendantForeground -or
                            $jobDrainSnapshot.DescendantTopLevelCount -gt 0) {
                        $windowIsolationFailed = $true
                        $WindowIsolation.LastSnapshot = $jobDrainSnapshot
                        if (-not [string]::IsNullOrEmpty(
                                    $windowIsolationFailure)) {
                            $windowIsolationFailure += ' '
                        }
                        $windowIsolationFailure +=
                            'A live post-root job descendant violated desktop containment: ' +
                            $jobDrainSnapshot.Summary
                        $suspendedProcess.Terminate(66)
                        $nativeTreeClosed =
                            $suspendedProcess.WaitForTreeExit(5000)
                        break
                    }
                    [System.Threading.Thread]::Sleep(1)
                }
                $jobDrainTimer.Stop()
                if (-not $nativeTreeClosed -and -not $windowIsolationFailed) {
                    $windowIsolationFailed = $true
                    if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                        $windowIsolationFailure += ' '
                    }
                    $windowIsolationFailure +=
                        'The native root exited while descendants retained the process job; ' +
                        'the lane was terminated to prevent inherited log handles crossing lanes.'
                    $suspendedProcess.Terminate(66)
                    $nativeTreeClosed =
                        $suspendedProcess.WaitForTreeExit(5000)
                    if (-not $nativeTreeClosed) {
                        $windowIsolationFailure +=
                            ' The process tree remained active after the 5-second termination deadline.'
                    }
                }
            } catch {
                $treeInspectionException = $_.Exception
                $windowIsolationFailed = $true
                if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
                    $windowIsolationFailure += ' '
                }
                $windowIsolationFailure +=
                    "Native process-tree finalization failed: $($treeInspectionException.Message)"
                try {
                    $suspendedProcess.Terminate(66)
                    $nativeTreeClosed =
                        $suspendedProcess.WaitForTreeExit(5000)
                } catch {
                    $windowIsolationFailure +=
                        " Emergency job termination failed: $($_.Exception.Message)"
                }
            }
        }
    }

    # Native logs are read only after the job reports zero active processes, so
    # no descendant can retain inherited stdout/stderr into the next lane.
    $stdout = ''
    $stderr = ''
    $nativeLogReadFailure = ''
    if ($null -ne $suspendedProcess) {
        if (-not $nativeTreeClosed) {
            $stderr = (
                '[GATE] ERROR: Native child logs were not read or rewritten ' +
                "because the process job did not reach zero active processes.`n")
        } else {
            try {
                $stdout = Read-GateLogFinalized -Path $stdoutPath
            } catch {
                $nativeLogReadFailure =
                    "stdout: $($_.Exception.Message)"
            }
            try {
                $stderr = Read-GateLogFinalized -Path $stderrPath
            } catch {
                if (-not [string]::IsNullOrEmpty($nativeLogReadFailure)) {
                    $nativeLogReadFailure += '; '
                }
                $nativeLogReadFailure +=
                    "stderr: $($_.Exception.Message)"
            }
            if (-not [string]::IsNullOrEmpty($nativeLogReadFailure)) {
                $stderr +=
                    "[GATE] ERROR: Native log acquisition failed closed: $nativeLogReadFailure`n"
            }
        }
    } else {
        try {
            if ($stdoutTask.Wait(5000)) {
                $stdout = $stdoutTask.Result
            } else {
                $stdout = "[GATE] stdout remained open after child timeout.`n"
            }
        } catch {
            $stdout = "[GATE] Could not collect child stdout: $_`n"
        }
        try {
            if ($stderrTask.Wait(5000)) {
                $stderr = $stderrTask.Result
            } else {
                $stderr = "[GATE] stderr remained open after child timeout.`n"
            }
        } catch {
            $stderr = "[GATE] Could not collect child stderr: $_`n"
        }
    }

    if ($null -ne $WindowIsolation -and $env:OS -eq 'Windows_NT') {
        if (-not $process.HasExited) {
            $windowSnapshot = Get-WindowIsolationSnapshot `
                -WindowIsolation $WindowIsolation `
                -SuspendedProcess $suspendedProcess
            if ($windowSnapshot.SawEmbeddedChild) {
                $WindowIsolation.SawEmbeddedChild = $true
                $WindowIsolation.LastSnapshot = $windowSnapshot
            } elseif (-not $WindowIsolation.SawEmbeddedChild) {
                $WindowIsolation.LastSnapshot = $windowSnapshot
            }
        }
        if ((-not $WindowIsolation.MonitorEstablishedBeforeResume -or
                -not [TrawfTestGate.HiddenWindowHost]::IsPrivateDesktopNotInput(
                    $WindowIsolation.DesktopHandle,
                    $WindowIsolation.DesktopName)) -and
                -not $windowIsolationFailed) {
            $windowIsolationFailed = $true
            $windowIsolationFailure =
                'Private desktop was not continuously isolated from the input desktop.'
        }
        if ($WindowIsolation.RequireRenderWindow -and
                -not $WindowIsolation.SawEmbeddedChild -and
                -not $windowIsolationFailed) {
            $windowIsolationFailed = $true
            $windowIsolationFailure =
                "Windowed process never created a render HWND owned by the hidden host: $($WindowIsolation.LastSnapshot.Summary)"
        }
        if ($WindowIsolation.RequireRenderWindow -and
                -not $WindowIsolation.InputIsolationApplied -and
                -not $windowIsolationFailed) {
            $windowIsolationFailed = $true
            $windowIsolationFailure =
                "Windowed render HWND never established disabled OS-input/focus isolation: $($WindowIsolation.LastSnapshot.Summary)"
        }
        if ($WindowIsolation.RequireRenderWindow -and
                -not $WindowIsolation.SawEmbeddedVisibleStyle -and
                -not $windowIsolationFailed) {
            $windowIsolationFailed = $true
            $windowIsolationFailure =
                "Windowed render HWND never reached its real-swapchain WS_VISIBLE style: $($WindowIsolation.LastSnapshot.Summary)"
        }
        if (-not [string]::IsNullOrEmpty(
                    $WindowIsolation.FirstInputEscapeSummary) -and
                -not $windowIsolationFailed) {
            $windowIsolationFailed = $true
            $windowIsolationFailure =
                'An unsafe input-desktop HWND was recorded by the isolation ledger: ' +
                $WindowIsolation.FirstInputEscapeSummary
        }
        $lastEmbeddedHandles = @(
            $WindowIsolation.LastSnapshot.EmbeddedWindowHandles)
        if ($WindowIsolation.InputIsolationApplied -and
                $WindowIsolation.LastSnapshot.SawEmbeddedChild -and
                $lastEmbeddedHandles -contains
                    [int64] $WindowIsolation.EmbeddedWindowHandle) {
            # InputIsolationApplied is set only after DisableWindowInput verifies
            # !IsWindowEnabled on this exact HWND. A final root-teardown inspect
            # can retain an earlier rendered Summary string, so bind and publish
            # the verified postcondition instead of persisting stale text.
            $WindowIsolation.LastSnapshot.EmbeddedChildrenInputDisabled = $true
            $WindowIsolation.LastSnapshot.Summary = [regex]::Replace(
                $WindowIsolation.LastSnapshot.Summary,
                'embedded_input_disabled=(?:True|False)',
                'embedded_input_disabled=True',
                1)
        }
        $firstInputEscapeEvidence = if ([string]::IsNullOrEmpty(
                $WindowIsolation.FirstInputEscapeSummary)) {
            '<none>'
        } else {
            $WindowIsolation.FirstInputEscapeSummary
        }
        $windowIsolationLine = (
            "[GATE] WINDOW ISOLATION: private_desktop=$($WindowIsolation.DesktopName) " +
            "render_window_required=$($WindowIsolation.RequireRenderWindow) " +
            "monitor_before_resume=$($WindowIsolation.MonitorEstablishedBeforeResume) " +
            "pump_thread=$($WindowIsolation.PumpThreadId) " +
            "creator_thread=$($WindowIsolation.CreatorThreadId) " +
            "input_reassertions=$($WindowIsolation.InputIsolationReassertions) " +
            "isolation_samples=$($WindowIsolation.IsolationSampleCount) " +
            "detached_ime_binding_samples=$($WindowIsolation.DetachedOwnerImeBindingSampleCount) " +
            "job_drain_samples=$($WindowIsolation.JobDrainSampleCount) " +
            "job_tree_closed=$nativeTreeClosed " +
            "input_window_samples=$($WindowIsolation.InputDesktopWindowSampleCount) " +
            "first_input_escape=[$firstInputEscapeEvidence] " +
            $WindowIsolation.LastSnapshot.Summary)
        $stdout = "$stdout$windowIsolationLine`n"
        if ($windowIsolationFailed) {
            $stderr = "$stderr[GATE] ERROR: $windowIsolationFailure`n"
        }
    }
    $logFinalizationFailures = New-Object System.Collections.Generic.List[string]
    if ($null -ne $WindowIsolation -and $env:OS -eq 'Windows_NT') {
        $isolationEvidence = "$windowIsolationLine`n"
        if ($windowIsolationFailed) {
            $isolationEvidence += "[GATE] ERROR: $windowIsolationFailure`n"
        }
        try {
            Write-GateLogFinalized -Path $isolationPath `
                -Content $isolationEvidence
        } catch {
            [void] $logFinalizationFailures.Add(
                "isolation attestation: $($_.Exception.Message)")
        }
    }
    if ($null -ne $suspendedProcess -and -not $nativeTreeClosed) {
        [void] $logFinalizationFailures.Add(
            'native process job still had active processes')
    }
    if (-not [string]::IsNullOrEmpty($nativeLogReadFailure)) {
        [void] $logFinalizationFailures.Add(
            "native log acquisition: $nativeLogReadFailure")
    }
    if (($null -eq $suspendedProcess -or $nativeTreeClosed) -and
            [string]::IsNullOrEmpty($nativeLogReadFailure)) {
        try {
            Write-GateLogFinalized -Path $stdoutPath -Content $stdout
        } catch {
            [void] $logFinalizationFailures.Add(
                "stdout: $($_.Exception.Message)")
        }
        if ($logFinalizationFailures.Count -gt 0) {
            $stderr += (
                '[GATE] ERROR: Gate log finalization failed closed: ' +
                ($logFinalizationFailures -join '; ') + "`n")
        }
        try {
            Write-GateLogFinalized -Path $stderrPath -Content $stderr
        } catch {
            [void] $logFinalizationFailures.Add(
                "stderr: $($_.Exception.Message)")
        }
    }
    if ($logFinalizationFailures.Count -gt 0) {
        $windowIsolationFailed = $true
        $finalizationFailure =
            'Gate log finalization failed closed: ' +
            ($logFinalizationFailures -join '; ')
        if (-not [string]::IsNullOrEmpty($windowIsolationFailure)) {
            $finalizationFailure +=
                ". Containment status: $windowIsolationFailure"
        }
        if ($null -ne $WindowIsolation -and $env:OS -eq 'Windows_NT') {
            try {
                Write-GateLogFinalized -Path $isolationPath -Content (
                    "$windowIsolationLine`n[GATE] ERROR: $finalizationFailure`n")
            } catch {
                $finalizationFailure +=
                    ". Isolation attestation retry also failed: $($_.Exception.Message)"
            }
        }
        $stderr += "[GATE] ERROR: $finalizationFailure`n"
    }
    if ($EchoOutput -and -not [string]::IsNullOrEmpty($stdout)) {
        [Console]::Out.Write($stdout)
    }
    if ($EchoOutput -and -not [string]::IsNullOrEmpty($stderr)) {
        [Console]::Error.Write($stderr)
    }
    if ($logFinalizationFailures.Count -gt 0) {
        throw [System.IO.IOException]::new($finalizationFailure)
    }

    $exitCode = if ($timedOut) {
        124
    } elseif ($windowIsolationFailed) {
        66
    } elseif ($null -ne $suspendedProcess) {
        $nativeExitCode
    } else {
        $process.ExitCode
    }
    return [PSCustomObject]@{
        Label = $Label
        ExitCode = $exitCode
        TimedOut = $timedOut
        WindowIsolationFailed = $windowIsolationFailed
        Stdout = $stdout
        Stderr = $stderr
        Output = "$stdout`n$stderr"
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
        IsolationPath = if ($null -ne $WindowIsolation) {
            $isolationPath
        } else {
            $null
        }
    }
    } finally {
        try {
            if ($null -ne $suspendedProcess) {
                try {
                    if (-not $suspendedProcess.WaitForTreeExit(0)) {
                        $suspendedProcess.Terminate(66)
                        if (-not $suspendedProcess.WaitForTreeExit(5000)) {
                            throw (
                                'Native child process tree did not close during ' +
                                'final ownership cleanup.')
                        }
                    }
                } finally {
                    $suspendedProcess.Dispose()
                    $suspendedProcess = $null
                }
            } elseif ($processStarted -and $null -ne $process -and
                    -not $process.HasExited) {
                $cleanupProcessId = $process.Id
                $process.Kill()
                if (-not $process.WaitForExit(5000)) {
                    throw (
                        "Ordinary child PID $cleanupProcessId did not close " +
                        'during final ownership cleanup.')
                }
            }
        } finally {
            if ($null -ne $process) {
                $process.Dispose()
                $process = $null
            }
        }
    }
}

function Invoke-ContainedGodotCommand {
    param(
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $GodotExecutable,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [int] $ChildTimeoutSeconds = $TimeoutSeconds,
        [string] $WorkingDirectory = $ProjectPath,
        [hashtable] $Environment = @{}
    )

    $windowHost = $null
    try {
        if ($env:OS -eq 'Windows_NT') {
            $windowHost = New-HiddenWindowHost -RequireRenderWindow $false
        }
        $safeNativeLabel = ($Label -replace '[^A-Za-z0-9_.-]', '-')
        $nativeUserDataRoot = Join-Path $RunArtifactDirectory (
            'native-user-data\' + $safeNativeLabel)
        New-Item -ItemType Directory -Force -Path $nativeUserDataRoot | Out-Null
        $nativeEnvironment = @{
            'APPDATA' = $nativeUserDataRoot
            'LOCALAPPDATA' = $nativeUserDataRoot
            'XDG_DATA_HOME' = $nativeUserDataRoot
            'TRAWF_TEST_PROCESS_CONTAINMENT_MODE' = if ($null -ne $windowHost) {
                'private_never_input_desktop_job_v1'
            } else {
                'process_tree_v1'
            }
        }
        foreach ($environmentName in $Environment.Keys) {
            if ($nativeEnvironment.ContainsKey($environmentName)) {
                throw "Contained Godot environment may not override '$environmentName'."
            }
            $nativeEnvironment[$environmentName] = $Environment[$environmentName]
        }
        return Invoke-GateChild -Label $Label -FilePath $GodotExecutable `
            -Arguments $Arguments -ChildTimeoutSeconds $ChildTimeoutSeconds `
            -WorkingDirectory $WorkingDirectory -Environment $nativeEnvironment `
            -WindowIsolation $windowHost
    } finally {
        Remove-HiddenWindowHost -WindowHost $windowHost
    }
}

function Invoke-NativeGodotTest {
    param(
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $GodotExecutable,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Headless', 'Windowed')]
        [string] $LaunchMode,
        [string] $EntryPoint = 'res://scenes/system/test_bootstrap.tscn',
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]] $TestArguments,
        [int] $ChildTimeoutSeconds = $TimeoutSeconds
    )

    $nativeGodotExecutable = if ($LaunchMode -eq 'Windowed') {
        Resolve-WindowedGodotExecutable -GodotExecutable $GodotExecutable
    } else {
        $GodotExecutable
    }
    $windowHost = $null
    $offscreenPosition = $script:WindowedOffscreenPosition
    try {
        # Acquisition belongs inside the cleanup scope. New-HiddenWindowHost is
        # itself exception-safe, and any successfully returned session is
        # disposed by this finally block on every later failure.
        if ($env:OS -eq 'Windows_NT') {
            # Headless is an engine mode, not a Win32 guarantee. A parser or
            # renderer alert can still create an HWND, so every Windows Godot
            # process is born suspended on the private never-input desktop and
            # placed into the exact kill-on-close Job before first instruction.
            $windowHost = New-HiddenWindowHost `
                -RequireRenderWindow ($LaunchMode -eq 'Windowed')
            $offscreenPosition = $windowHost.OffscreenPosition
        }
        $embeddedWindowId = if ($null -ne $windowHost -and
                $LaunchMode -eq 'Windowed') {
            $windowHost.Id
        } else {
            ''
        }
        $nativeTestArguments = Get-NativeGodotArguments -LaunchMode $LaunchMode `
            -EntryPoint $EntryPoint -TestArguments $TestArguments `
            -EmbeddedWindowId $embeddedWindowId -OffscreenPosition $offscreenPosition

    # Every required native invocation gets a clean, artifact-owned user://
    # root. Persona traces and settings from an earlier workstation run must not
    # satisfy a later gate, and the evidence files must travel with the logs.
    $safeNativeLabel = ($Label -replace '[^A-Za-z0-9_.-]', '-')
    $nativeUserDataRoot = Join-Path $RunArtifactDirectory (
        'native-user-data\' + $safeNativeLabel)
    New-Item -ItemType Directory -Force -Path $nativeUserDataRoot | Out-Null
    $nativeEnvironment = @{
        'APPDATA' = $nativeUserDataRoot
        'LOCALAPPDATA' = $nativeUserDataRoot
        'XDG_DATA_HOME' = $nativeUserDataRoot
        'TRAWF_TEST_PROCESS_CONTAINMENT_MODE' = if ($null -ne $windowHost) {
            'private_never_input_desktop_job_v1'
        } else {
            'process_tree_v1'
        }
    }
    if ($LaunchMode -eq 'Windowed') {
        $nativeEnvironment['TRAWF_TEST_WINDOWED_OFFSCREEN'] =
            $offscreenPosition
        $nativeEnvironment['TRAWF_TEST_POINTER_INPUT_MODE'] = 'app_local_events_v1'
        if ($null -ne $windowHost) {
            $nativeEnvironment['TRAWF_TEST_WINDOW_HOST_MODE'] = 'hidden_parent_v1'
            $nativeEnvironment['TRAWF_TEST_WINDOW_PARENT_ID'] = $windowHost.Id
        } else {
            $nativeEnvironment['TRAWF_TEST_WINDOW_HOST_MODE'] = 'offscreen_geometry_v1'
        }
    }

        return Invoke-GateChild -Label $Label -FilePath $nativeGodotExecutable `
            -Arguments $nativeTestArguments -ChildTimeoutSeconds $ChildTimeoutSeconds `
            -Environment $nativeEnvironment -WindowIsolation $windowHost
    } finally {
        Remove-HiddenWindowHost -WindowHost $windowHost
    }
}

function Complete-RequiredInvocation {
    param([Parameter(Mandatory = $true)] $Result)

    if ($Result.ExitCode -ne 0) {
        Write-GateError "Required invocation '$($Result.Label)' failed with exit code $($Result.ExitCode)."
        exit $Result.ExitCode
    }

    # Godot can report script/parser/runtime faults on stderr while returning 0.
    # These are never an acceptable required-test result; without this check a
    # broken assertion helper can print PASS and still poison the engine log.
    $severeRuntimeErrors = [regex]::Matches(
        $Result.Output,
        '(?im)^(?:SCRIPT ERROR:|ERROR:\s+(?:Failed to load script|Failed to create an autoload|String formatting error))'
    )
    if ($severeRuntimeErrors.Count -gt 0) {
        $severeLines = @($Result.Output -split "`r?`n" | Where-Object {
            $_ -match '^(?:SCRIPT ERROR:|ERROR:\s+(?:Failed to load script|Failed to create an autoload|String formatting error))'
        })
        Write-GateError ("Required invocation '$($Result.Label)' emitted a script/runtime fault:`n" + ($severeLines -join "`n"))
        exit 88
    }

    $skipMatches = [regex]::Matches($Result.Output, '(?im)^\s*SKIP\b')
    if ($skipMatches.Count -gt 0) {
        $skipLines = @($Result.Output -split "`r?`n" | Where-Object { $_ -match '^\s*SKIP\b' })
        Write-GateError ("Required invocation '$($Result.Label)' reported a skip:`n" + ($skipLines -join "`n"))
        exit 86
    }
    Write-Host "[GATE] PASS: $($Result.Label)"
}

function Resolve-PowerShellExecutable {
    try {
        $current = (Get-Process -Id $PID).Path
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            return $current
        }
    } catch {
        # Fall through to command discovery.
    }
    return Resolve-Executable -Kind 'PowerShell' -Candidates @('pwsh', 'powershell')
}

function Resolve-NpmExecutable {
    return Resolve-Executable -Kind 'npm' -Candidates @(
        $env:NPM_BIN
        'npm.cmd'
        'npm'
    )
}

function Resolve-NpxExecutable {
    return Resolve-Executable -Kind 'npx' -Candidates @(
        $env:NPX_BIN
        'npx.cmd'
        'npx'
    )
}

function Get-AvailableTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

function Invoke-CrossPlatformPersonaAggregation {
    param(
        [Parameter(Mandatory = $true)][string] $GodotExecutable,
        [Parameter(Mandatory = $true)][string] $NodeExecutable
    )

    # The two platform gates first seal isolated, platform-owned cohorts. This
    # final release leg consumes those manifests and distills their exact eight
    # primary traces together, so same-node Native/Web policy conflicts cannot
    # hide behind two individually green previews.
    $reporterPath = Join-Path $ProjectPath 'tests/web/persona-validation-reporter.mjs'
    $nativeUserDataRoot = Join-Path $RunArtifactDirectory 'native-user-data\windowed-persona-probe'
    $nativeManifestPath = Join-Path $RunArtifactDirectory 'native-persona-trace-manifest.json'
    $webManifestPath = Join-Path $RunArtifactDirectory 'playwright\persona-trace-manifest.json'
    $combinedPreviewPath = Join-Path $RunArtifactDirectory 'persona-decision-library.combined.preview.json'
    $combinedReportPath = Join-Path $RunArtifactDirectory 'persona-cross-platform-validation.json'

    $nativeManifestResult = Invoke-GateChild -Label 'persona-native-artifact-manifest' `
        -FilePath $NodeExecutable -Arguments @(
            $reporterPath,
            '--build-native-manifest',
            $nativeUserDataRoot,
            $nativeManifestPath
        ) -WorkingDirectory $ProjectPath -ChildTimeoutSeconds 120
    Complete-RequiredInvocation $nativeManifestResult

    foreach ($manifestPath in @($nativeManifestPath, $webManifestPath)) {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Write-GateError "Required persona artifact manifest is missing: $manifestPath"
            exit 89
        }
    }
    try {
        $nativeArtifactManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
        $webArtifactManifest = Get-Content -LiteralPath $webManifestPath -Raw | ConvertFrom-Json
        $nativePrimaryTraces = @($nativeArtifactManifest.traces)
        $webPrimaryTraces = @($webArtifactManifest.traces)
    } catch {
        Write-GateError "Could not consume persona artifact manifests: $_"
        exit 89
    }
    if ($nativePrimaryTraces.Count -ne 4 -or $webPrimaryTraces.Count -ne 4) {
        Write-GateError ("Cross-platform persona aggregation requires exactly 4 Native + 4 Web " +
            "primary traces; observed $($nativePrimaryTraces.Count) + $($webPrimaryTraces.Count).")
        exit 89
    }
    $combinedTraceEntries = @($nativePrimaryTraces + $webPrimaryTraces) | Sort-Object `
        execution_platform, persona, repeat_index
    $combinedTracePaths = @($combinedTraceEntries | ForEach-Object { [string] $_.path })
    if ($combinedTracePaths.Count -ne 8 -or @($combinedTracePaths | Select-Object -Unique).Count -ne 8 `
            -or @($combinedTracePaths | Where-Object {
                [string]::IsNullOrWhiteSpace($_) -or
                -not (Test-Path -LiteralPath $_ -PathType Leaf)
            }).Count -ne 0) {
        Write-GateError 'Persona artifact manifests do not resolve to exactly eight unique primary trace files.'
        exit 89
    }

    $distillationArguments = @(
        '--headless', '--path', $ProjectPath,
        '--script', 'res://tools/distill_persona_decision_library.gd', '--'
    )
    foreach ($tracePath in $combinedTracePaths) {
        $distillationArguments += "--trace=$($tracePath.Replace('\', '/'))"
    }
    # The release gate owns this prospective preview. It never mutates the
    # canonical learned library; promotion remains an explicit later workflow.
    $distillationArguments += "--output=$($combinedPreviewPath.Replace('\', '/'))"
    $combinedDistillationResult = Invoke-ContainedGodotCommand `
        -Label 'persona-cross-platform-distillation-preview' `
        -GodotExecutable $GodotExecutable -Arguments $distillationArguments `
        -WorkingDirectory $ProjectPath -ChildTimeoutSeconds 240
    Complete-RequiredInvocation $combinedDistillationResult

    $combinedValidationResult = Invoke-GateChild `
        -Label 'persona-cross-platform-validation' `
        -FilePath $NodeExecutable -Arguments @(
            $reporterPath,
            '--validate-combined',
            $nativeManifestPath,
            $webManifestPath,
            $combinedPreviewPath,
            $combinedReportPath
        ) -WorkingDirectory $ProjectPath -ChildTimeoutSeconds 120
    Complete-RequiredInvocation $combinedValidationResult
    Write-Host "[GATE] PASS: combined Native+Web persona preview uses exactly 8 primary traces."
}

# Internal leg used by -SelfTest. It deliberately routes a non-zero synthetic
# process through Invoke-GateChild, then exits with that exact code.
if ($SyntheticChildExitCode -ge 0) {
    $shell = Resolve-PowerShellExecutable
    $synthetic = Invoke-GateChild -Label 'synthetic-child' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-Command', "exit $SyntheticChildExitCode"
    ) -ChildTimeoutSeconds 30
    exit $synthetic.ExitCode
}

if ($SyntheticSkip) {
    $shell = Resolve-PowerShellExecutable
    $skipProbeResult = Invoke-GateChild -Label 'synthetic-required-skip' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-Command', "Write-Output 'SKIP: synthetic required check'; exit 0"
    ) -ChildTimeoutSeconds 30
    Complete-RequiredInvocation $skipProbeResult
    Write-GateError 'Synthetic skip unexpectedly passed the required-invocation check.'
    exit 1
}

if ($SyntheticHang) {
    Start-Sleep -Seconds 60
    Write-GateError 'Synthetic hang unexpectedly survived its parent timeout.'
    exit 1
}

if ($SyntheticRuntimeError) {
    $shell = Resolve-PowerShellExecutable
    $runtimeErrorProbe = Invoke-GateChild -Label 'synthetic-runtime-error' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-Command',
        "[Console]::Error.WriteLine('SCRIPT ERROR: synthetic zero-exit fault'); exit 0"
    ) -ChildTimeoutSeconds 30
    Complete-RequiredInvocation $runtimeErrorProbe
    Write-GateError 'Synthetic runtime error unexpectedly passed the required-invocation check.'
    exit 1
}

if ($SelfTest) {
    $shell = Resolve-PowerShellExecutable
    $expected = 37
    $selfTestArtifacts = Join-Path $RunArtifactDirectory 'nested-self-test'
    $nested = Invoke-GateChild -Label 'exit-propagation-self-test' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-SyntheticChildExitCode', $expected,
        '-ArtifactDirectory', $selfTestArtifacts
    ) -ChildTimeoutSeconds 60
    if ($nested.ExitCode -ne $expected) {
        Write-GateError "Exit propagation self-test failed: expected $expected, observed $($nested.ExitCode)."
        exit 1
    }
    $skipExpected = 86
    $skipNested = Invoke-GateChild -Label 'required-skip-self-test' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-SyntheticSkip',
        '-ArtifactDirectory', $selfTestArtifacts
    ) -ChildTimeoutSeconds 60 -EchoOutput $false
    if ($skipNested.ExitCode -ne $skipExpected) {
        Write-GateError "Required-skip self-test failed: expected $skipExpected, observed $($skipNested.ExitCode)."
        exit 1
    }
    $timeoutExpected = 124
    $timeoutNested = Invoke-GateChild -Label 'timeout-self-test' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-SyntheticHang',
        '-ArtifactDirectory', $selfTestArtifacts
    ) -ChildTimeoutSeconds 1 -EchoOutput $false
    if ($timeoutNested.ExitCode -ne $timeoutExpected -or -not $timeoutNested.TimedOut) {
        Write-GateError "Timeout self-test failed: expected exit $timeoutExpected with TimedOut=true; observed exit $($timeoutNested.ExitCode), TimedOut=$($timeoutNested.TimedOut)."
        exit 1
    }
    $runtimeErrorExpected = 88
    $runtimeErrorNested = Invoke-GateChild -Label 'runtime-error-self-test' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-SyntheticRuntimeError',
        '-ArtifactDirectory', $selfTestArtifacts
    ) -ChildTimeoutSeconds 60 -EchoOutput $false
    if ($runtimeErrorNested.ExitCode -ne $runtimeErrorExpected) {
        Write-GateError "Runtime-error self-test failed: expected $runtimeErrorExpected, observed $($runtimeErrorNested.ExitCode)."
        exit 1
    }

    foreach ($validFocusedFlag in @(
        '--test-all',
        '--test-agent-player-input-boundary',
        '--test-basin-fill-proof-2'
    )) {
        if (-not (Test-FocusedTestFlag -Value $validFocusedFlag)) {
            Write-GateError "Focused test flag validator rejected '$validFocusedFlag'."
            exit 1
        }
    }
    foreach ($invalidFocusedFlag in @(
        '', '--test', '--test-Upper', '--test-has_underscore',
        '--test-two --fail-on-skip', '--test-two=payload',
        'res://tools/test.gd', '--headless'
    )) {
        if (Test-FocusedTestFlag -Value $invalidFocusedFlag) {
            Write-GateError "Focused test flag validator accepted '$invalidFocusedFlag'."
            exit 1
        }
    }
    $focusedValidationExpected = 64
    $focusedValidationNested = Invoke-GateChild `
        -Label 'focused-headless-argument-rejection-self-test' `
        -FilePath $shell -Arguments @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath,
            '-FocusedHeadlessTest', '--test-Upper',
            '-ArtifactDirectory', $selfTestArtifacts
        ) -ChildTimeoutSeconds 60 -EchoOutput $false
    if ($focusedValidationNested.ExitCode -ne $focusedValidationExpected -or
            $focusedValidationNested.Output -notmatch
                'must be exactly one lowercase --test-\[a-z0-9-\]\+ token') {
        Write-GateError (
            'Focused Headless argument-rejection self-test failed: expected ' +
            "exit $focusedValidationExpected, observed " +
            "$($focusedValidationNested.ExitCode).")
        exit 1
    }
    $focusedWindowedValidationNested = Invoke-GateChild `
        -Label 'focused-windowed-argument-rejection-self-test' `
        -FilePath $shell -Arguments @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath,
            '-FocusedWindowedTest', '--test-Upper',
            '-ArtifactDirectory', $selfTestArtifacts
        ) -ChildTimeoutSeconds 60 -EchoOutput $false
    if ($focusedWindowedValidationNested.ExitCode -ne $focusedValidationExpected -or
            $focusedWindowedValidationNested.Output -notmatch
                'must be exactly one lowercase --test-\[a-z0-9-\]\+ token') {
        Write-GateError (
            'Focused Windowed argument rejection self-test expected exit ' +
            "$focusedValidationExpected and the strict grammar diagnostic; " +
            "observed exit=$($focusedWindowedValidationNested.ExitCode).")
        exit 1
    }
    $focusedMutualExclusionNested = Invoke-GateChild `
        -Label 'focused-runtime-mutual-exclusion-self-test' `
        -FilePath $shell -Arguments @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', $PSCommandPath,
            '-FocusedHeadlessTest', '--test-all',
            '-FocusedWindowedTest', '--test-all',
            '-ArtifactDirectory', $selfTestArtifacts
        ) -ChildTimeoutSeconds 60 -EchoOutput $false
    if ($focusedMutualExclusionNested.ExitCode -ne $focusedValidationExpected -or
            $focusedMutualExclusionNested.Output -notmatch
                'another focused runtime') {
        Write-GateError (
            'Focused runtime mutual-exclusion self-test expected exit ' +
            "$focusedValidationExpected and the exclusivity diagnostic; " +
            "observed exit=$($focusedMutualExclusionNested.ExitCode).")
        exit 1
    }

    $distillationRequestProbeRoot = Join-Path $RunArtifactDirectory `
        'persona-distillation-request-self-test'
    New-Item -ItemType Directory -Force `
        -Path $distillationRequestProbeRoot | Out-Null
    $distillationTraceProbes = @()
    foreach ($traceProbeIndex in 0..3) {
        $traceProbePath = Join-Path $distillationRequestProbeRoot `
            "trace-$traceProbeIndex.jsonl"
        [System.IO.File]::WriteAllText(
            $traceProbePath, "{}`n", [System.Text.Encoding]::UTF8)
        $distillationTraceProbes += $traceProbePath
    }
    $distillationOutputProbe = Join-Path $distillationRequestProbeRoot `
        'preview.json'
    $distillationRequestProbePath = Join-Path $distillationRequestProbeRoot `
        'request.json'
    [System.IO.File]::WriteAllText(
        $distillationRequestProbePath,
        ([ordered] @{
            schema = 'persona_distillation_request_v1'
            traces = $distillationTraceProbes
            output = $distillationOutputProbe
        } | ConvertTo-Json -Depth 4),
        [System.Text.Encoding]::UTF8)
    try {
        $distillationRequestProbe = Read-PersonaDistillationRequest `
            -RequestPath $distillationRequestProbePath
    } catch {
        Write-GateError (
            'Valid contained persona-distillation request was rejected: ' +
            $_.Exception.Message)
        exit 1
    }
    if ($distillationRequestProbe.TracePaths.Count -ne 4 -or
            $distillationRequestProbe.OutputPath -cne
                [System.IO.Path]::GetFullPath($distillationOutputProbe)) {
        Write-GateError (
            'Contained persona-distillation request did not preserve its ' +
            'exact four traces and output path.')
        exit 1
    }
    $malformedDistillationRequestPath = Join-Path `
        $distillationRequestProbeRoot 'malformed-request.json'
    [System.IO.File]::WriteAllText(
        $malformedDistillationRequestPath,
        ([ordered] @{
            schema = 'persona_distillation_request_v1'
            traces = $distillationTraceProbes
            output = $distillationOutputProbe
            raw_arguments = @('--script', 'res://unreviewed.gd')
        } | ConvertTo-Json -Depth 4),
        [System.Text.Encoding]::UTF8)
    $malformedDistillationRejected = $false
    try {
        [void] (Read-PersonaDistillationRequest `
            -RequestPath $malformedDistillationRequestPath)
    } catch {
        $malformedDistillationRejected = $true
    }
    if (-not $malformedDistillationRejected) {
        Write-GateError (
            'Contained persona-distillation request accepted an unreviewed ' +
            'raw Godot argument payload.')
        exit 1
    }

    $environmentProbeResult = Invoke-GateChild -Label 'child-environment-self-test' -FilePath $shell -Arguments @(
        '-NoProfile', '-NonInteractive', '-Command',
        'if ($env:TRAWF_GATE_ENV_PROBE -cne "visible") { exit 41 }; exit 0'
    ) -Environment @{ 'TRAWF_GATE_ENV_PROBE' = 'visible' } -ChildTimeoutSeconds 30 -EchoOutput $false
    if ($environmentProbeResult.ExitCode -ne 0) {
        Write-GateError ("Child-environment self-test failed: expected exit 0, observed {0}." -f
            $environmentProbeResult.ExitCode)
        exit 1
    }

    if ($env:OS -eq 'Windows_NT') {
        $windowedExecutableProbeDirectory = Join-Path $RunArtifactDirectory `
            'windowed-executable-resolution-self-test'
        [System.IO.Directory]::CreateDirectory($windowedExecutableProbeDirectory) | Out-Null
        $consoleWrapperProbe = Join-Path $windowedExecutableProbeDirectory `
            'Godot_v4.7-stable_win64_console.exe'
        $guiEngineProbe = Join-Path $windowedExecutableProbeDirectory `
            'Godot_v4.7-stable_win64.exe'
        [System.IO.File]::WriteAllBytes($consoleWrapperProbe, [byte[]] @(0))
        [System.IO.File]::WriteAllBytes($guiEngineProbe, [byte[]] @(0))
        $resolvedWindowedProbe = Resolve-WindowedGodotExecutable `
            -GodotExecutable $consoleWrapperProbe
        if ($resolvedWindowedProbe -cne [System.IO.Path]::GetFullPath($guiEngineProbe)) {
            Write-GateError ("Windowed executable self-test expected the GUI engine {0}; observed {1}." -f
                $guiEngineProbe, $resolvedWindowedProbe)
            exit 1
        }
    }

    $selfTestWindowHost = New-HiddenWindowHost
    try {
        $selfTestEmbeddedWindowId = if ($null -eq $selfTestWindowHost) {
            ''
        } else {
            $selfTestWindowHost.Id
        }
        $selfTestOffscreenPosition = if ($null -eq $selfTestWindowHost) {
            $script:WindowedOffscreenPosition
        } else {
            $selfTestWindowHost.OffscreenPosition
        }
        $windowedArgumentProbe = @(Get-NativeGodotArguments -LaunchMode 'Windowed' `
            -EntryPoint 'res://scenes/system/test_bootstrap.tscn' `
            -TestArguments @('--test-player-contract', '--fail-on-skip') `
            -EmbeddedWindowId $selfTestEmbeddedWindowId `
            -OffscreenPosition $selfTestOffscreenPosition)
        $expectedWindowedArguments = @('--path', $ProjectPath)
        if ($null -ne $selfTestWindowHost) {
            $expectedWindowedArguments += @('--wid', $selfTestWindowHost.Id)
        }
        $expectedWindowedArguments += @(
            '--windowed',
            '--position', $selfTestOffscreenPosition,
            '--single-window',
            '--rendering-method', 'gl_compatibility',
            '--audio-driver', 'Dummy',
            'res://scenes/system/test_bootstrap.tscn', '--',
            '--test-player-contract', '--fail-on-skip'
        )
        if (($windowedArgumentProbe -join "`0") -cne ($expectedWindowedArguments -join "`0")) {
            Write-GateError ("Windowed launch self-test expected hidden-parent/offscreen arguments [{0}]; observed [{1}]." -f
                ($expectedWindowedArguments -join ', '), ($windowedArgumentProbe -join ', '))
            exit 1
        }
        if ($null -ne $selfTestWindowHost) {
            $hostProbe = [TrawfTestGate.HiddenWindowHost]::Inspect(
                $selfTestWindowHost.DesktopHandle,
                $selfTestWindowHost.DesktopName,
                $selfTestWindowHost.Handle, $PID)
            if (-not $hostProbe.PrivateDesktopExists -or
                    -not $hostProbe.PrivateDesktopNameMatches -or
                    $hostProbe.PrivateDesktopIsInput -or
                    -not $hostProbe.ParentEnumeratedOnPrivateDesktop -or
                    -not $hostProbe.ParentThreadUsesPrivateDesktop -or
                    -not $hostProbe.ParentExists -or $hostProbe.ParentVisible -or
                    -not $hostProbe.ParentHasPopupStyle -or
                    -not $hostProbe.ParentHasToolWindowStyle -or
                    -not $hostProbe.ParentHasNoActivateStyle -or
                    $hostProbe.ParentHasVisibleStyle -or
                    $hostProbe.ParentHasAppWindowStyle -or
                    -not $hostProbe.ParentOutsideVirtualDesktop -or
                    $hostProbe.ParentForeground -or
                    -not $selfTestWindowHost.Session.PumpThreadAlive -or
                    $selfTestWindowHost.PumpThreadId -eq 0 -or
                    $selfTestWindowHost.PumpThreadId -eq
                        $selfTestWindowHost.CreatorThreadId -or
                    -not [TrawfTestGate.HiddenWindowHost]::IntersectionSemanticsPassSelfTest()) {
                Write-GateError "Hidden-parent host self-test failed: $($hostProbe.Summary)"
                exit 1
            }
            $immediateShowFixturePath = Join-Path $RunArtifactDirectory `
                'window-isolation-immediate-show-fixture.exe'
            $immediateShowFixtureSource = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class TrawfImmediateShowFixture
{
    private const uint STARTF_USESHOWWINDOW = 0x00000001;
    private const uint STARTF_USESTDHANDLES = 0x00000100;
    private const short SW_HIDE = 0;
    private const uint WS_POPUP = 0x80000000;
    private const uint WS_DISABLED = 0x08000000;
    private const uint WS_EX_APPWINDOW = 0x00040000;
    private const int SW_SHOW = 5;
    private const int GWLP_HWNDPARENT = -8;
    private const uint PM_REMOVE = 0x0001;
    private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    private const uint CREATE_NO_WINDOW = 0x08000000;
    private const uint DESKTOP_READOBJECTS = 0x0001;
    private const uint DESKTOP_CREATEWINDOW = 0x0002;
    private const int STD_INPUT_HANDLE = -10;
    private const int STD_OUTPUT_HANDLE = -11;
    private const int STD_ERROR_HANDLE = -12;

    private delegate IntPtr WindowProcedure(
        IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASS
    {
        public uint Style;
        public WindowProcedure WindowProc;
        public int ClassExtra;
        public int WindowExtra;
        public IntPtr Instance;
        public IntPtr Icon;
        public IntPtr Cursor;
        public IntPtr Background;
        public string MenuName;
        public string ClassName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr Hwnd;
        public uint Message;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public POINT Point;
        public uint Private;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct STARTUPINFO
    {
        public int Size;
        public IntPtr Reserved;
        public IntPtr Desktop;
        public IntPtr Title;
        public uint X;
        public uint Y;
        public uint XSize;
        public uint YSize;
        public uint XCountChars;
        public uint YCountChars;
        public uint FillAttribute;
        public uint Flags;
        public short ShowWindow;
        public short Reserved2Size;
        public IntPtr Reserved2;
        public IntPtr StdIn;
        public IntPtr StdOut;
        public IntPtr StdErr;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_INFORMATION
    {
        public IntPtr Process;
        public IntPtr Thread;
        public uint ProcessId;
        public uint ThreadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandleW(string moduleName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern void GetStartupInfoW(ref STARTUPINFO startupInfo);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int standardHandle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(
        string applicationName, StringBuilder commandLine,
        IntPtr processAttributes, IntPtr threadAttributes,
        bool inheritHandles, uint creationFlags, IntPtr environment,
        string currentDirectory, ref STARTUPINFO startupInfo,
        out PROCESS_INFORMATION processInformation);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern ushort RegisterClassW(ref WNDCLASS windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(
        uint extendedStyle, string className, string title, uint style,
        int x, int y, int width, int height, IntPtr owner, IntPtr menu,
        IntPtr instance, IntPtr parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr OpenDesktopW(
        string desktopName, uint flags, bool inherit, uint desiredAccess);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetThreadDesktop(IntPtr desktop);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProcW(
        IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindowEnabled(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetParent(IntPtr hwnd);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtrW(
        IntPtr hwnd, int index, IntPtr newValue);

    [DllImport("imm32.dll")]
    private static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool SetWindowTextW(IntPtr hwnd, string title);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern bool PeekMessageW(
        out MSG message, IntPtr hwnd, uint minimum, uint maximum,
        uint removeMessage);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref MSG message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessageW(ref MSG message);

    private static readonly WindowProcedure Procedure = DefWindowProcW;

    private static bool SpawnLogDescendant(bool hang)
    {
        string executable = Process.GetCurrentProcess().MainModule.FileName;
        STARTUPINFO startupInfo = new STARTUPINFO();
        startupInfo.Size = Marshal.SizeOf(typeof(STARTUPINFO));
        startupInfo.Flags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
        startupInfo.ShowWindow = SW_HIDE;
        startupInfo.StdIn = GetStdHandle(STD_INPUT_HANDLE);
        startupInfo.StdOut = GetStdHandle(STD_OUTPUT_HANDLE);
        startupInfo.StdErr = GetStdHandle(STD_ERROR_HANDLE);
        StringBuilder commandLine = new StringBuilder(
            "\"" + executable + "\" " +
            (hang ? "--hanging-descendant" : "--descendant"));
        PROCESS_INFORMATION processInformation;
        if (!CreateProcessW(
                executable, commandLine, IntPtr.Zero, IntPtr.Zero, true,
                CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                IntPtr.Zero, null, ref startupInfo,
                out processInformation))
        {
            return false;
        }
        Console.WriteLine((hang
            ? "hanging_descendant_spawned_pid="
            : "descendant_spawned_pid=") + processInformation.ProcessId);
        Console.Out.Flush();
        CloseHandle(processInformation.Thread);
        CloseHandle(processInformation.Process);
        return true;
    }

    private static bool SpawnHiddenInputDesktopEscape(
        string inputDesktopName)
    {
        ManualResetEvent ready = new ManualResetEvent(false);
        IntPtr escapeWindow = IntPtr.Zero;
        int escapeError = 0;
        Thread escapeThread = new Thread(delegate()
        {
            IntPtr inputDesktop = OpenDesktopW(
                inputDesktopName, 0, false,
                DESKTOP_READOBJECTS | DESKTOP_CREATEWINDOW);
            if (inputDesktop == IntPtr.Zero)
            {
                escapeError = Marshal.GetLastWin32Error();
                ready.Set();
                return;
            }
            if (!SetThreadDesktop(inputDesktop))
            {
                escapeError = Marshal.GetLastWin32Error();
                CloseDesktop(inputDesktop);
                ready.Set();
                return;
            }
            // Positive area makes this an unsafe escape under the release
            // contract, but omitting WS_VISIBLE and never calling ShowWindow
            // guarantees that the adversarial fixture itself paints no pixel.
            escapeWindow = CreateWindowExW(
                0, "STATIC", "TRAWF hidden input-desktop escape fixture",
                WS_POPUP, 8, 8, 96, 64,
                IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (escapeWindow == IntPtr.Zero)
            {
                escapeError = Marshal.GetLastWin32Error();
                CloseDesktop(inputDesktop);
                ready.Set();
                return;
            }
            Console.WriteLine(
                "hidden_input_escape_created=True hwnd=" +
                escapeWindow.ToInt64() + " visible=" +
                IsWindowVisible(escapeWindow) + " pid=" +
                Process.GetCurrentProcess().Id);
            Console.Out.Flush();
            ready.Set();
            while (true)
            {
                MSG message;
                while (PeekMessageW(
                        out message, IntPtr.Zero, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(ref message);
                    DispatchMessageW(ref message);
                }
                Thread.Sleep(1);
            }
        });
        escapeThread.IsBackground = true;
        escapeThread.Name = "TRAWF hidden input-desktop escape fixture";
        escapeThread.Start();
        if (!ready.WaitOne(3000))
        {
            return false;
        }
        if (escapeWindow == IntPtr.Zero)
        {
            Console.WriteLine("hidden_input_escape_error=" + escapeError);
            Console.Out.Flush();
            return false;
        }
        return true;
    }

    public static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--descendant")
        {
            Thread.Sleep(350);
            Console.WriteLine("descendant_log_final=True");
            Console.Out.Flush();
            return 0;
        }
        if (args.Length == 1 && args[0] == "--hanging-descendant")
        {
            Thread.Sleep(60000);
            return 77;
        }
        STARTUPINFO startupInfo = new STARTUPINFO();
        startupInfo.Size = Marshal.SizeOf(typeof(STARTUPINFO));
        GetStartupInfoW(ref startupInfo);
        bool startupHidden =
            (startupInfo.Flags & STARTF_USESHOWWINDOW) != 0 &&
            startupInfo.ShowWindow == SW_HIDE;
        Console.WriteLine("startup_show_hidden=" + startupHidden);
        Console.Out.Flush();
        if (!startupHidden)
        {
            return 75;
        }
        if (args.Length != 5)
        {
            return 70;
        }
        IntPtr owner = new IntPtr(long.Parse(args[0]));
        int x = int.Parse(args[1]);
        int y = int.Parse(args[2]);
        int lane = int.Parse(args[3]);
        string inputDesktopName = args[4];
        IntPtr instance = GetModuleHandleW(null);
        WNDCLASS windowClass = new WNDCLASS();
        windowClass.WindowProc = Procedure;
        windowClass.Instance = instance;
        windowClass.ClassName = "Engine";
        if (RegisterClassW(ref windowClass) == 0)
        {
            return 71;
        }
        bool headlessAlert = lane == 7;
        IntPtr hwnd = CreateWindowExW(
            headlessAlert ? WS_EX_APPWINDOW : 0,
            "Engine",
            headlessAlert ? "ALERT: headless fixture" : "",
            WS_POPUP,
            x, y, 320, 180,
            headlessAlert ? IntPtr.Zero : owner,
            IntPtr.Zero, instance, IntPtr.Zero);
        if (hwnd == IntPtr.Zero)
        {
            return 72;
        }
        ShowWindow(hwnd, SW_SHOW);
        bool firstShowVisible = IsWindowVisible(hwnd);
        Console.WriteLine("first_show_visible=" + firstShowVisible);
        Console.Out.Flush();
        if (headlessAlert)
        {
            Console.WriteLine(
                "headless_alert_private_desktop=True pid=" +
                Process.GetCurrentProcess().Id);
            Console.Out.Flush();
            while (true)
            {
                MSG alertMessage;
                while (PeekMessageW(
                        out alertMessage, IntPtr.Zero, 0, 0, PM_REMOVE))
                {
                    TranslateMessage(ref alertMessage);
                    DispatchMessageW(ref alertMessage);
                }
                Thread.Sleep(1);
            }
        }
        SetWindowTextW(hwnd, "TRAWF Immediate Show Fixture");
        Stopwatch timer = Stopwatch.StartNew();
        while (timer.ElapsedMilliseconds < 10000)
        {
            MSG message;
            while (PeekMessageW(
                    out message, IntPtr.Zero, 0, 0, PM_REMOVE))
            {
                TranslateMessage(ref message);
                DispatchMessageW(ref message);
            }
            if (IsWindowVisible(hwnd) && !IsWindowEnabled(hwnd) &&
                    GetParent(hwnd) == owner)
            {
                Console.WriteLine("private_desktop_contained=True");
                Console.Out.Flush();
                if (lane == 1 && !SpawnLogDescendant(false))
                {
                    DestroyWindow(hwnd);
                    return 76;
                }
                if (lane == 2)
                {
                    // Keep the real Engine + Default IME relationship alive
                    // across multiple 25 ms samples while the launcher has
                    // deliberately suppressed its earlier IME-binding pass.
                    Stopwatch imeBindingTimer = Stopwatch.StartNew();
                    while (imeBindingTimer.ElapsedMilliseconds < 100)
                    {
                        MSG imeBindingMessage;
                        while (PeekMessageW(
                                out imeBindingMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref imeBindingMessage);
                            DispatchMessageW(ref imeBindingMessage);
                        }
                        if (!IsWindowVisible(hwnd) || IsWindowEnabled(hwnd) ||
                                GetParent(hwnd) != owner)
                        {
                            DestroyWindow(hwnd);
                            return 83;
                        }
                        Thread.Sleep(1);
                    }
                    Console.WriteLine("current_owner_ime_fixture_held=True");
                    Console.Out.Flush();
                }
                if (lane == 3)
                {
                    if (!SpawnLogDescendant(true))
                    {
                        DestroyWindow(hwnd);
                        return 78;
                    }
                    Console.WriteLine("root_hang_started=True");
                    Console.Out.Flush();
                    while (true)
                    {
                        Thread.Sleep(1000);
                    }
                }
                if (lane == 4)
                {
                    Console.WriteLine(
                        "nonzero_root_pid=" +
                        Process.GetCurrentProcess().Id);
                    Console.Out.Flush();
                    DestroyWindow(hwnd);
                    return 37;
                }
                if (lane == 9 || lane == 10)
                {
                    // DisableWindowInput can win the race while STARTUPINFO
                    // still keeps this HWND hidden. The fixture may then flash
                    // visible and hide again before the monitor has persisted
                    // its first visible-style receipt; in that ordering the
                    // launcher correctly treats it as an initially hidden
                    // render surface and reveals it. Hold a continuously
                    // visible, disabled surface across several 25 ms monitor
                    // samples so lanes 9/10 deterministically exercise an
                    // ESTABLISHED render HWND becoming hidden.
                    Stopwatch establishedTimer = Stopwatch.StartNew();
                    while (establishedTimer.ElapsedMilliseconds < 100)
                    {
                        MSG establishMessage;
                        while (PeekMessageW(
                                out establishMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref establishMessage);
                            DispatchMessageW(ref establishMessage);
                        }
                        if (!IsWindowVisible(hwnd) || IsWindowEnabled(hwnd) ||
                                GetParent(hwnd) != owner)
                        {
                            DestroyWindow(hwnd);
                            return 81;
                        }
                        Thread.Sleep(1);
                    }
                    Console.WriteLine(
                        "established_render_hide_started=True lane=" + lane);
                    Console.Out.Flush();
                    ShowWindow(hwnd, SW_HIDE);
                    bool hideSucceeded = !IsWindowVisible(hwnd);
                    Console.WriteLine("established_render_hide_succeeded=" +
                        hideSucceeded + " lane=" + lane);
                    Console.Out.Flush();
                    if (!hideSucceeded)
                    {
                        DestroyWindow(hwnd);
                        return 82;
                    }
                    // Reproduce the real Godot shutdown ordering in both the
                    // positive teardown lane and the live-process negative:
                    // Windows can detach the thread's inert Default IME owner
                    // after the established render HWND hides, even though the
                    // live ImmGetDefaultIMEWnd(render) binding remains.
                    IntPtr defaultIme = ImmGetDefaultIMEWnd(hwnd);
                    IntPtr previousImeOwner = defaultIme == IntPtr.Zero
                        ? IntPtr.Zero
                        : SetWindowLongPtrW(
                            defaultIme, GWLP_HWNDPARENT, IntPtr.Zero);
                    bool detachedDefaultIme =
                        defaultIme != IntPtr.Zero &&
                        previousImeOwner == hwnd &&
                        GetParent(defaultIme) == IntPtr.Zero &&
                        ImmGetDefaultIMEWnd(hwnd) == defaultIme;
                    Console.WriteLine(
                        "established_render_default_ime_detached=" +
                        detachedDefaultIme + " lane=" + lane);
                    Console.Out.Flush();
                    if (!detachedDefaultIme)
                    {
                        DestroyWindow(hwnd);
                        return 84;
                    }
                    if (lane == 9)
                    {
                        // Longer than the established 25 ms sample cadence but
                        // shorter than the launcher's continuously attested
                        // 50 x 1 ms teardown bound.
                        Thread.Sleep(40);
                        DestroyWindow(hwnd);
                        return 0;
                    }
                    while (true)
                    {
                        MSG hiddenMessage;
                        while (PeekMessageW(
                                out hiddenMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref hiddenMessage);
                            DispatchMessageW(ref hiddenMessage);
                        }
                        Thread.Sleep(1);
                    }
                }
                if (lane == 5)
                {
                    if (!SpawnHiddenInputDesktopEscape(inputDesktopName))
                    {
                        DestroyWindow(hwnd);
                        return 79;
                    }
                    while (true)
                    {
                        MSG privateMessage;
                        while (PeekMessageW(
                                out privateMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref privateMessage);
                            DispatchMessageW(ref privateMessage);
                        }
                        Thread.Sleep(1);
                    }
                }
                if (lane == 6)
                {
                    IntPtr unsafeAuxiliary = CreateWindowExW(
                        0, "STATIC",
                        "TRAWF hidden private-desktop auxiliary fixture",
                        WS_POPUP, x, y, 96, 64,
                        hwnd, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                    if (unsafeAuxiliary == IntPtr.Zero)
                    {
                        DestroyWindow(hwnd);
                        return 80;
                    }
                    Console.WriteLine(
                        "hidden_private_auxiliary_created=True hwnd=" +
                        unsafeAuxiliary.ToInt64() + " visible=" +
                        IsWindowVisible(unsafeAuxiliary) + " pid=" +
                        Process.GetCurrentProcess().Id);
                    Console.Out.Flush();
                    while (true)
                    {
                        MSG privateMessage;
                        while (PeekMessageW(
                                out privateMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref privateMessage);
                            DispatchMessageW(ref privateMessage);
                        }
                        Thread.Sleep(1);
                    }
                }
                if (lane == 8)
                {
                    IntPtr unknownAuxiliary = CreateWindowExW(
                        0, "STATIC",
                        "TRAWF unknown zero-area auxiliary fixture",
                        WS_POPUP | WS_DISABLED, x, y, 0, 0,
                        hwnd, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                    if (unknownAuxiliary == IntPtr.Zero)
                    {
                        DestroyWindow(hwnd);
                        return 81;
                    }
                    Console.WriteLine(
                        "unknown_zero_area_auxiliary_created=True hwnd=" +
                        unknownAuxiliary.ToInt64() + " visible=" +
                        IsWindowVisible(unknownAuxiliary) + " enabled=" +
                        IsWindowEnabled(unknownAuxiliary) + " pid=" +
                        Process.GetCurrentProcess().Id);
                    Console.Out.Flush();
                    while (true)
                    {
                        MSG privateMessage;
                        while (PeekMessageW(
                                out privateMessage, IntPtr.Zero, 0, 0,
                                PM_REMOVE))
                        {
                            TranslateMessage(ref privateMessage);
                            DispatchMessageW(ref privateMessage);
                        }
                        Thread.Sleep(1);
                    }
                }
                DestroyWindow(hwnd);
                return 0;
            }
            Thread.Sleep(10);
        }
        DestroyWindow(hwnd);
        return 74;
    }
}
'@
            Add-Type -TypeDefinition $immediateShowFixtureSource `
                -Language CSharp -OutputAssembly $immediateShowFixturePath `
                -OutputType WindowsApplication
            $fixtureCoordinates = $selfTestOffscreenPosition -split ',', 2
            foreach ($immediateShowLane in @(1, 2, 9)) {
                # Reuse the private desktop but reset per-process topology state
                # so the second native child proves the first job and inherited
                # log handles were fully drained before another lane starts.
                $selfTestWindowHost.SawEmbeddedChild = $false
                $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
                $selfTestWindowHost.InputIsolationApplied = $false
                $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
                $selfTestWindowHost.InputIsolationReassertions = 0
                $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
                $selfTestWindowHost.IsolationSampleCount = [int64] 0
                $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
                $selfTestWindowHost.JobDrainSampleCount = [int64] 0
                $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
                $selfTestWindowHost.FirstInputEscapeSummary = ''
                # Lane 2 deterministically removes the earlier enumeration's
                # IME binding map. The exact live Engine-owner relationship must
                # still classify the inert Default IME without a startup grace.
                $selfTestWindowHost.SuppressImePrebindingForSelfTest =
                    $immediateShowLane -eq 2
                $immediateShowResult = Invoke-GateChild `
                    -Label "window-isolation-immediate-show-self-test-$immediateShowLane" `
                    -FilePath $immediateShowFixturePath `
                    -Arguments @(
                        $selfTestWindowHost.Id,
                        $fixtureCoordinates[0],
                        $fixtureCoordinates[1],
                        $immediateShowLane,
                        $selfTestWindowHost.InputDesktopName) `
                    -WorkingDirectory $RunArtifactDirectory `
                    -WindowIsolation $selfTestWindowHost `
                    -ChildTimeoutSeconds 30 -EchoOutput $false
                $immediateShowIsolationEvidence = if (Test-Path -LiteralPath `
                        $immediateShowResult.IsolationPath -PathType Leaf) {
                    [System.IO.File]::ReadAllText(
                        $immediateShowResult.IsolationPath)
                } else {
                    ''
                }
                if ($immediateShowResult.ExitCode -ne 0 -or
                        $immediateShowResult.Output -notmatch
                            '(?m)^startup_show_hidden=True\s*$' -or
                        $immediateShowResult.Output -notmatch
                            '(?m)^private_desktop_contained=True\s*$' -or
                        $immediateShowResult.Output -notmatch
                            'monitor_before_resume=True' -or
                        $immediateShowResult.Output -notmatch
                            'private_is_input=False' -or
                        $immediateShowResult.Output -notmatch
                            'embedded_input_disabled=True' -or
                        $immediateShowIsolationEvidence -notmatch
                            'exact_job_membership=True' -or
                        $immediateShowIsolationEvidence -notmatch
                            'input_name_matches=True' -or
                        $immediateShowIsolationEvidence -notmatch
                            'input_enumerated=True' -or
                        $immediateShowIsolationEvidence -notmatch
                            'input_escape_unsafe=False' -or
                        $immediateShowIsolationEvidence -notmatch
                            'job_tree_closed=True' -or
                        $immediateShowIsolationEvidence -notmatch
                            'first_input_escape=\[<none>\]' -or
                        $immediateShowIsolationEvidence -notmatch
                            'hosted_aux=\[\]' -or
                        ($immediateShowLane -ne 9 -and
                            $immediateShowIsolationEvidence -notmatch
                                'system_aux=\[[^\r\n]*class=IME,title=Default IME,rect=\[0,0,0,0\]') -or
                        ($immediateShowLane -eq 2 -and
                            $immediateShowIsolationEvidence -notmatch
                                'current_owner_ime_bindings=[1-9]\d*') -or
                        ($immediateShowLane -eq 2 -and
                            $immediateShowResult.Output -notmatch
                                '(?m)^current_owner_ime_fixture_held=True\s*$') -or
                        # The OS may lazily create the MSCTFIME child only after
                        # text input activity. Its absence is not a containment
                        # failure; when present, InspectJob still accepts only
                        # its exact class/title/style/owner binding or rejects
                        # it as an unsafe auxiliary. Default IME is the stable
                        # real-system classification anchor for this fixture.
                        ($immediateShowLane -eq 1 -and
                            $immediateShowResult.Output -notmatch
                                '(?m)^descendant_log_final=True\s*$') -or
                        ($immediateShowLane -eq 1 -and
                            $immediateShowIsolationEvidence -notmatch
                                'job_drain_samples=[1-9]\d*') -or
                        ($immediateShowLane -eq 9 -and
                            $immediateShowResult.Output -notmatch
                                '(?m)^established_render_hide_started=True lane=9\s*$') -or
                        ($immediateShowLane -eq 9 -and
                            $immediateShowResult.Output -notmatch
                                '(?m)^established_render_hide_succeeded=True lane=9\s*$') -or
                        ($immediateShowLane -eq 9 -and
                            $immediateShowResult.Output -notmatch
                                '(?m)^established_render_default_ime_detached=True lane=9\s*$') -or
                        ($immediateShowLane -eq 9 -and
                            $immediateShowIsolationEvidence -notmatch
                                'detached_ime_binding_samples=[1-9]\d*') -or
                        -not (Test-Path -LiteralPath `
                            $immediateShowResult.IsolationPath -PathType Leaf)) {
                    Write-GateError (
                        "Immediate-show private-desktop self-test lane $immediateShowLane " +
                        "failed with exit code $($immediateShowResult.ExitCode): " +
                        $immediateShowResult.Output)
                    exit 1
                }
            }
            $selfTestWindowHost.SuppressImePrebindingForSelfTest = $false
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            $liveHiddenRenderResult = Invoke-GateChild `
                -Label 'window-isolation-live-hidden-render-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $selfTestWindowHost.Id,
                    $fixtureCoordinates[0],
                    $fixtureCoordinates[1],
                    10,
                    $selfTestWindowHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $selfTestWindowHost `
                -ChildTimeoutSeconds 30 -EchoOutput $false
            $liveHiddenRenderIsolationEvidence = if (Test-Path -LiteralPath `
                    $liveHiddenRenderResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $liveHiddenRenderResult.IsolationPath)
            } else {
                ''
            }
            if ($liveHiddenRenderResult.ExitCode -ne 66 -or
                    -not $liveHiddenRenderResult.WindowIsolationFailed -or
                    $liveHiddenRenderResult.TimedOut -or
                    $liveHiddenRenderResult.Output -notmatch
                        '(?m)^established_render_hide_started=True lane=10\s*$' -or
                    $liveHiddenRenderResult.Output -notmatch
                        '(?m)^established_render_hide_succeeded=True lane=10\s*$' -or
                    $liveHiddenRenderResult.Output -notmatch
                        '(?m)^established_render_default_ime_detached=True lane=10\s*$' -or
                    $liveHiddenRenderResult.Output -notmatch
                        'root process remained live after the bounded teardown poll' -or
                    $liveHiddenRenderIsolationEvidence -notmatch
                        'detached_ime_binding_samples=[1-9]\d*' -or
                    $liveHiddenRenderIsolationEvidence -notmatch
                        'input_escape_unsafe=False' -or
                    $liveHiddenRenderIsolationEvidence -notmatch
                        'job_tree_closed=True' -or
                    $liveHiddenRenderIsolationEvidence -notmatch
                        'first_input_escape=\[<none>\]') {
                Write-GateError (
                    'Live hidden-render private-desktop self-test did not ' +
                    'fail closed with exit 66: ' +
                    $liveHiddenRenderResult.Output)
                exit 1
            }
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            $inputEscapeResult = Invoke-GateChild `
                -Label 'window-isolation-input-desktop-escape-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $selfTestWindowHost.Id,
                    $fixtureCoordinates[0],
                    $fixtureCoordinates[1],
                    5,
                    $selfTestWindowHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $selfTestWindowHost `
                -ChildTimeoutSeconds 30 -EchoOutput $false
            $inputEscapeIsolationEvidence = if (Test-Path -LiteralPath `
                    $inputEscapeResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $inputEscapeResult.IsolationPath)
            } else {
                ''
            }
            $inputEscapePidMatch = [regex]::Match(
                $inputEscapeResult.Output,
                '(?m)^hidden_input_escape_created=True hwnd=\d+ visible=False pid=(\d+)\s*$')
            $inputEscapeRootAlive = $false
            if ($inputEscapePidMatch.Success) {
                $inputEscapeRootAlive = $null -ne (Get-Process -Id `
                    ([int] $inputEscapePidMatch.Groups[1].Value) `
                    -ErrorAction SilentlyContinue)
            }
            if ($inputEscapeResult.ExitCode -ne 66 -or
                    -not $inputEscapeResult.WindowIsolationFailed -or
                    $inputEscapeResult.TimedOut -or
                    -not $inputEscapePidMatch.Success -or
                    $inputEscapeRootAlive -or
                    $inputEscapeIsolationEvidence -notmatch
                        'exact_job_membership=True' -or
                    $inputEscapeIsolationEvidence -notmatch
                        'input_escape_unsafe=True' -or
                    $inputEscapeIsolationEvidence -notmatch
                        'job_tree_closed=True' -or
                    $inputEscapeIsolationEvidence -notmatch
                        'positive_area=True' -or
                    $inputEscapeIsolationEvidence -notmatch
                        'class=Static' -or
                    $inputEscapeIsolationEvidence -notmatch
                        'title=TRAWF hidden input-desktop escape fixture' -or
                    $inputEscapeIsolationEvidence -match
                        'first_input_escape=\[<none>\]') {
                Write-GateError (
                    'Hidden input-desktop escape self-test failed: ' +
                    "exit=$($inputEscapeResult.ExitCode) " +
                    "isolation_failed=$($inputEscapeResult.WindowIsolationFailed) " +
                    "timed_out=$($inputEscapeResult.TimedOut) " +
                    "root_alive=$inputEscapeRootAlive " +
                    $inputEscapeResult.Output)
                exit 1
            }
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            $privateAuxiliaryResult = Invoke-GateChild `
                -Label 'window-isolation-private-auxiliary-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $selfTestWindowHost.Id,
                    $fixtureCoordinates[0],
                    $fixtureCoordinates[1],
                    6,
                    $selfTestWindowHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $selfTestWindowHost `
                -ChildTimeoutSeconds 30 -EchoOutput $false
            $privateAuxiliaryEvidence = if (Test-Path -LiteralPath `
                    $privateAuxiliaryResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $privateAuxiliaryResult.IsolationPath)
            } else {
                ''
            }
            if ($privateAuxiliaryResult.ExitCode -ne 66 -or
                    -not $privateAuxiliaryResult.WindowIsolationFailed -or
                    $privateAuxiliaryResult.TimedOut -or
                    $privateAuxiliaryResult.Output -notmatch
                        '(?m)^hidden_private_auxiliary_created=True hwnd=\d+ visible=False pid=\d+\s*$' -or
                    $privateAuxiliaryEvidence -notmatch
                        'title=TRAWF hidden private-desktop auxiliary fixture' -or
                    $privateAuxiliaryEvidence -notmatch
                        'exstyle=0x0' -or
                    $privateAuxiliaryEvidence -notmatch
                        'rect=\[-?\d+,-?\d+,96,64\]' -or
                    $privateAuxiliaryEvidence -notmatch
                        'hosted_aux=\[') {
                Write-GateError (
                    'Hidden positive-area private-desktop auxiliary self-test failed: ' +
                    "exit=$($privateAuxiliaryResult.ExitCode) " +
                    "isolation_failed=$($privateAuxiliaryResult.WindowIsolationFailed) " +
                    "timed_out=$($privateAuxiliaryResult.TimedOut) " +
                    $privateAuxiliaryResult.Output)
                exit 1
            }
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            # The live-owner fallback remains active for this adversarial lane:
            # an exact Default IME may pass, but an otherwise inert unknown
            # zero-area owner-bound helper must still terminate the exact Job.
            $selfTestWindowHost.SuppressImePrebindingForSelfTest = $true
            try {
                $unknownAuxiliaryResult = Invoke-GateChild `
                    -Label 'window-isolation-unknown-auxiliary-self-test' `
                    -FilePath $immediateShowFixturePath `
                    -Arguments @(
                        $selfTestWindowHost.Id,
                        $fixtureCoordinates[0],
                        $fixtureCoordinates[1],
                        8,
                        $selfTestWindowHost.InputDesktopName) `
                    -WorkingDirectory $RunArtifactDirectory `
                    -WindowIsolation $selfTestWindowHost `
                    -ChildTimeoutSeconds 30 -EchoOutput $false
            } finally {
                $selfTestWindowHost.SuppressImePrebindingForSelfTest = $false
            }
            $unknownAuxiliaryEvidence = if (Test-Path -LiteralPath `
                    $unknownAuxiliaryResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $unknownAuxiliaryResult.IsolationPath)
            } else {
                ''
            }
            if ($unknownAuxiliaryResult.ExitCode -ne 66 -or
                    -not $unknownAuxiliaryResult.WindowIsolationFailed -or
                    $unknownAuxiliaryResult.TimedOut -or
                    $unknownAuxiliaryResult.Output -notmatch
                        '(?m)^unknown_zero_area_auxiliary_created=True hwnd=\d+ visible=False enabled=False pid=\d+\s*$' -or
                    $unknownAuxiliaryEvidence -notmatch
                        'title=TRAWF unknown zero-area auxiliary fixture' -or
                    $unknownAuxiliaryEvidence -notmatch
                        'rect=\[-?\d+,-?\d+,0,0\]' -or
                    $unknownAuxiliaryEvidence -notmatch
                        'hosted_aux=\[') {
                Write-GateError (
                    'Unknown zero-area private-desktop auxiliary self-test failed: ' +
                    "exit=$($unknownAuxiliaryResult.ExitCode) " +
                    "isolation_failed=$($unknownAuxiliaryResult.WindowIsolationFailed) " +
                    "timed_out=$($unknownAuxiliaryResult.TimedOut) " +
                    $unknownAuxiliaryResult.Output)
                exit 1
            }
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            $hangingTreeTimer =
                [System.Diagnostics.Stopwatch]::StartNew()
            $hangingTreeResult = Invoke-GateChild `
                -Label 'window-isolation-hanging-tree-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $selfTestWindowHost.Id,
                    $fixtureCoordinates[0],
                    $fixtureCoordinates[1],
                    3,
                    $selfTestWindowHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $selfTestWindowHost `
                -ChildTimeoutSeconds 2 -EchoOutput $false
            $hangingTreeTimer.Stop()
            $hangingPidMatch = [regex]::Match(
                $hangingTreeResult.Output,
                '(?m)^hanging_descendant_spawned_pid=(\d+)\s*$')
            $hangingDescendantAlive = $false
            if ($hangingPidMatch.Success) {
                $hangingDescendantPid =
                    [int] $hangingPidMatch.Groups[1].Value
                $hangingDescendantAlive = $null -ne (Get-Process -Id `
                    $hangingDescendantPid -ErrorAction SilentlyContinue)
            }
            if ($hangingTreeResult.ExitCode -ne 124 -or
                    -not $hangingTreeResult.TimedOut -or
                    $hangingTreeTimer.ElapsedMilliseconds -gt 15000 -or
                    -not $hangingPidMatch.Success -or
                    $hangingDescendantAlive -or
                    $hangingTreeResult.Output -notmatch
                        '(?m)^root_hang_started=True\s*$' -or
                    $hangingTreeResult.Output -notmatch
                        'embedded_input_disabled=True' -or
                    -not (Test-Path -LiteralPath `
                        $hangingTreeResult.IsolationPath -PathType Leaf)) {
                Write-GateError (
                    'Hanging native process-tree self-test failed: ' +
                    "exit=$($hangingTreeResult.ExitCode) " +
                    "timed_out=$($hangingTreeResult.TimedOut) " +
                    "elapsed_ms=$($hangingTreeTimer.ElapsedMilliseconds) " +
                    "descendant_alive=$hangingDescendantAlive " +
                    $hangingTreeResult.Output)
                exit 1
            }
            $selfTestWindowHost.SawEmbeddedChild = $false
            $selfTestWindowHost.SawEmbeddedVisibleStyle = $false
            $selfTestWindowHost.InputIsolationApplied = $false
            $selfTestWindowHost.MonitorEstablishedBeforeResume = $false
            $selfTestWindowHost.InputIsolationReassertions = 0
            $selfTestWindowHost.EmbeddedWindowHandle = [int64] 0
            $selfTestWindowHost.IsolationSampleCount = [int64] 0
            $selfTestWindowHost.DetachedOwnerImeBindingSampleCount = [int64] 0
            $selfTestWindowHost.JobDrainSampleCount = [int64] 0
            $selfTestWindowHost.InputDesktopWindowSampleCount = [int64] 0
            $selfTestWindowHost.FirstInputEscapeSummary = ''
            $nonzeroResult = Invoke-GateChild `
                -Label 'window-isolation-native-exit-37-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $selfTestWindowHost.Id,
                    $fixtureCoordinates[0],
                    $fixtureCoordinates[1],
                    4,
                    $selfTestWindowHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $selfTestWindowHost `
                -ChildTimeoutSeconds 30 -EchoOutput $false
            $nonzeroPidMatch = [regex]::Match(
                $nonzeroResult.Output,
                '(?m)^nonzero_root_pid=(\d+)\s*$')
            $nonzeroRootAlive = $false
            if ($nonzeroPidMatch.Success) {
                $nonzeroRootPid =
                    [int] $nonzeroPidMatch.Groups[1].Value
                $nonzeroRootAlive = $null -ne (Get-Process -Id `
                    $nonzeroRootPid -ErrorAction SilentlyContinue)
            }
            $nonzeroIsolationEvidence = if (Test-Path -LiteralPath `
                    $nonzeroResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $nonzeroResult.IsolationPath)
            } else {
                ''
            }
            $nonzeroLogClosed = Test-GateLogHandleClosed `
                -Path $nonzeroResult.StdoutPath
            if ($nonzeroResult.ExitCode -ne 37 -or
                    $nonzeroResult.TimedOut -or
                    $nonzeroResult.WindowIsolationFailed -or
                    -not $nonzeroPidMatch.Success -or
                    $nonzeroRootAlive -or
                    -not $nonzeroLogClosed -or
                    $nonzeroResult.Output -notmatch
                        '(?m)^startup_show_hidden=True\s*$' -or
                    $nonzeroResult.Output -notmatch
                        '(?m)^private_desktop_contained=True\s*$' -or
                    $nonzeroResult.Output -notmatch
                        'monitor_before_resume=True' -or
                    $nonzeroResult.Output -notmatch
                        'private_is_input=False' -or
                    $nonzeroResult.Output -notmatch
                        'embedded_input_disabled=True' -or
                    $nonzeroIsolationEvidence -notmatch
                        'embedded_input_disabled=True') {
                Write-GateError (
                    'Native nonzero-exit containment self-test failed: ' +
                    "exit=$($nonzeroResult.ExitCode) " +
                    "timed_out=$($nonzeroResult.TimedOut) " +
                    "isolation_failed=$($nonzeroResult.WindowIsolationFailed) " +
                    "root_alive=$nonzeroRootAlive " +
                    "log_closed=$nonzeroLogClosed " +
                    $nonzeroResult.Output)
                exit 1
            }
        }
    } finally {
        Remove-HiddenWindowHost -WindowHost $selfTestWindowHost
    }

    if ($env:OS -eq 'Windows_NT') {
        $headlessAlertHost = New-HiddenWindowHost -RequireRenderWindow $false
        try {
            $headlessAlertCoordinates =
                $headlessAlertHost.OffscreenPosition -split ',', 2
            $headlessAlertResult = Invoke-GateChild `
                -Label 'headless-alert-private-desktop-self-test' `
                -FilePath $immediateShowFixturePath `
                -Arguments @(
                    $headlessAlertHost.Id,
                    $headlessAlertCoordinates[0],
                    $headlessAlertCoordinates[1],
                    7,
                    $headlessAlertHost.InputDesktopName) `
                -WorkingDirectory $RunArtifactDirectory `
                -WindowIsolation $headlessAlertHost `
                -ChildTimeoutSeconds 30 -EchoOutput $false
            $headlessAlertEvidence = if (Test-Path -LiteralPath `
                    $headlessAlertResult.IsolationPath -PathType Leaf) {
                [System.IO.File]::ReadAllText(
                    $headlessAlertResult.IsolationPath)
            } else {
                ''
            }
            if ($headlessAlertResult.ExitCode -ne 66 -or
                    -not $headlessAlertResult.WindowIsolationFailed -or
                    $headlessAlertResult.TimedOut -or
                    $headlessAlertResult.Output -notmatch
                        '(?m)^headless_alert_private_desktop=True pid=\d+\s*$' -or
                    $headlessAlertEvidence -notmatch
                        'render_window_required=False' -or
                    $headlessAlertEvidence -notmatch
                        'private_is_input=False' -or
                    $headlessAlertEvidence -notmatch
                        'exact_job_membership=True' -or
                    $headlessAlertEvidence -notmatch
                        'input_escape_unsafe=False' -or
                    $headlessAlertEvidence -notmatch
                        'job_tree_closed=True' -or
                    $headlessAlertEvidence -notmatch
                        'title=ALERT: headless fixture' -or
                    $headlessAlertEvidence -notmatch
                        'disallowed_top_levels=\[' -or
                    $headlessAlertEvidence -notmatch
                        'first_input_escape=\[<none>\]') {
                Write-GateError (
                    'Headless ALERT private-desktop containment self-test ' +
                    "failed: exit=$($headlessAlertResult.ExitCode) " +
                    "isolation_failed=$($headlessAlertResult.WindowIsolationFailed) " +
                    "timed_out=$($headlessAlertResult.TimedOut) " +
                    $headlessAlertResult.Output)
                exit 1
            }
        } finally {
            Remove-HiddenWindowHost -WindowHost $headlessAlertHost
        }
    }
    $headlessArgumentProbe = @(Get-NativeGodotArguments -LaunchMode 'Headless' `
        -EntryPoint 'res://scenes/system/test_bootstrap.tscn' `
        -TestArguments @('--test-all', '--fail-on-skip'))
    $expectedHeadlessArguments = @(
        '--headless', '--path', $ProjectPath,
        'res://scenes/system/test_bootstrap.tscn', '--',
        '--test-all', '--fail-on-skip'
    )
    if (($headlessArgumentProbe -join "`0") -cne
            ($expectedHeadlessArguments -join "`0") -or
            $headlessArgumentProbe.Contains('--windowed') -or
            $headlessArgumentProbe.Contains('--position') -or
            $headlessArgumentProbe.Contains('--single-window')) {
        Write-GateError (
            'Headless launch self-test did not preserve the exact bootstrap, ' +
            'single test flag, and fail-on-skip argument contract.')
        exit 1
    }

    $requiredAppLocalInputSources = @(
        (Join-Path $ProjectPath 'tools\agent_player_input_driver.gd'),
        (Join-Path $ProjectPath 'tools\generated_input_playthrough_driver.gd'),
        (Join-Path $ProjectPath 'scripts\test_runner_cli.gd')
    )
    $cursorPolicyMutations = @(
        [PSCustomObject] @{ Name = 'direct-input-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'Input.warp_mouse(Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'spaced-input-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'Input . warp_mouse (Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'dynamic-input-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'Input.call("warp_mouse", Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'constructed-input-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'Input.call("warp" + "_mouse", Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'multi-fragment-input-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'Input.call("war" + "p_" + "mouse", Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'csharp-input-warp'; Path = 'tests/mutation.cs'; Source = 'Input.WarpMouse(Vector2.Zero);'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'display-server-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'DisplayServer.warp_mouse(Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'viewport-warp'; Path = 'scripts/testing/mutation.gd'; Source = 'get_viewport().warp_mouse(Vector2.ZERO)'; Expected = 'cursor-warp-symbol' }
        [PSCustomObject] @{ Name = 'dynamic-cursor-capture'; Path = 'tools/mutation.gd'; Source = 'Input.call("set_mouse_mode", Input.MOUSE_MODE_CAPTURED)'; Expected = 'automated-os-pointer:set_mouse_mode' }
        [PSCustomObject] @{ Name = 'native-cursor-position'; Path = 'tools/mutation.cpp'; Source = 'SetCursorPos(1, 1);'; Expected = 'automated-os-pointer:SetCursorPos' }
        [PSCustomObject] @{ Name = 'native-cursor-confinement'; Path = 'tools/mutation.cpp'; Source = 'ClipCursor(&bounds);'; Expected = 'automated-os-pointer:ClipCursor' }
        [PSCustomObject] @{ Name = 'window-reposition'; Path = 'scripts/testing/mutation.gd'; Source = 'DisplayServer.window_set_position(Vector2i.ZERO)'; Expected = 'window-lifetime:window_set_position' }
        [PSCustomObject] @{ Name = 'dynamic-window-mode'; Path = 'scripts/testing/mutation.gd'; Source = 'DisplayServer.call("window_set_mode", 0)'; Expected = 'window-lifetime:window_set_mode' }
        [PSCustomObject] @{ Name = 'constructed-window-position'; Path = 'scripts/testing/mutation.gd'; Source = 'DisplayServer.call("window_" + "set_" + "position", Vector2i.ZERO)'; Expected = 'window-lifetime:window_set_position' }
        [PSCustomObject] @{ Name = 'constructed-window-mode'; Path = 'scripts/testing/mutation.gd'; Source = 'DisplayServer.call("window_" + "set_" + "mode", 0)'; Expected = 'window-lifetime:window_set_mode' }
        [PSCustomObject] @{ Name = 'window-position-property'; Path = 'tools/mutation.gd'; Source = 'Window.position = Vector2i.ZERO'; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'window-position-setter'; Path = 'tools/mutation.gd'; Source = 'get_window().set_position(Vector2i.ZERO)'; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'window-position-dynamic'; Path = 'tools/mutation.gd'; Source = 'get_window().call("set_position", Vector2i.ZERO)'; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'typed-window-position'; Path = 'tools/mutation.gd'; Source = "var surface: Window = get_window()`nsurface.position = Vector2i.ZERO"; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'inferred-window-position'; Path = 'tools/mutation.gd'; Source = "var surface := get_window()`nsurface.position = Vector2i.ZERO"; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'csharp-window-position-setter'; Path = 'tests/mutation.cs'; Source = 'Window surface; surface.SetPosition(Vector2I.Zero);'; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'csharp-inferred-window-position'; Path = 'tests/mutation.cs'; Source = "var surface = GetWindow();`nsurface.SetPosition(Vector2I.Zero);"; Expected = 'window-lifetime:Window.position' }
        [PSCustomObject] @{ Name = 'window-mode-property'; Path = 'tools/mutation.gd'; Source = 'get_window().mode = Window.MODE_FULLSCREEN'; Expected = 'window-lifetime:Window.mode' }
        [PSCustomObject] @{ Name = 'window-mode-setter'; Path = 'tools/mutation.gd'; Source = '_root_window.set_mode(Window.MODE_FULLSCREEN)'; Expected = 'window-lifetime:Window.mode' }
        [PSCustomObject] @{ Name = 'window-mode-dynamic'; Path = 'tools/mutation.gd'; Source = 'get_tree().root.set("mode", Window.MODE_FULLSCREEN)'; Expected = 'window-lifetime:Window.mode' }
        [PSCustomObject] @{ Name = 'window-foreground-method'; Path = 'tools/mutation.gd'; Source = '_root_window.move_to_foreground()'; Expected = 'window-lifetime:Window.move_to_foreground' }
        [PSCustomObject] @{ Name = 'window-foreground-dynamic'; Path = 'tools/mutation.gd'; Source = 'get_window().call("move_to_foreground")'; Expected = 'window-lifetime:Window.move_to_foreground' }
    )
    foreach ($mutation in $cursorPolicyMutations) {
        $mutationViolations = @(Get-CursorIsolationPolicyViolations `
            -Source $mutation.Source -RelativePath $mutation.Path)
        if (-not $mutationViolations.Contains($mutation.Expected)) {
            Write-GateError ("Cursor-isolation mutation '{0}' escaped policy: expected '{1}', observed [{2}]." -f
                $mutation.Name, $mutation.Expected, ($mutationViolations -join ', '))
            exit 1
        }
    }
    $safePointerFixture = @'
var motion := InputEventMouseMotion.new()
Input.parse_input_event(motion)
'@
    if (@(Get-CursorIsolationPolicyViolations -Source $safePointerFixture `
                -RelativePath 'tools/app_local_fixture.gd').Count -ne 0) {
        Write-GateError 'Cursor-isolation policy rejected app-local Godot pointer injection.'
        exit 1
    }
    $safeTransformFixture = 'character.position = Vector3.ZERO'
    if (@(Get-CursorIsolationPolicyViolations -Source $safeTransformFixture `
                -RelativePath 'tools/app_local_fixture.gd').Count -ne 0) {
        Write-GateError 'Cursor-isolation policy confused an ordinary character transform with Window.position.'
        exit 1
    }
    $safeTransformSetterFixture = 'character.set_position(Vector3.ZERO)'
    if (@(Get-CursorIsolationPolicyViolations -Source $safeTransformSetterFixture `
                -RelativePath 'tools/app_local_fixture.gd').Count -ne 0) {
        Write-GateError 'Cursor-isolation policy confused an ordinary character position setter with Window.set_position.'
        exit 1
    }
    $allowedOffscreenFixture = 'DisplayServer.window_set_position(Vector2i(20000, 20000))'
    if (@(Get-CursorIsolationPolicyViolations -Source $allowedOffscreenFixture `
                -RelativePath 'tools/offscreen_window.gd').Count -ne 0) {
        Write-GateError 'Cursor-isolation policy rejected the single allowlisted offscreen-window park helper.'
        exit 1
    }

    foreach ($projectSource in @(Get-ProjectExecutableTestSourceFiles -Directory $ProjectPath)) {
        $projectSourceText = [System.IO.File]::ReadAllText($projectSource.FullName)
        $projectRelativePath = Get-ProjectRelativeSourcePath -FullPath $projectSource.FullName
        $policyViolations = @(Get-CursorIsolationPolicyViolations `
            -Source $projectSourceText -RelativePath $projectRelativePath)
        if ($policyViolations.Count -gt 0) {
            Write-GateError ("Project executable/test source violates cursor/offscreen isolation: {0} [{1}]" -f
                $projectSource.FullName, ($policyViolations -join ', '))
            exit 1
        }
    }
    foreach ($inputSourcePath in $requiredAppLocalInputSources) {
        $inputSource = [System.IO.File]::ReadAllText($inputSourcePath)
        if ($inputSource -notmatch 'InputEventMouseMotion\.new\s*\(\)' -or
                $inputSource -notmatch 'Input\.parse_input_event\s*\(') {
            Write-GateError "Required automated input source lacks app-local Godot pointer injection: $inputSourcePath"
            exit 1
        }
    }

    $bootstrapSourcePath = Join-Path $ProjectPath 'scripts\test_bootstrap.gd'
    $bootstrapSource = [System.IO.File]::ReadAllText($bootstrapSourcePath)
    foreach ($bootstrapContractToken in @(
        '_windowed_test_contract_active = _is_test_invocation()',
        'WINDOWS_HIDDEN_PARENT_MODE',
        '_is_canonical_position_token(expected_position)',
        'var launch_failure := _windowed_launch_token_failure()',
        'Windowed test enter-tree launch contract failed:',
        'var surface_failure := _windowed_surface_contract_failure()',
        'actual_position != expected_position',
        'DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)',
        'process_priority = 1000000',
        'func _process(',
        '_enforce_window_isolation(',
        '_window_is_fully_offscreen()',
        '_rects_have_positive_area_intersection(',
        '_fail_windowed_contract()'
    )) {
        if (-not $bootstrapSource.Contains($bootstrapContractToken)) {
            Write-GateError "Windowed bootstrap lacks fail-closed/lifetime token '$bootstrapContractToken'."
            exit 1
        }
    }
    if ($bootstrapSource -match 'if\s+(?:expected_position|parent_id)\s*==\s*""\s*:\s*\r?\n\s*return\s+true') {
        Write-GateError 'Windowed bootstrap still fails open when its offscreen launch environment is absent.'
        exit 1
    }
    $expectedTierNames = @('Headless', 'Windowed', 'Web')
    $actualTierNames = @($script:GateTierManifest.Keys)
    if ($actualTierNames.Count -ne $expectedTierNames.Count) {
        Write-GateError ("Tier-manifest self-test expected exactly {0}; observed {1}." -f
            ($expectedTierNames -join ', '), ($actualTierNames -join ', '))
        exit 1
    }
    for ($tierIndex = 0; $tierIndex -lt $expectedTierNames.Count; $tierIndex += 1) {
        if ($actualTierNames[$tierIndex] -cne $expectedTierNames[$tierIndex]) {
            Write-GateError ("Tier-manifest self-test expected tier {0} at index {1}; observed {2}." -f
                $expectedTierNames[$tierIndex], $tierIndex, $actualTierNames[$tierIndex])
            exit 1
        }
    }

    $expectedPreflightNames = @('AgentPlayerInputBoundary')
    $actualPreflightNames = @($script:GatePreflightManifest.Keys)
    if ($actualPreflightNames.Count -ne $expectedPreflightNames.Count -or
            $actualPreflightNames[0] -cne $expectedPreflightNames[0]) {
        Write-GateError (
            'Preflight-manifest self-test requires exactly one ' +
            'AgentPlayerInputBoundary entry.')
        exit 1
    }
    $agentPlayerBoundaryPreflight =
        $script:GatePreflightManifest['AgentPlayerInputBoundary']
    if ($null -eq $agentPlayerBoundaryPreflight -or
            $agentPlayerBoundaryPreflight.Label -cne
                'preflight-agent-player-input-boundary' -or
            $agentPlayerBoundaryPreflight.LaunchMode -cne 'Headless' -or
            $agentPlayerBoundaryPreflight.EntryPoint -cne
                'res://tools/verify_agent_player_input_boundary.gd' -or
            @($agentPlayerBoundaryPreflight.TestArguments).Count -ne 0) {
        Write-GateError (
            'Preflight-manifest self-test requires the exact contained ' +
            'agent-player input-boundary verifier contract.')
        exit 1
    }

    $expectedNativeManifest = [ordered] @{
        Headless = @(
            [PSCustomObject] @{
                Label = 'headless-test-all'
                LaunchMode = 'Headless'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-all', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'headless-aster-drink-authority'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_aster_drink_authority.gd'
                TestArguments = @()
            }
            [PSCustomObject] @{
                Label = 'headless-persona-decision-pipeline'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_persona_decision_pipeline.gd'
                TestArguments = @()
            }
            [PSCustomObject] @{
                Label = 'headless-generated-actionable-approaches'
                LaunchMode = 'Headless'
                EntryPoint = 'res://tools/verify_generated_actionable_approaches.gd'
                TestArguments = @()
            }
        )
        Windowed = @(
            [PSCustomObject] @{
                Label = 'windowed-player-contract'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-player-contract', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-player-observation'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-player-observation', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-basin-player-journey'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-basin-player-journey', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-persona-probe'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-persona-probe', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-player-surface-matrix'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-generated-player-surface-matrix', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-stretch-playtest-loop'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://scenes/system/test_bootstrap.tscn'
                TestArguments = @('--test-generated-stretch-playtest-loop', '--fail-on-skip')
            }
            [PSCustomObject] @{
                Label = 'windowed-generated-interaction-truth'
                LaunchMode = 'Windowed'
                EntryPoint = 'res://tools/verify_generated_interaction_truth.gd'
                TestArguments = @()
            }
        )
    }
    foreach ($nativeTierName in $expectedNativeManifest.Keys) {
        $nativeTierDefinition = $script:GateTierManifest[$nativeTierName]
        if ($null -eq $nativeTierDefinition -or $nativeTierDefinition.Kind -cne 'Native') {
            Write-GateError "Tier-manifest self-test expected '$nativeTierName' to be a Native tier."
            exit 1
        }
        $expectedNativeInvocations = @($expectedNativeManifest[$nativeTierName])
        $actualNativeInvocations = @($nativeTierDefinition.Invocations)
        if ($actualNativeInvocations.Count -ne $expectedNativeInvocations.Count) {
            Write-GateError ("Tier-manifest self-test expected {0} '{1}' invocation(s); observed {2}." -f
                $expectedNativeInvocations.Count, $nativeTierName, $actualNativeInvocations.Count)
            exit 1
        }
        for ($invocationIndex = 0; $invocationIndex -lt $expectedNativeInvocations.Count; $invocationIndex += 1) {
            $expectedInvocation = $expectedNativeInvocations[$invocationIndex]
            $actualInvocation = $actualNativeInvocations[$invocationIndex]
            if ($actualInvocation.EntryPoint -ceq
                    $agentPlayerBoundaryPreflight.EntryPoint) {
                Write-GateError (
                    'Agent-player input-boundary verifier must live only in ' +
                    'the shared preflight manifest, not a tier invocation.')
                exit 1
            }
            if ($actualInvocation.Label -cne $expectedInvocation.Label -or
                    $actualInvocation.LaunchMode -cne $expectedInvocation.LaunchMode -or
                    $actualInvocation.EntryPoint -cne $expectedInvocation.EntryPoint) {
                Write-GateError ("Tier-manifest self-test found an unexpected '{0}' invocation at index {1}: label={2}, mode={3}, entry={4}." -f
                    $nativeTierName, $invocationIndex, $actualInvocation.Label,
                    $actualInvocation.LaunchMode, $actualInvocation.EntryPoint)
                exit 1
            }
            $expectedTestArguments = @($expectedInvocation.TestArguments)
            $actualTestArguments = @($actualInvocation.TestArguments)
            if ($actualTestArguments.Count -ne $expectedTestArguments.Count) {
                Write-GateError ("Tier-manifest self-test expected '{0}' arguments [{1}]; observed [{2}]." -f
                    $actualInvocation.Label, ($expectedTestArguments -join ', '), ($actualTestArguments -join ', '))
                exit 1
            }
            for ($argumentIndex = 0; $argumentIndex -lt $expectedTestArguments.Count; $argumentIndex += 1) {
                if ($actualTestArguments[$argumentIndex] -cne $expectedTestArguments[$argumentIndex]) {
                    Write-GateError ("Tier-manifest self-test expected '{0}' arguments [{1}]; observed [{2}]." -f
                        $actualInvocation.Label, ($expectedTestArguments -join ', '), ($actualTestArguments -join ', '))
                    exit 1
                }
            }
        }
    }

    $webTierDefinition = $script:GateTierManifest['Web']
    if ($null -eq $webTierDefinition -or $webTierDefinition.Kind -cne 'Web' -or
            $webTierDefinition.NpmScript -cne 'test:web:basin' -or
            $webTierDefinition.ExpectedNpmCommand -cne 'playwright test tests/web/basin-fill-proof.spec.mjs --repeat-each=2' -or
            $webTierDefinition.PlaywrightSpec -cne 'tests/web/basin-fill-proof.spec.mjs') {
        Write-GateError 'Tier-manifest self-test requires Web test:web:basin to run the Basin spec with --repeat-each=2.'
        exit 1
    }
    $packageJsonPath = Join-Path $ProjectPath 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        Write-GateError "Web tier-manifest self-test could not find package.json: $packageJsonPath"
        exit 1
    }
    try {
        $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
    } catch {
        Write-GateError "Web tier-manifest self-test could not parse package.json: $_"
        exit 1
    }
    $npmScriptProperty = $packageJson.scripts.PSObject.Properties[$webTierDefinition.NpmScript]
    if ($null -eq $npmScriptProperty -or
            [string] $npmScriptProperty.Value -cne $webTierDefinition.ExpectedNpmCommand) {
        $observedNpmCommand = if ($null -eq $npmScriptProperty) { '<missing>' } else { [string] $npmScriptProperty.Value }
        Write-GateError ("Web tier-manifest self-test expected npm script '{0}' to be '{1}'; observed '{2}'." -f
            $webTierDefinition.NpmScript, $webTierDefinition.ExpectedNpmCommand, $observedNpmCommand)
        exit 1
    }
    $playwrightSpecPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectPath $webTierDefinition.PlaywrightSpec))
    if (-not (Test-Path -LiteralPath $playwrightSpecPath -PathType Leaf)) {
        Write-GateError "Web tier-manifest self-test could not find the resolved Basin Playwright spec: $playwrightSpecPath"
        exit 1
    }
    $playwrightSpecSource = Get-Content -LiteralPath $playwrightSpecPath -Raw
    foreach ($requiredWebContractToken in @(
        'Generated seed-5 Capbage HIDE roundtrip uses strict Web player observations',
        'Static Capbage-green source cannot self-attest a suppressed Web result pulse',
        'generated_player_surface_seed_5',
        'result_pulse_static_green_contract',
        'CONTROL RECEIVED'
    )) {
        if (-not $playwrightSpecSource.Contains($requiredWebContractToken)) {
            Write-GateError (
                "Web tier-manifest self-test requires the Basin spec contract token '$requiredWebContractToken'.")
            exit 1
        }
    }

    $webE2eRegistryPath = Join-Path $ProjectPath 'scripts/fragments/fragment_preview_sequence.gd'
    if (-not (Test-Path -LiteralPath $webE2eRegistryPath -PathType Leaf)) {
        Write-GateError "Web tier-manifest self-test could not find the e2e entry registry: $webE2eRegistryPath"
        exit 1
    }
    $webE2eRegistrySource = Get-Content -LiteralPath $webE2eRegistryPath -Raw
    foreach ($requiredWebRegistryToken in @(
        'const WEB_E2E_PREVIEW_ENTRIES',
        'func get_web_e2e_preview_entry',
        'generated_player_surface_seed_5',
        'result_pulse_static_green_contract'
    )) {
        if (-not $webE2eRegistrySource.Contains($requiredWebRegistryToken)) {
            Write-GateError (
                "Web tier-manifest self-test requires the e2e registry token '$requiredWebRegistryToken'.")
            exit 1
        }
    }

    # Fixture quarantine is a structural contract, not a token inventory. In
    # particular, the same id existing somewhere in this file does not prove it
    # stayed out of the player-facing picker/CLI/handoff registries.
    $ordinaryPreviewRegistryMatch = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^const\s+PREVIEW_ENTRIES\s*:=\s*\[.*?^\]\s*$'
    )
    $ordinaryChunkRegistryMatch = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^const\s+CHUNK_SCENES\s*:=\s*\{.*?^\}\s*$'
    )
    if (-not $ordinaryPreviewRegistryMatch.Success -or -not $ordinaryChunkRegistryMatch.Success) {
        Write-GateError 'Web tier-manifest self-test could not structurally isolate the ordinary preview registries.'
        exit 1
    }
    $ordinaryPreviewRegistrySource = $ordinaryPreviewRegistryMatch.Value
    $ordinaryChunkRegistrySource = $ordinaryChunkRegistryMatch.Value
    $webFixtureIds = @(
        'generated_player_surface_seed_5',
        'result_pulse_static_green_contract'
    )
    foreach ($webFixtureId in $webFixtureIds) {
        if ($ordinaryPreviewRegistrySource.Contains($webFixtureId)) {
            Write-GateError (
                "Web fixture '$webFixtureId' leaked into ordinary PREVIEW_ENTRIES.")
            exit 1
        }
    }
    $webFixtureChunkId = 'result_pulse_web_contract'
    $webFixtureScenePath = 'res://scenes/fragments/chunks/result_pulse_web_contract_chunk.tscn'
    if ($ordinaryPreviewRegistrySource.Contains($webFixtureChunkId) -or
            $ordinaryPreviewRegistrySource.Contains($webFixtureScenePath) -or
            $ordinaryChunkRegistrySource.Contains($webFixtureChunkId) -or
            $ordinaryChunkRegistrySource.Contains($webFixtureScenePath)) {
        Write-GateError 'The result-pulse Web fixture scene leaked into an ordinary preview registry.'
        exit 1
    }

    $ordinaryResolverSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^static\s+func\s+get_preview_entry\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $ordinaryStageResolverSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^static\s+func\s+get_preview_stage\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $ordinaryPickerSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^func\s+_build_fragment_menu\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $ordinaryHandoffSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^func\s+request_preview_handoff\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $ordinaryBeginSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^func\s+_begin\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    if (-not $ordinaryResolverSource.Contains('for entry in PREVIEW_ENTRIES:') -or
            $ordinaryResolverSource.Contains('WEB_E2E') -or
            -not $ordinaryStageResolverSource.Contains('get_preview_entry(entry_id)') -or
            $ordinaryStageResolverSource.Contains('WEB_E2E') -or
            -not $ordinaryPickerSource.Contains('PREVIEW_ENTRIES.duplicate()') -or
            $ordinaryPickerSource.Contains('WEB_E2E') -or
            -not $ordinaryHandoffSource.Contains('get_preview_entry(entry_id)') -or
            $ordinaryHandoffSource.Contains('get_web_e2e_preview_entry') -or
            -not $ordinaryBeginSource.Contains('_apply_preview_entry(get_preview_entry(cli_id))') -or
            -not $ordinaryBeginSource.Contains('_apply_preview_entry(get_preview_entry(menu_launch_id))') -or
            $ordinaryBeginSource.Contains('get_web_e2e_preview_entry')) {
        Write-GateError 'A picker, handoff, CLI, stage, or ordinary id resolver can reach the Web fixture registry.'
        exit 1
    }

    $fixtureChunkLookupSource = [regex]::Match(
        $webE2eRegistrySource,
        '(?ms)^func\s+_get_chunk_scene\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $fixtureEntryGuardIndex = $fixtureChunkLookupSource.IndexOf(
        'if WEB_E2E_PREVIEW_ENTRIES.has(_active_preview_entry_id):')
    $fixtureSceneLookupIndex = $fixtureChunkLookupSource.IndexOf(
        'WEB_E2E_CHUNK_SCENES.get(')
    $ordinarySceneLookupIndex = $fixtureChunkLookupSource.IndexOf(
        'CHUNK_SCENES.get(chunk_name, null)')
    if ($fixtureEntryGuardIndex -lt 0 -or
            $fixtureSceneLookupIndex -lt $fixtureEntryGuardIndex -or
            $ordinarySceneLookupIndex -lt $fixtureSceneLookupIndex) {
        Write-GateError 'The Web-only chunk lookup is no longer gated by a quarantined active entry.'
        exit 1
    }

    $mainMenuPath = Join-Path $ProjectPath 'scripts/ui/main_menu.gd'
    if (-not (Test-Path -LiteralPath $mainMenuPath -PathType Leaf)) {
        Write-GateError "Web fixture quarantine self-test could not find MainMenu: $mainMenuPath"
        exit 1
    }
    $mainMenuSource = Get-Content -LiteralPath $mainMenuPath -Raw
    $webQuerySetupSource = [regex]::Match(
        $mainMenuSource,
        '(?ms)^func\s+_setup_web_e2e_probe\b.*?(?=^(?:static\s+)?func\s+|\z)'
    ).Value
    $webResolverCallCount = [regex]::Matches(
        $mainMenuSource,
        'FragmentPreviewScript\.get_web_e2e_preview_entry\s*\('
    ).Count
    $webFixtureAssignmentCount = [regex]::Matches(
        $mainMenuSource,
        'FragmentPreviewScript\.menu_launch_entry\s*='
    ).Count
    if (-not $webQuerySetupSource.Contains(
                'if not OS.has_feature("web") or _web_query_value("e2e") != "1":') -or
            -not $webQuerySetupSource.Contains(
                'FragmentPreviewScript.get_web_e2e_preview_entry(requested_fragment)') -or
            -not $webQuerySetupSource.Contains(
                'FragmentPreviewScript.menu_launch_entry = requested_entry.duplicate(true)') -or
            $webResolverCallCount -ne 1 -or $webFixtureAssignmentCount -ne 1) {
        Write-GateError 'The Web fixture launch is no longer reachable exclusively through Web + ?e2e=1 MainMenu setup.'
        exit 1
    }
    foreach ($requiredQuarantineRuntimeToken in @(
        'webFixtureQuarantineViolations',
        'assertFixtureRequiresInitialWebE2EQuery',
        'ordinaryPickerState.ready'
    )) {
        if (-not $playwrightSpecSource.Contains($requiredQuarantineRuntimeToken)) {
            Write-GateError (
                "The Basin Web spec is missing fixture-quarantine assertion '$requiredQuarantineRuntimeToken'.")
            exit 1
        }
    }

    $webPersonaReporterPath = Join-Path $ProjectPath 'tests/web/persona-validation-reporter.mjs'
    if (-not (Test-Path -LiteralPath $webPersonaReporterPath -PathType Leaf)) {
        Write-GateError "Web tier-manifest self-test could not find the persona reporter: $webPersonaReporterPath"
        exit 1
    }
    $webPersonaReporterSource = Get-Content -LiteralPath $webPersonaReporterPath -Raw
    foreach ($requiredWebReporterToken in @(
        'REQUIRED_NON_PERSONA_TESTS',
        'Web persona trace refusal and input-ledger contract vectors',
        'Generated seed-5 Capbage HIDE roundtrip uses strict Web player observations',
        'Static Capbage-green source cannot self-attest a suppressed Web result pulse',
        'EXPECTED_TESTS.has(testCase.title)'
    )) {
        if (-not $webPersonaReporterSource.Contains($requiredWebReporterToken)) {
            Write-GateError (
                "Web tier-manifest self-test requires the reporter contract token '$requiredWebReporterToken'.")
            exit 1
        }
    }

    $bootstrapScene = Join-Path $RepoRoot 'to-rust-as-we-fall/scenes/system/test_bootstrap.tscn'
    $tokens = $null
    $parseErrors = $null
    $launcherAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath,
        [ref] $tokens,
        [ref] $parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        Write-GateError ("Native test bootstrap self-test could not parse the launcher:`n" +
            (($parseErrors | ForEach-Object { $_.Message }) -join "`n"))
        exit 1
    }

    $nativeHelperDefinitions = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-NativeGodotTest'
    }, $true))
    if ($nativeHelperDefinitions.Count -ne 1) {
        Write-GateError "Native test bootstrap self-test expected one Invoke-NativeGodotTest helper; observed $($nativeHelperDefinitions.Count)."
        exit 1
    }
    $nativeHelper = $nativeHelperDefinitions[0]
    $helperBootstrapLiterals = @($nativeHelper.Body.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $node.Value -eq 'res://scenes/system/test_bootstrap.tscn'
    }, $true))
    $helperChildCalls = @($nativeHelper.Body.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-GateChild'
    }, $true))
    if ($helperBootstrapLiterals.Count -ne 1 -or $helperChildCalls.Count -ne 1) {
        Write-GateError "Invoke-NativeGodotTest must inject the bootstrap exactly once and route through Invoke-GateChild exactly once."
        exit 1
    }
    $nativeHelperSource = $nativeHelper.Extent.Text
    if ($nativeHelperSource -notmatch
            'Resolve-WindowedGodotExecutable\s+-GodotExecutable\s+\$GodotExecutable' -or
            $nativeHelperSource -notmatch
            '-FilePath\s+\$nativeGodotExecutable' -or
            $nativeHelperSource -notmatch
            'if\s*\(\$env:OS\s+-eq\s+''Windows_NT''\)' -or
            $nativeHelperSource -notmatch
            'New-HiddenWindowHost[\s\S]*-RequireRenderWindow\s+\(\$LaunchMode\s+-eq\s+''Windowed''\)' -or
            $nativeHelperSource -notmatch
            '-WindowIsolation\s+\$windowHost') {
        Write-GateError (
            'Invoke-NativeGodotTest must bypass the console wrapper only for ' +
            'Windowed rendering while routing both Windows Headless and ' +
            'Windowed processes through private-desktop Job containment.')
        exit 1
    }
    foreach ($requiredNativeEnvironment in @('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME')) {
        if ($nativeHelperSource -notmatch ("'{0}'" -f $requiredNativeEnvironment)) {
            Write-GateError "Invoke-NativeGodotTest must isolate $requiredNativeEnvironment under the run artifact directory."
            exit 1
        }
    }
    if ($nativeHelperSource -notmatch '-Environment\s+\$nativeEnvironment') {
        Write-GateError 'Invoke-NativeGodotTest must pass its isolated native environment to Invoke-GateChild.'
        exit 1
    }

    $containedGodotDefinitions = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-ContainedGodotCommand'
    }, $true))
    if ($containedGodotDefinitions.Count -ne 1) {
        Write-GateError (
            'Contained-Godot self-test expected one arbitrary-command helper; ' +
            "observed $($containedGodotDefinitions.Count).")
        exit 1
    }
    $containedGodotSource = $containedGodotDefinitions[0].Extent.Text
    foreach ($requiredContainedGodotToken in @(
        'New-HiddenWindowHost -RequireRenderWindow $false',
        '-WindowIsolation $windowHost',
        'APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME'
    )) {
        if (-not $containedGodotSource.Contains($requiredContainedGodotToken)) {
            Write-GateError (
                "Contained-Godot helper is missing '$requiredContainedGodotToken'.")
            exit 1
        }
    }

    # Prove structurally that runtime dispatch consumes the same manifest that
    # the exact semantic checks above validate. A disconnected manifest would
    # otherwise let SelfTest stay green after the real calls were deleted.
    $manifestAssignments = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'script:GateTierManifest'
    }, $true))
    if ($manifestAssignments.Count -ne 1) {
        Write-GateError "Tier-manifest self-test expected one script:GateTierManifest assignment; observed $($manifestAssignments.Count)."
        exit 1
    }

    $preflightManifestAssignments = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'script:GatePreflightManifest'
    }, $true))
    if ($preflightManifestAssignments.Count -ne 1) {
        Write-GateError (
            'Preflight-manifest self-test expected one ' +
            'script:GatePreflightManifest assignment; observed ' +
            "$($preflightManifestAssignments.Count).")
        exit 1
    }

    $runtimeManifestLookups = @($launcherAst.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst] -or
                $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $node.Left.VariablePath.UserPath -ne 'tierDefinition') {
            return $false
        }
        return $null -ne $node.Right.Find({
            param($child)
            $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $child.VariablePath.UserPath -eq 'script:GateTierManifest'
        }, $true) -and $null -ne $node.Right.Find({
            param($child)
            $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $child.VariablePath.UserPath -eq 'activeTier'
        }, $true)
    }, $true))
    if ($runtimeManifestLookups.Count -ne 1) {
        Write-GateError "Tier-manifest self-test expected runtime to resolve tierDefinition from GateTierManifest and activeTier exactly once; observed $($runtimeManifestLookups.Count)."
        exit 1
    }

    $runtimePreflightManifestLookups = @($launcherAst.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst] -or
                $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $node.Left.VariablePath.UserPath -ne 'preflightInvocation') {
            return $false
        }
        return $null -ne $node.Right.Find({
            param($child)
            $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $child.VariablePath.UserPath -eq 'script:GatePreflightManifest'
        }, $true) -and $null -ne $node.Right.Find({
            param($child)
            $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $child.VariablePath.UserPath -eq 'preflightName'
        }, $true)
    }, $true))
    if ($runtimePreflightManifestLookups.Count -ne 1) {
        Write-GateError (
            'Preflight-manifest self-test expected runtime to resolve ' +
            'preflightInvocation exactly once; observed ' +
            "$($runtimePreflightManifestLookups.Count).")
        exit 1
    }

    $runtimeNativeCalls = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-NativeGodotTest'
    }, $true))
    $manifestRuntimeNativeCalls = @($runtimeNativeCalls | Where-Object {
        $_.Extent.Text -match '\$nativeInvocation\.'
    })
    $preflightRuntimeNativeCalls = @($runtimeNativeCalls | Where-Object {
        $_.Extent.Text -match '\$preflightInvocation\.'
    })
    $focusedHeadlessRuntimeNativeCalls = @($runtimeNativeCalls | Where-Object {
        $_.Extent.Text -match '\$FocusedHeadlessTest'
    })
    $focusedWindowedRuntimeNativeCalls = @($runtimeNativeCalls | Where-Object {
        $_.Extent.Text -match '\$FocusedWindowedTest'
    })
    if ($runtimeNativeCalls.Count -ne 4 -or
            $manifestRuntimeNativeCalls.Count -ne 1 -or
            $preflightRuntimeNativeCalls.Count -ne 1 -or
            $focusedHeadlessRuntimeNativeCalls.Count -ne 1 -or
            $focusedWindowedRuntimeNativeCalls.Count -ne 1) {
        Write-GateError (
            'Native runtime self-test expected exactly one shared-preflight, ' +
            'one tier-manifest, one strict focused-Headless, and one strict ' +
            'focused-Windowed Invoke-NativeGodotTest call; ' +
            "observed total=$($runtimeNativeCalls.Count), " +
            "preflight=$($preflightRuntimeNativeCalls.Count), " +
            "manifest=$($manifestRuntimeNativeCalls.Count), " +
            "focusedHeadless=$($focusedHeadlessRuntimeNativeCalls.Count), " +
            "focusedWindowed=$($focusedWindowedRuntimeNativeCalls.Count).")
        exit 1
    }
    $nativeInvocationMembers = @($manifestRuntimeNativeCalls[0].FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Expression.VariablePath.UserPath -eq 'nativeInvocation'
    }, $true) | ForEach-Object { $_.Member.Value })
    foreach ($requiredMember in @('Label', 'LaunchMode', 'EntryPoint', 'TestArguments')) {
        if ($requiredMember -notin $nativeInvocationMembers) {
            Write-GateError "Manifest-driven Invoke-NativeGodotTest does not consume nativeInvocation.$requiredMember."
            exit 1
        }
    }
    $preflightInvocationMembers = @($preflightRuntimeNativeCalls[0].FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Expression.VariablePath.UserPath -eq 'preflightInvocation'
    }, $true) | ForEach-Object { $_.Member.Value })
    foreach ($requiredMember in @('Label', 'LaunchMode', 'EntryPoint', 'TestArguments')) {
        if ($requiredMember -notin $preflightInvocationMembers) {
            Write-GateError (
                'Shared-preflight Invoke-NativeGodotTest does not consume ' +
                "preflightInvocation.$requiredMember.")
            exit 1
        }
    }
    if ($preflightRuntimeNativeCalls[0].Extent.StartOffset -ge
            $manifestRuntimeNativeCalls[0].Extent.StartOffset) {
        Write-GateError (
            'Shared agent-player input-boundary verification must run before ' +
            'tier-specific Native work.')
        exit 1
    }
    $preflightCompletionCalls = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Complete-RequiredInvocation' -and
            $null -ne $node.Find({
                param($child)
                $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $child.VariablePath.UserPath -eq 'preflightResult'
            }, $true)
    }, $true))
    if ($preflightCompletionCalls.Count -ne 1 -or
            $preflightCompletionCalls[0].Extent.StartOffset -le
                $preflightRuntimeNativeCalls[0].Extent.StartOffset -or
            $preflightCompletionCalls[0].Extent.StartOffset -ge
                $manifestRuntimeNativeCalls[0].Extent.StartOffset) {
        Write-GateError (
            'Shared agent-player input-boundary preflight must complete as a ' +
            'required invocation before tier dispatch exactly once.')
        exit 1
    }
    $focusedHeadlessRuntimeSource =
        $focusedHeadlessRuntimeNativeCalls[0].Extent.Text
    foreach ($requiredFocusedToken in @(
        "-LaunchMode 'Headless'",
        "-EntryPoint 'res://scenes/system/test_bootstrap.tscn'",
        "@(`$FocusedHeadlessTest, '--fail-on-skip')"
    )) {
        if (-not $focusedHeadlessRuntimeSource.Contains($requiredFocusedToken)) {
            Write-GateError (
                "Focused Headless dispatch is missing '$requiredFocusedToken'.")
            exit 1
        }
    }
    $focusedWindowedRuntimeSource =
        $focusedWindowedRuntimeNativeCalls[0].Extent.Text
    foreach ($requiredFocusedToken in @(
        "-LaunchMode 'Windowed'",
        "-EntryPoint 'res://scenes/system/test_bootstrap.tscn'",
        "@(`$FocusedWindowedTest, '--fail-on-skip')"
    )) {
        if (-not $focusedWindowedRuntimeSource.Contains($requiredFocusedToken)) {
            Write-GateError (
                "Focused Windowed dispatch is missing '$requiredFocusedToken'.")
            exit 1
        }
    }

    $webJourneyCalls = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-GateChild' -and
            $node.Extent.Text -match "'web-basin-player-journey'"
    }, $true))
    if ($webJourneyCalls.Count -ne 1) {
        Write-GateError "Tier-manifest self-test expected one Web Basin npm invocation; observed $($webJourneyCalls.Count)."
        exit 1
    }
    $webNpmScriptRefs = @($webJourneyCalls[0].FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Expression.VariablePath.UserPath -eq 'tierDefinition' -and
            $node.Member.Value -eq 'NpmScript'
    }, $true))
    if ($webNpmScriptRefs.Count -ne 1) {
        Write-GateError 'Web Basin npm invocation must consume tierDefinition.NpmScript exactly once.'
        exit 1
    }
    $webEnvironmentAssignments = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'playwrightEnvironment'
    }, $true))
    if ($webEnvironmentAssignments.Count -ne 1) {
        Write-GateError "Tier-manifest self-test expected one playwrightEnvironment assignment; observed $($webEnvironmentAssignments.Count)."
        exit 1
    }
    $webEnvironmentSource = $webEnvironmentAssignments[0].Extent.Text
    foreach ($requiredWebEnvironment in @(
        'TRAWF_WEB_ROOT', 'TRAWF_WEB_PORT', 'TRAWF_PLAYWRIGHT_OUTPUT_DIR',
        'TRAWF_GODOT_PATH', 'TRAWF_PROJECT_PATH',
        'TRAWF_POWERSHELL_PATH', 'TRAWF_TEST_GATE_LAUNCHER',
        'TRAWF_GATE_ARTIFACT_DIRECTORY'
    )) {
        if ($webEnvironmentSource -notmatch ("'{0}'" -f $requiredWebEnvironment)) {
            Write-GateError "The Web Basin runner must inject $requiredWebEnvironment for the persona reporter."
            exit 1
        }
    }
    $webJourneySource = $webJourneyCalls[0].Extent.Text
    if ($webJourneySource -notmatch '-Environment\s+\$playwrightEnvironment') {
        Write-GateError 'The Web Basin npm invocation must receive playwrightEnvironment.'
        exit 1
    }
    if ($webJourneySource -notmatch '\[Math\]::Min\(\$TimeoutSeconds,\s*1200\)') {
        Write-GateError 'The 2x2 Web persona invocation must have a bounded 1200-second child ceiling.'
        exit 1
    }
    $personaReporterPath = Join-Path $ProjectPath `
        'tests\web\persona-validation-reporter.mjs'
    $personaReporterSource = Get-Content -LiteralPath $personaReporterPath -Raw
    foreach ($requiredReporterToken in @(
        'persona_distillation_request_v1',
        'TRAWF_POWERSHELL_PATH',
        'TRAWF_TEST_GATE_LAUNCHER',
        'TRAWF_GATE_ARTIFACT_DIRECTORY',
        '-PersonaDistillationRequest'
    )) {
        if (-not $personaReporterSource.Contains($requiredReporterToken)) {
            Write-GateError (
                "Web persona reporter does not route distillation through '$requiredReporterToken'.")
            exit 1
        }
    }
    if ($personaReporterSource -match
            'runChild\(\s*godot\s*,\s*args') {
        Write-GateError (
            'Web persona reporter directly launches Godot instead of the ' +
            'tracked contained-Godot launcher.')
        exit 1
    }

    $crossPlatformDefinitions = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Invoke-CrossPlatformPersonaAggregation'
    }, $true))
    if ($crossPlatformDefinitions.Count -ne 1) {
        Write-GateError ("Cross-platform persona self-test expected one aggregation helper; " +
            "observed $($crossPlatformDefinitions.Count).")
        exit 1
    }
    $crossPlatformSource = $crossPlatformDefinitions[0].Extent.Text
    foreach ($requiredCrossPlatformSource in @(
        'native-user-data\windowed-persona-probe',
        'native-persona-trace-manifest.json',
        'playwright\persona-trace-manifest.json',
        '--build-native-manifest',
        'ConvertFrom-Json',
        '.traces',
        'Count -ne 4',
        'res://tools/distill_persona_decision_library.gd',
        '--trace=',
        'persona-decision-library.combined.preview.json',
        '--validate-combined',
        'persona-cross-platform-validation.json'
    )) {
        if (-not $crossPlatformSource.Contains($requiredCrossPlatformSource)) {
            Write-GateError "Cross-platform persona aggregation does not consume required artifact contract '$requiredCrossPlatformSource'."
            exit 1
        }
    }
    if ($crossPlatformSource.Contains('--in-place')) {
        Write-GateError 'Cross-platform persona aggregation must never mutate the canonical decision library in place.'
        exit 1
    }
    $crossPlatformRuntimeCalls = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-CrossPlatformPersonaAggregation'
    }, $true))
    if ($crossPlatformRuntimeCalls.Count -ne 1) {
        Write-GateError ("Cross-platform persona self-test expected one runtime aggregation call; " +
            "observed $($crossPlatformRuntimeCalls.Count).")
        exit 1
    }
    $launcherSource = $launcherAst.Extent.Text
    if ($launcherSource -notmatch 'Contains\(''Windowed''\)\s+-and\s+\$expandedTiers\.Contains\(''Web''\)') {
        Write-GateError 'Combined persona aggregation must run whenever both Windowed and Web tiers are requested.'
        exit 1
    }

    # The aggregation condition above is useful only if CI requests both tiers
    # from the same launcher process. Separate workflow steps create separate
    # run-owned artifact directories, so neither process can see the other
    # platform's four-trace manifest and the final 4+4 preview never runs.
    $releaseWorkflowPath = Join-Path $RepoRoot '.github/workflows/game-release-gate.yml'
    if (-not (Test-Path -LiteralPath $releaseWorkflowPath -PathType Leaf)) {
        Write-GateError "Release workflow does not exist: $releaseWorkflowPath"
        exit 1
    }
    $releaseWorkflowSource = Get-Content -LiteralPath $releaseWorkflowPath -Raw
    $combinedTierLiteral = '-Tier Windowed,Web'
    $combinedTierMatches = [regex]::Matches(
        $releaseWorkflowSource,
        '(?m)-Tier[ \t]+Windowed,Web(?=[ \t\r\n''"])'
    )
    if ($combinedTierMatches.Count -ne 1) {
        Write-GateError ("Release workflow must invoke exactly one combined Windowed,Web gate; observed {0}." -f
            $combinedTierMatches.Count)
        exit 1
    }
    foreach ($splitTierPattern in @(
        '(?m)-Tier[ \t]+Windowed(?!,Web)(?=[ \t\r\n''"])',
        '(?m)-Tier[ \t]+Web(?=[ \t\r\n''"])',
        '(?m)-Tier[ \t]+(?:Release|All)(?=[ \t\r\n''"])'
    )) {
        if ($releaseWorkflowSource -match $splitTierPattern) {
            Write-GateError 'Release workflow must not duplicate persona runs through a split Windowed, Web, Release, or All launcher invocation.'
            exit 1
        }
    }
    $combinedTierOffset = $releaseWorkflowSource.IndexOf(
        $combinedTierLiteral, [System.StringComparison]::Ordinal)
    $npmInstallOffset = $releaseWorkflowSource.IndexOf(
        'npm ci --no-audit --no-fund', [System.StringComparison]::Ordinal)
    $playwrightInstallOffset = $releaseWorkflowSource.IndexOf(
        'npx playwright install --with-deps chromium',
        [System.StringComparison]::Ordinal)
    if ($npmInstallOffset -lt 0 -or $playwrightInstallOffset -lt 0 -or
            $npmInstallOffset -ge $combinedTierOffset -or
            $playwrightInstallOffset -ge $combinedTierOffset) {
        Write-GateError 'The combined Windowed,Web invocation must run after the pinned Playwright dependencies are installed.'
        exit 1
    }
    $combinedWindowStart = [Math]::Max(0, $combinedTierOffset - 400)
    $combinedWindowLength = [Math]::Min(
        800, $releaseWorkflowSource.Length - $combinedWindowStart)
    $combinedWorkflowWindow = $releaseWorkflowSource.Substring(
        $combinedWindowStart, $combinedWindowLength)
    foreach ($requiredCombinedToken in @(
        'xvfb-run',
        'pwsh -NoProfile -Command',
        '-WebDependenciesReady'
    )) {
        if (-not $combinedWorkflowWindow.Contains($requiredCombinedToken)) {
            Write-GateError "Combined Windowed,Web workflow invocation is missing '$requiredCombinedToken'."
            exit 1
        }
    }

    # No runtime Godot command may use the ordinary child path. Tests use the
    # native-test helper; export and distillation use the arbitrary contained
    # helper. Both helpers establish private-desktop Job ownership on Windows.
    $godotChildCalls = @($launcherAst.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst] -or
                $node.GetCommandName() -ne 'Invoke-GateChild') {
            return $false
        }
        return $null -ne $node.Find({
            param($child)
            $child -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $child.VariablePath.UserPath -in @(
                    'godot', 'GodotExecutable', 'nativeGodotExecutable')
        }, $true)
    }, $true))
    foreach ($godotChildCall in $godotChildCalls) {
        $ancestor = $godotChildCall.Parent
        while ($null -ne $ancestor -and
                $ancestor -isnot
                    [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $ancestor = $ancestor.Parent
        }
        $owningFunction = if ($null -eq $ancestor) { '' } else { $ancestor.Name }
        if ($owningFunction -notin @(
                'Invoke-NativeGodotTest',
                'Invoke-ContainedGodotCommand')) {
            Write-GateError (
                'A runtime Godot command bypasses private-desktop Job ' +
                "containment (owner='$owningFunction'): " +
                $godotChildCall.Extent.Text)
            exit 1
        }
    }
    $containedRuntimeCalls = @($launcherAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Invoke-ContainedGodotCommand'
    }, $true))
    foreach ($requiredContainedLabel in @(
        'web-export-release',
        'persona-cross-platform-distillation-preview',
        'web-persona-distillation-preview',
        'generated-baseline-regeneration',
        'generated-replay-export',
        'generated-replay-freshness'
    )) {
        $matchingContainedCalls = @($containedRuntimeCalls | Where-Object {
            $_.Extent.Text.Contains($requiredContainedLabel)
        })
        if ($matchingContainedCalls.Count -ne 1) {
            Write-GateError (
                "Contained-Godot runtime call '$requiredContainedLabel' " +
                "expected once; observed $($matchingContainedCalls.Count).")
            exit 1
        }
    }
    if (-not (Test-Path -LiteralPath $bootstrapScene -PathType Leaf)) {
        Write-GateError "Native test bootstrap scene does not exist: $bootstrapScene"
        exit 1
    }
    Write-Host (
        '[GATE] SELF-TEST PASS: exit propagation, required-skip, timeout, ' +
        'runtime-fault, strict focused Headless/Windowed validation and mutual ' +
        'exclusion, contained native/window isolation, forbidden-input scans, ' +
        'manifest routing, CI topology, and cross-platform persona-preview ' +
        'contracts passed.')
    exit 0
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    Write-GateError "Godot project directory does not exist: $ProjectPath"
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'project.godot') -PathType Leaf)) {
    Write-GateError "project.godot not found under: $ProjectPath"
    exit 2
}

$expandedTiers = New-Object System.Collections.Generic.List[string]
foreach ($requestedTier in $Tier) {
    if ($requestedTier -in @('Release', 'All')) {
        foreach ($releaseTier in $script:GateTierManifest.Keys) {
            if (-not $expandedTiers.Contains($releaseTier)) {
                [void] $expandedTiers.Add($releaseTier)
            }
        }
    } elseif (-not $expandedTiers.Contains($requestedTier)) {
        [void] $expandedTiers.Add($requestedTier)
    }
}

$godot = Resolve-GodotExecutable
Write-Host "[GATE] Repository: $RepoRoot"
Write-Host "[GATE] Project:    $ProjectPath"
Write-Host "[GATE] Godot:     $godot"
Write-Host "[GATE] Tiers:     $($expandedTiers -join ', ')"
Write-Host "[GATE] Artifacts: $RunArtifactDirectory"

if ($script:GeneratedBaselineRegenerationRequested) {
    $regenerationResult = Invoke-ContainedGodotCommand `
        -Label 'generated-baseline-regeneration' `
        -GodotExecutable $godot -Arguments @(
            '--headless', '--path', $ProjectPath,
            '--script', 'res://tools/regenerate_generated_stretch_specs.gd'
        ) -WorkingDirectory $ProjectPath `
        -ChildTimeoutSeconds ([Math]::Min($TimeoutSeconds, 1200))
    Complete-RequiredInvocation $regenerationResult

    $replayExportResult = Invoke-ContainedGodotCommand `
        -Label 'generated-replay-export' `
        -GodotExecutable $godot -Arguments @(
            '--headless', '--path', $ProjectPath,
            '--script', 'res://tools/export_stretch_replays.gd'
        ) -WorkingDirectory $ProjectPath `
        -ChildTimeoutSeconds ([Math]::Min($TimeoutSeconds, 1200))
    Complete-RequiredInvocation $replayExportResult

    $freshnessResult = Invoke-ContainedGodotCommand `
        -Label 'generated-replay-freshness' `
        -GodotExecutable $godot -Arguments @(
            '--headless', '--path', $ProjectPath,
            'res://scenes/system/test_bootstrap.tscn', '--',
            '--test-generated-replay', '--fail-on-skip'
        ) -WorkingDirectory $ProjectPath `
        -ChildTimeoutSeconds ([Math]::Min($TimeoutSeconds, 1200))
    Complete-RequiredInvocation $freshnessResult
    Write-Host (
        "`n[GATE] PASS: all nine generated baselines, game replays, and " +
        'level-sketch replay mirrors were regenerated and verified under ' +
        'native containment.')
    exit 0
}

if ($script:FocusedHeadlessRequested) {
    $focusedLabel = 'focused-headless-' +
        $FocusedHeadlessTest.Substring('--test-'.Length)
    $focusedResult = Invoke-NativeGodotTest -Label $focusedLabel `
        -GodotExecutable $godot -LaunchMode 'Headless' `
        -EntryPoint 'res://scenes/system/test_bootstrap.tscn' `
        -TestArguments @($FocusedHeadlessTest, '--fail-on-skip')
    Complete-RequiredInvocation $focusedResult
    Write-Host (
        "`n[GATE] PASS: focused Headless diagnostic completed through " +
        'test_bootstrap with fail-on-skip and native containment.')
    exit 0
}

if ($script:FocusedWindowedRequested) {
    $focusedLabel = 'focused-windowed-' +
        $FocusedWindowedTest.Substring('--test-'.Length)
    $focusedResult = Invoke-NativeGodotTest -Label $focusedLabel `
        -GodotExecutable $godot -LaunchMode 'Windowed' `
        -EntryPoint 'res://scenes/system/test_bootstrap.tscn' `
        -TestArguments @($FocusedWindowedTest, '--fail-on-skip')
    Complete-RequiredInvocation $focusedResult
    Write-Host (
        "`n[GATE] PASS: focused Windowed diagnostic completed through " +
        'test_bootstrap with fail-on-skip and native containment.')
    exit 0
}

if ($script:PersonaDistillationRequested) {
    try {
        $distillationRequest = Read-PersonaDistillationRequest `
            -RequestPath $PersonaDistillationRequest
    } catch {
        Write-GateError $_.Exception.Message
        exit 64
    }
    $containedDistillationArguments = @(
        '--headless', '--path', $ProjectPath,
        '--script', 'res://tools/distill_persona_decision_library.gd', '--'
    )
    foreach ($tracePath in $distillationRequest.TracePaths) {
        $containedDistillationArguments +=
            "--trace=$($tracePath.Replace('\', '/'))"
    }
    $containedDistillationArguments +=
        "--output=$($distillationRequest.OutputPath.Replace('\', '/'))"
    $containedDistillationResult = Invoke-ContainedGodotCommand `
        -Label 'web-persona-distillation-preview' `
        -GodotExecutable $godot -Arguments $containedDistillationArguments `
        -WorkingDirectory $ProjectPath -ChildTimeoutSeconds 240
    Complete-RequiredInvocation $containedDistillationResult
    if (-not (Test-Path -LiteralPath $distillationRequest.OutputPath `
                -PathType Leaf)) {
        Write-GateError (
            'Contained persona distillation completed without its requested output.')
        exit 87
    }
    Write-Host (
        "`n[GATE] PASS: contained persona distillation wrote " +
        $distillationRequest.OutputPath)
    exit 0
}

foreach ($preflightName in $script:GatePreflightManifest.Keys) {
    $preflightInvocation = $script:GatePreflightManifest[$preflightName]
    $preflightResult = Invoke-NativeGodotTest `
        -Label $preflightInvocation.Label `
        -GodotExecutable $godot `
        -LaunchMode $preflightInvocation.LaunchMode `
        -EntryPoint $preflightInvocation.EntryPoint `
        -TestArguments @($preflightInvocation.TestArguments)
    Complete-RequiredInvocation $preflightResult
}

foreach ($activeTier in $expandedTiers) {
    $tierDefinition = $script:GateTierManifest[$activeTier]
    if ($null -eq $tierDefinition) {
        Write-GateError "No tier manifest entry exists for requested tier '$activeTier'."
        exit 2
    }
    switch ($tierDefinition.Kind) {
        'Native' {
            foreach ($nativeInvocation in @($tierDefinition.Invocations)) {
                $result = Invoke-NativeGodotTest -Label $nativeInvocation.Label `
                    -GodotExecutable $godot -LaunchMode $nativeInvocation.LaunchMode `
                    -EntryPoint $nativeInvocation.EntryPoint `
                    -TestArguments @($nativeInvocation.TestArguments)
                Complete-RequiredInvocation $result
            }
        }
        'Web' {
            $webRoot = Join-Path $RunArtifactDirectory 'web-export'
            New-Item -ItemType Directory -Force -Path $webRoot | Out-Null
            $webIndex = Join-Path $webRoot 'index.html'
            $exportResult = Invoke-ContainedGodotCommand `
                -Label 'web-export-release' -GodotExecutable $godot -Arguments @(
                '--headless', '--path', $ProjectPath,
                '--export-release', 'Web', $webIndex
            )
            Complete-RequiredInvocation $exportResult

            foreach ($requiredArtifact in @('index.html', 'index.js', 'index.pck', 'index.wasm')) {
                $artifactPath = Join-Path $webRoot $requiredArtifact
                if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
                    Write-GateError "Web export succeeded but required artifact is missing: $artifactPath"
                    exit 87
                }
            }

            $node = Resolve-Executable -Kind 'Node.js 22+' -Candidates @($env:NODE_BIN, 'node')
            $npm = Resolve-NpmExecutable
            if (-not $WebDependenciesReady) {
                $npmInstallResult = Invoke-GateChild -Label 'web-npm-ci' -FilePath $npm -Arguments @(
                    'ci', '--no-audit', '--no-fund'
                ) -WorkingDirectory $ProjectPath
                Complete-RequiredInvocation $npmInstallResult

                $npx = Resolve-NpxExecutable
                $browserInstallResult = Invoke-GateChild -Label 'web-playwright-install-chromium' -FilePath $npx -Arguments @(
                    'playwright', 'install', 'chromium'
                ) -WorkingDirectory $ProjectPath
                Complete-RequiredInvocation $browserInstallResult
            }

            $playwrightOutput = Join-Path $RunArtifactDirectory 'playwright'
            New-Item -ItemType Directory -Force -Path $playwrightOutput | Out-Null
            $playwrightPort = Get-AvailableTcpPort
            $containedGodotPowerShell = Resolve-PowerShellExecutable
            $playwrightEnvironment = @{
                'TRAWF_WEB_ROOT' = $webRoot
                'TRAWF_WEB_PORT' = $playwrightPort.ToString()
                'TRAWF_PLAYWRIGHT_OUTPUT_DIR' = $playwrightOutput
                'TRAWF_GODOT_PATH' = $godot
                'TRAWF_PROJECT_PATH' = $ProjectPath
                'TRAWF_POWERSHELL_PATH' = $containedGodotPowerShell
                'TRAWF_TEST_GATE_LAUNCHER' = $PSCommandPath
                'TRAWF_GATE_ARTIFACT_DIRECTORY' = $RunArtifactDirectory
            }
            $basinWebResult = Invoke-GateChild -Label 'web-basin-player-journey' -FilePath $npm -Arguments @(
                'run', $tierDefinition.NpmScript
            ) -WorkingDirectory $ProjectPath -Environment $playwrightEnvironment `
                -ChildTimeoutSeconds ([Math]::Min($TimeoutSeconds, 1200))
            Complete-RequiredInvocation $basinWebResult

            $browserProbe = Invoke-GateChild -Label 'web-playwright-browser-path' -FilePath $node -Arguments @(
                '-e', "process.stdout.write(require('@playwright/test').chromium.executablePath())"
            ) -WorkingDirectory $ProjectPath -EchoOutput $false -ChildTimeoutSeconds 30
            Complete-RequiredInvocation $browserProbe
            $playwrightBrowser = $browserProbe.Stdout.Trim()
            $browser = Resolve-BrowserExecutable -AdditionalCandidates @($playwrightBrowser)
            $smokeScript = Join-Path $RepoRoot 'scripts/web-smoke.mjs'
            $smokeResult = Invoke-GateChild -Label 'web-browser-smoke' -FilePath $node -Arguments @(
                $smokeScript,
                '--root', $webRoot,
                '--browser', $browser,
                '--timeout-seconds', ([Math]::Min($TimeoutSeconds, 600)).ToString(),
                '--screenshot', (Join-Path $RunArtifactDirectory 'web-smoke.png'),
                '--report', (Join-Path $RunArtifactDirectory 'web-smoke.json')
            ) -ChildTimeoutSeconds ([Math]::Min($TimeoutSeconds + 30, 630))
            Complete-RequiredInvocation $smokeResult
        }
        default {
            Write-GateError "Unsupported tier kind '$($tierDefinition.Kind)' for '$activeTier'."
            exit 2
        }
    }
}

if ($expandedTiers.Contains('Windowed') -and $expandedTiers.Contains('Web')) {
    $personaAggregationNode = Resolve-Executable -Kind 'Node.js 22+' -Candidates @(
        $env:NODE_BIN,
        'node'
    )
    Invoke-CrossPlatformPersonaAggregation -GodotExecutable $godot `
        -NodeExecutable $personaAggregationNode
}

Write-Host "`n[GATE] PASS: all requested tiers completed without failures or skips."
exit 0
