#requires -Version 5.1

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Run')]
    [ValidateNotNullOrEmpty()]
    [string] $GateRunDirectory,

    [Parameter(Mandatory = $true, ParameterSetName = 'Run')]
    [ValidateNotNullOrEmpty()]
    [string] $GodotPath,

    [Parameter(ParameterSetName = 'Run')]
    [switch] $Promote,

    [Parameter(Mandatory = $true, ParameterSetName = 'SelfTest')]
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:ProjectRoot = Join-Path $script:RepoRoot 'to-rust-as-we-fall'
$script:CanonicalLibraryPath = Join-Path $script:ProjectRoot 'data\playthroughs\decision_library.json'
$script:CohortArchiveRoot = Join-Path $script:ProjectRoot 'data\playthroughs\decision_traces\cohorts'
$script:PathComparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    [System.StringComparison]::OrdinalIgnoreCase
} else {
    [System.StringComparison]::Ordinal
}
$script:PathComparer = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    [System.StringComparer]::OrdinalIgnoreCase
} else {
    [System.StringComparer]::Ordinal
}

function Get-ExistingPath {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][ValidateSet('Leaf', 'Container')][string] $PathType,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType $PathType)) {
        throw "$Description does not exist as a $PathType`: $Path"
    }
    return [System.IO.Path]::GetFullPath((Get-Item -LiteralPath $Path -Force).FullName)
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($rootPrefix, $script:PathComparison)
}

function Assert-SamePath {
    param(
        [Parameter(Mandatory = $true)][string] $Actual,
        [Parameter(Mandatory = $true)][string] $Expected,
        [Parameter(Mandatory = $true)][string] $Description
    )

    $actualFull = [System.IO.Path]::GetFullPath($Actual)
    $expectedFull = [System.IO.Path]::GetFullPath($Expected)
    if (-not $actualFull.Equals($expectedFull, $script:PathComparison)) {
        throw "$Description is not bound to this gate run. Expected '$expectedFull', got '$actualFull'."
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Description
    )

    try {
        $document = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw "$Description is not valid JSON: $Path. $($_.Exception.Message)"
    }
    if ($null -eq $document -or $document -is [System.Array]) {
        throw "$Description must contain one JSON object: $Path"
    }
    return $document
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)] $Document,
        [Parameter(Mandatory = $true)][string] $Path
    )

    $json = $Document | ConvertTo-Json -Depth 100
    [System.IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false))
}

function Assert-GreenCombinedReport {
    param(
        [Parameter(Mandatory = $true)] $Report,
        [Parameter(Mandatory = $true)][string] $NativeManifestPath,
        [Parameter(Mandatory = $true)][string] $WebManifestPath,
        [Parameter(Mandatory = $true)][string] $PreviewPath,
        [Parameter(Mandatory = $true)][string] $Description
    )

    if ([string]$Report.schema -ne 'persona_cross_platform_validation_v1' -or
        $Report.passed -ne $true -or
        [int]$Report.issue_count -ne 0 -or
        @($Report.issues).Count -ne 0) {
        throw "$Description is not a green persona_cross_platform_validation_v1 report."
    }
    Assert-SamePath -Actual ([string]$Report.native_manifest) `
        -Expected $NativeManifestPath -Description "$Description native manifest"
    Assert-SamePath -Actual ([string]$Report.web_manifest) `
        -Expected $WebManifestPath -Description "$Description Web manifest"
    Assert-SamePath -Actual ([string]$Report.combined_preview) `
        -Expected $PreviewPath -Description "$Description combined preview"
}

function Get-ValidatedTraceMembers {
    param(
        [Parameter(Mandatory = $true)] $NativeArtifact,
        [Parameter(Mandatory = $true)] $WebArtifact,
        [Parameter(Mandatory = $true)][string] $GateRunRoot
    )

    $members = [System.Collections.Generic.List[object]]::new()
    $artifactDefinitions = @(
        [pscustomobject]@{
            Artifact = $NativeArtifact
            Platform = 'native'
            Schema = 'persona_native_trace_artifact_manifest_v1'
        },
        [pscustomobject]@{
            Artifact = $WebArtifact
            Platform = 'web'
            Schema = 'persona_web_trace_artifact_manifest_v1'
        }
    )

    foreach ($definition in $artifactDefinitions) {
        $artifact = $definition.Artifact
        $platform = [string]$definition.Platform
        if ([string]$artifact.schema -ne [string]$definition.Schema) {
            throw "$platform artifact schema is invalid."
        }
        $manifest = $artifact.invocation_manifest
        if ($null -eq $manifest -or
            [string]$manifest.schema -ne 'persona_strict_invocation_manifest_v1' -or
            $manifest.passed -ne $true -or
            [int]$manifest.failure_count -ne 0 -or
            @($manifest.failures).Count -ne 0 -or
            [string]$manifest.execution_platform -ne $platform -or
            [string]$manifest.fragment_id -ne 'basin_fill_proof' -or
            [int]$manifest.cohort_size -ne 4 -or
            @($manifest.members).Count -ne 4 -or
            @($manifest.expected_members).Count -ne 4) {
            throw "$platform invocation manifest is not the exact green Basin cohort."
        }
        if ([string]::IsNullOrWhiteSpace([string]$artifact.invocation_id) -or
            [string]$artifact.invocation_id -ne [string]$manifest.invocation_id -or
            [string]$artifact.invocation_manifest_hash -notmatch '^[a-f0-9]{64}$') {
            throw "$platform artifact is not bound to its invocation manifest."
        }

        $traces = @($artifact.traces)
        if ($traces.Count -ne 4) {
            throw "$platform artifact identifies $($traces.Count) traces; expected exactly 4."
        }
        foreach ($trace in $traces) {
            if ([string]$trace.execution_platform -ne $platform -or
                [string]$trace.fragment_id -ne 'basin_fill_proof' -or
                [string]$trace.persona -notin @('dean_takahashi', 'eazy_speezy') -or
                [int]$trace.repeat_index -notin @(0, 1)) {
                throw "$platform artifact contains an unexpected persona/repeat member."
            }
            if ([string]::IsNullOrWhiteSpace([string]$trace.trace_id)) {
                throw "$platform artifact contains a trace without a trace_id."
            }
            if ([string]::IsNullOrWhiteSpace([string]$trace.run_id)) {
                throw "$platform artifact contains a trace without a run_id."
            }
            if ([string]$trace.file_sha256 -notmatch '^[a-f0-9]{64}$') {
                throw "$platform trace '$($trace.trace_id)' has an invalid file digest."
            }
            if ([string]$trace.content_fingerprint_schema -ne 'authored_fragment_resource_bytes_v1' -or
                [string]$trace.content_fingerprint -notmatch '^[a-f0-9]{64}$' -or
                [string]$trace.gameplay_build_fingerprint_schema -ne 'gameplay_build_resource_set_bytes_v1' -or
                [string]$trace.gameplay_build_fingerprint -notmatch '^[a-f0-9]{64}$') {
                throw "$platform trace '$($trace.trace_id)' has an invalid content/build identity."
            }

            $tracePath = Get-ExistingPath -Path ([string]$trace.path) -PathType Leaf `
                -Description "$platform primary trace"
            if (-not (Test-PathWithinRoot -Path $tracePath -Root $GateRunRoot)) {
                throw "$platform primary trace is outside the selected gate run: $tracePath"
            }
            if ([System.IO.Path]::GetExtension($tracePath) -ne '.jsonl') {
                throw "$platform primary trace is not JSONL: $tracePath"
            }
            $actualDigest = Get-Sha256 -Path $tracePath
            if ($actualDigest -ne [string]$trace.file_sha256) {
                throw "$platform primary trace digest changed: $tracePath"
            }
            $members.Add([pscustomobject]@{
                ExecutionPlatform = $platform
                Persona = [string]$trace.persona
                RepeatIndex = [int]$trace.repeat_index
                TraceId = [string]$trace.trace_id
                RunId = [string]$trace.run_id
                ContentIdentity = ('{0}|{1}' -f `
                    [string]$trace.content_fingerprint_schema,
                    [string]$trace.content_fingerprint)
                GameplayBuildIdentity = ('{0}|{1}' -f `
                    [string]$trace.gameplay_build_fingerprint_schema,
                    [string]$trace.gameplay_build_fingerprint)
                SourcePath = $tracePath
                FileSha256 = $actualDigest
                ArchivedPath = ''
                ArchivedRelativePath = ''
            })
        }
    }

    if ($members.Count -ne 8) {
        throw "Combined artifacts identify $($members.Count) traces; expected exactly 8."
    }

    $expectedMatrix = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($platform in @('native', 'web')) {
        foreach ($persona in @('dean_takahashi', 'eazy_speezy')) {
            foreach ($repeatIndex in @(0, 1)) {
                [void]$expectedMatrix.Add("$platform|$persona|$repeatIndex")
            }
        }
    }
    $actualMatrix = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $canonicalPaths = [System.Collections.Generic.HashSet[string]]::new($script:PathComparer)
    $traceIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $runIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $fileDigests = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $contentIdentities = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $buildIdentities = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($member in $members) {
        $matrixKey = '{0}|{1}|{2}' -f $member.ExecutionPlatform, $member.Persona, $member.RepeatIndex
        if (-not $actualMatrix.Add($matrixKey)) {
            throw "Duplicate cohort matrix member: $matrixKey"
        }
        if (-not $canonicalPaths.Add([string]$member.SourcePath)) {
            throw "Two manifest entries resolve to the same canonical primary path: $($member.SourcePath)"
        }
        if (-not $traceIds.Add([string]$member.TraceId)) {
            throw "Duplicate primary trace_id: $($member.TraceId)"
        }
        if (-not $runIds.Add([string]$member.RunId)) {
            throw "Duplicate primary run_id: $($member.RunId)"
        }
        if (-not $fileDigests.Add([string]$member.FileSha256)) {
            throw "Duplicate primary file_sha256: $($member.FileSha256)"
        }
        [void]$contentIdentities.Add([string]$member.ContentIdentity)
        [void]$buildIdentities.Add([string]$member.GameplayBuildIdentity)
    }
    if (-not $actualMatrix.SetEquals($expectedMatrix)) {
        throw 'Combined artifacts do not identify the exact native/web Dean/Eazy repeat-0/repeat-1 matrix.'
    }
    if ($contentIdentities.Count -ne 1 -or $buildIdentities.Count -ne 1) {
        throw 'Combined artifacts do not share one authored-content and gameplay-build identity.'
    }

    return @($members | Sort-Object ExecutionPlatform, Persona, RepeatIndex)
}

function Test-FilesByteIdentical {
    param(
        [Parameter(Mandatory = $true)][string] $LeftPath,
        [Parameter(Mandatory = $true)][string] $RightPath
    )

    $leftInfo = Get-Item -LiteralPath $LeftPath
    $rightInfo = Get-Item -LiteralPath $RightPath
    if ($leftInfo.Length -ne $rightInfo.Length) {
        return $false
    }
    $leftStream = [System.IO.File]::OpenRead($leftInfo.FullName)
    $rightStream = [System.IO.File]::OpenRead($rightInfo.FullName)
    try {
        $leftBuffer = [byte[]]::new(65536)
        $rightBuffer = [byte[]]::new(65536)
        while ($true) {
            $leftCount = $leftStream.Read($leftBuffer, 0, $leftBuffer.Length)
            $rightCount = $rightStream.Read($rightBuffer, 0, $rightBuffer.Length)
            if ($leftCount -ne $rightCount) {
                return $false
            }
            if ($leftCount -eq 0) {
                return $true
            }
            for ($index = 0; $index -lt $leftCount; $index += 1) {
                if ($leftBuffer[$index] -ne $rightBuffer[$index]) {
                    return $false
                }
            }
        }
    } finally {
        $leftStream.Dispose()
        $rightStream.Dispose()
    }
}

function Copy-ArchiveInputs {
    param(
        [Parameter(Mandatory = $true)][object[]] $Members,
        [Parameter(Mandatory = $true)][string] $NativeManifestPath,
        [Parameter(Mandatory = $true)][string] $WebManifestPath,
        [Parameter(Mandatory = $true)][string] $CombinedReportPath,
        [Parameter(Mandatory = $true)][string] $CombinedPreviewPath,
        [Parameter(Mandatory = $true)][string] $CanonicalLibraryPath,
        [Parameter(Mandatory = $true)][string] $ArchiveDirectory
    )

    New-Item -ItemType Directory -Path $ArchiveDirectory -ErrorAction Stop | Out-Null
    $preimagePath = Join-Path $ArchiveDirectory 'decision_library.preimage.json'
    $sourceNativeManifestPath = Join-Path $ArchiveDirectory 'native-persona-trace-manifest.source.json'
    $sourceWebManifestPath = Join-Path $ArchiveDirectory 'web-persona-trace-manifest.source.json'
    $sourceReportPath = Join-Path $ArchiveDirectory 'persona-cross-platform-validation.source.json'
    $sourcePreviewPath = Join-Path $ArchiveDirectory 'persona-decision-library.combined.preview.source.json'
    Copy-Item -LiteralPath $CanonicalLibraryPath -Destination $preimagePath -ErrorAction Stop
    Copy-Item -LiteralPath $NativeManifestPath -Destination $sourceNativeManifestPath -ErrorAction Stop
    Copy-Item -LiteralPath $WebManifestPath -Destination $sourceWebManifestPath -ErrorAction Stop
    Copy-Item -LiteralPath $CombinedReportPath -Destination $sourceReportPath -ErrorAction Stop
    Copy-Item -LiteralPath $CombinedPreviewPath -Destination $sourcePreviewPath -ErrorAction Stop

    $memberBySourcePath = [System.Collections.Generic.Dictionary[string, object]]::new(
        $script:PathComparer)
    foreach ($member in $Members) {
        $traceDirectory = Join-Path $ArchiveDirectory ('traces\{0}' -f $member.ExecutionPlatform)
        New-Item -ItemType Directory -Path $traceDirectory -Force | Out-Null
        $relativePath = 'traces/{0}/{1}' -f $member.ExecutionPlatform,
            ([System.IO.Path]::GetFileName([string]$member.SourcePath))
        $archivedPath = Join-Path $ArchiveDirectory ($relativePath.Replace(
            '/', [System.IO.Path]::DirectorySeparatorChar))
        if (Test-Path -LiteralPath $archivedPath) {
            throw "Archive trace filename collision: $archivedPath"
        }
        Copy-Item -LiteralPath $member.SourcePath -Destination $archivedPath -ErrorAction Stop
        if ((Get-Sha256 -Path $archivedPath) -ne [string]$member.FileSha256 -or
            -not (Test-FilesByteIdentical -LeftPath $member.SourcePath -RightPath $archivedPath)) {
            throw "Archived trace is not byte-identical to its manifest primary: $archivedPath"
        }
        $member.ArchivedPath = [System.IO.Path]::GetFullPath($archivedPath)
        $member.ArchivedRelativePath = $relativePath
        $memberBySourcePath.Add([string]$member.SourcePath, $member)
    }

    $rebasedNativeManifest = Read-JsonFile -Path $NativeManifestPath `
        -Description 'native artifact manifest'
    $rebasedWebManifest = Read-JsonFile -Path $WebManifestPath `
        -Description 'Web artifact manifest'
    foreach ($artifact in @($rebasedNativeManifest, $rebasedWebManifest)) {
        foreach ($trace in @($artifact.traces)) {
            $sourcePath = Get-ExistingPath -Path ([string]$trace.path) -PathType Leaf `
                -Description 'manifest primary trace'
            if (-not $memberBySourcePath.ContainsKey($sourcePath)) {
                throw "Cannot rebase unvalidated manifest trace: $sourcePath"
            }
            $trace.path = [string]$memberBySourcePath[$sourcePath].ArchivedPath
        }
    }
    $rebasedNativeManifestPath = Join-Path $ArchiveDirectory 'native-persona-trace-manifest.archived.json'
    $rebasedWebManifestPath = Join-Path $ArchiveDirectory 'web-persona-trace-manifest.archived.json'
    Write-JsonFile -Document $rebasedNativeManifest -Path $rebasedNativeManifestPath
    Write-JsonFile -Document $rebasedWebManifest -Path $rebasedWebManifestPath

    return [pscustomobject]@{
        PreimagePath = $preimagePath
        SourceNativeManifestPath = $sourceNativeManifestPath
        SourceWebManifestPath = $sourceWebManifestPath
        SourceReportPath = $sourceReportPath
        SourcePreviewPath = $sourcePreviewPath
        RebasedNativeManifestPath = $rebasedNativeManifestPath
        RebasedWebManifestPath = $rebasedWebManifestPath
        Members = $Members
    }
}

function Invoke-AtomicFileReplace {
    param(
        [Parameter(Mandatory = $true)][string] $CandidatePath,
        [Parameter(Mandatory = $true)][string] $DestinationPath,
        [Parameter(Mandatory = $true)][string] $BackupPath,
        [Parameter(Mandatory = $true)][string] $Token
    )

    if (Test-Path -LiteralPath $BackupPath) {
        throw "Atomic replacement backup already exists: $BackupPath"
    }
    $destinationDirectory = Split-Path $DestinationPath -Parent
    if ([System.IO.Path]::GetPathRoot($destinationDirectory) -ne
        [System.IO.Path]::GetPathRoot((Split-Path $BackupPath -Parent))) {
        throw 'Atomic replacement destination and backup must be on the same volume.'
    }
    $safeToken = $Token -replace '[^A-Za-z0-9._-]', '_'
    $temporaryPath = Join-Path $destinationDirectory ".persona-library-$safeToken-$PID.tmp"
    if (Test-Path -LiteralPath $temporaryPath) {
        throw "Atomic replacement temporary path already exists: $temporaryPath"
    }
    Copy-Item -LiteralPath $CandidatePath -Destination $temporaryPath -ErrorAction Stop
    try {
        [System.IO.File]::Replace($temporaryPath, $DestinationPath, $BackupPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Invoke-VerifiedCanonicalRollback {
    param(
        [Parameter(Mandatory = $true)][string] $RollbackSourcePath,
        [Parameter(Mandatory = $true)][string] $DestinationPath,
        [Parameter(Mandatory = $true)][string] $WorkDirectory,
        [Parameter(Mandatory = $true)][string] $ExpectedSha256,
        [Parameter(Mandatory = $true)][string] $Token
    )

    $rollbackSource = Get-ExistingPath -Path $RollbackSourcePath -PathType Leaf `
        -Description 'captured canonical rollback source'
    if ((Get-Sha256 -Path $rollbackSource) -ne $ExpectedSha256) {
        throw 'Captured canonical rollback source changed before rollback.'
    }

    $safeToken = $Token -replace '[^A-Za-z0-9._-]', '_'
    $retainedSourcePath = Join-Path $WorkDirectory `
        "decision_library.$safeToken.rollback-source.json"
    $failedPostimagePath = Join-Path $WorkDirectory `
        "decision_library.$safeToken.failed-postimage.json"
    foreach ($reservedPath in @($retainedSourcePath, $failedPostimagePath)) {
        if (Test-Path -LiteralPath $reservedPath) {
            throw "Rollback forensic path already exists: $reservedPath"
        }
    }

    # Retain a separate byte-exact source so File.Replace semantics can never
    # consume the only copy used to verify the restored destination.
    Copy-Item -LiteralPath $rollbackSource -Destination $retainedSourcePath `
        -ErrorAction Stop
    if ((Get-Sha256 -Path $retainedSourcePath) -ne $ExpectedSha256 -or
        -not (Test-FilesByteIdentical -LeftPath $rollbackSource `
            -RightPath $retainedSourcePath)) {
        throw 'Could not retain a byte-exact canonical rollback source.'
    }

    Invoke-AtomicFileReplace -CandidatePath $retainedSourcePath `
        -DestinationPath $DestinationPath -BackupPath $failedPostimagePath `
        -Token "$safeToken-restore"

    if (-not (Test-Path -LiteralPath $rollbackSource -PathType Leaf) -or
        -not (Test-Path -LiteralPath $retainedSourcePath -PathType Leaf) -or
        (Get-Sha256 -Path $rollbackSource) -ne $ExpectedSha256 -or
        (Get-Sha256 -Path $retainedSourcePath) -ne $ExpectedSha256 -or
        (Get-Sha256 -Path $DestinationPath) -ne $ExpectedSha256 -or
        -not (Test-FilesByteIdentical -LeftPath $DestinationPath `
            -RightPath $retainedSourcePath) -or
        -not (Test-FilesByteIdentical -LeftPath $rollbackSource `
            -RightPath $retainedSourcePath)) {
        throw 'Verified rollback did not restore the captured canonical bytes.'
    }
}

function Invoke-GuardedCanonicalPromotion {
    param(
        [Parameter(Mandatory = $true)][string] $CandidatePath,
        [Parameter(Mandatory = $true)][string] $DestinationPath,
        [Parameter(Mandatory = $true)][string] $AtomicBackupPath,
        [Parameter(Mandatory = $true)][string] $ArchivedPreimagePath,
        [Parameter(Mandatory = $true)][string] $ExpectedPreimageSha256,
        [Parameter(Mandatory = $true)][string] $ExpectedCandidateSha256,
        [Parameter(Mandatory = $true)][string] $WorkDirectory,
        [Parameter(Mandatory = $true)][string] $Token,
        [Parameter(Mandatory = $true)][scriptblock] $Finalize
    )

    $replacementCompleted = $false
    $capturedPreReplacementSha256 = ''
    try {
        Invoke-AtomicFileReplace -CandidatePath $CandidatePath `
            -DestinationPath $DestinationPath -BackupPath $AtomicBackupPath `
            -Token $Token
        $replacementCompleted = $true

        $capturedPreReplacementSha256 = Get-Sha256 -Path $AtomicBackupPath
        if ($capturedPreReplacementSha256 -ne $ExpectedPreimageSha256 -or
            -not (Test-FilesByteIdentical -LeftPath $AtomicBackupPath `
                -RightPath $ArchivedPreimagePath)) {
            throw 'Canonical changed during replacement.'
        }
        if ((Get-Sha256 -Path $DestinationPath) -ne $ExpectedCandidateSha256 -or
            -not (Test-FilesByteIdentical -LeftPath $DestinationPath `
                -RightPath $CandidatePath)) {
            throw 'Promoted canonical does not match the validated candidate.'
        }

        # Postimage archival and archive-index creation are part of the same
        # transaction: any exception here must restore the captured canonical.
        [void](& $Finalize)
    } catch {
        $promotionFailure = $_.Exception.Message
        if (-not $replacementCompleted) {
            throw
        }

        try {
            $rollbackSha256 = if ($capturedPreReplacementSha256 -ne '') {
                $capturedPreReplacementSha256
            } else {
                Get-Sha256 -Path $AtomicBackupPath
            }
            Invoke-VerifiedCanonicalRollback `
                -RollbackSourcePath $AtomicBackupPath `
                -DestinationPath $DestinationPath -WorkDirectory $WorkDirectory `
                -ExpectedSha256 $rollbackSha256 -Token $Token
        } catch {
            $rollbackFailure = $_.Exception.Message
            throw "Promotion failed after canonical replacement: $promotionFailure " +
                "Verified rollback also failed: $rollbackFailure"
        }
        throw "Promotion failed after canonical replacement: $promotionFailure " +
            'Verified rollback restored the captured pre-replacement canonical bytes.'
    }
}

function Write-ArchiveIndex {
    param(
        [Parameter(Mandatory = $true)][string] $ArchiveDirectory,
        [Parameter(Mandatory = $true)][string] $RunId,
        [Parameter(Mandatory = $true)][string] $SourceRunDirectory,
        [Parameter(Mandatory = $true)][object[]] $Members,
        [Parameter(Mandatory = $true)][string] $PreimageSha256,
        [Parameter(Mandatory = $true)][string] $CandidateSha256,
        [Parameter(Mandatory = $true)][bool] $Promoted
    )

    $rootPrefix = [System.IO.Path]::GetFullPath($ArchiveDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $inventory = @(
        Get-ChildItem -LiteralPath $ArchiveDirectory -File -Recurse |
            Where-Object Name -ne 'archive-index.json' |
            Sort-Object FullName |
            ForEach-Object {
                [pscustomobject]@{
                    path = $_.FullName.Substring($rootPrefix.Length).Replace('\', '/')
                    sha256 = Get-Sha256 -Path $_.FullName
                    bytes = $_.Length
                }
            }
    )
    $traceIndex = @(
        $Members | ForEach-Object {
            [pscustomobject]@{
                execution_platform = $_.ExecutionPlatform
                persona = $_.Persona
                repeat_index = $_.RepeatIndex
                trace_id = $_.TraceId
                run_id = $_.RunId
                archived_path = $_.ArchivedRelativePath
                file_sha256 = $_.FileSha256
            }
        }
    )
    $index = [ordered]@{
        schema = 'persona_cohort_archive_v1'
        run_id = $RunId
        source_gate_run = $SourceRunDirectory
        promoted = $Promoted
        canonical_preimage_sha256 = $PreimageSha256
        candidate_sha256 = $CandidateSha256
        traces = $traceIndex
        files = $inventory
    }
    Write-JsonFile -Document $index -Path (Join-Path $ArchiveDirectory 'archive-index.json')
}

function Invoke-PromotionSelfTest {
    $selfTestParent = Join-Path $script:RepoRoot '.test-gate'
    New-Item -ItemType Directory -Path $selfTestParent -Force | Out-Null
    $fixtureRoot = Join-Path $selfTestParent (
        'persona-promotion-self-test-{0}-{1}' -f $PID, [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $sentinel = Join-Path $fixtureRoot '.owned-by-promote-persona-self-test'
    [System.IO.File]::WriteAllText($sentinel, 'owned')
    $realCanonicalHash = if (Test-Path -LiteralPath $script:CanonicalLibraryPath -PathType Leaf) {
        Get-Sha256 -Path $script:CanonicalLibraryPath
    } else {
        ''
    }
    try {
        $tracesByPlatform = @{ native = @(); web = @() }
        foreach ($platform in @('native', 'web')) {
            foreach ($persona in @('dean_takahashi', 'eazy_speezy')) {
                foreach ($repeatIndex in @(0, 1)) {
                    $tracePath = Join-Path $fixtureRoot "$platform-$persona-$repeatIndex.jsonl"
                    [System.IO.File]::WriteAllText(
                        $tracePath, "$platform|$persona|$repeatIndex`n",
                        [System.Text.UTF8Encoding]::new($false))
                    $tracesByPlatform[$platform] += [pscustomobject]@{
                        run_id = "fixture:$platform`_$persona`_$repeatIndex"
                        trace_id = "fixture-trace:$platform`_$persona`_$repeatIndex"
                        persona = $persona
                        fragment_id = 'basin_fill_proof'
                        execution_platform = $platform
                        repeat_index = $repeatIndex
                        content_fingerprint_schema = 'authored_fragment_resource_bytes_v1'
                        content_fingerprint = ('a' * 64 -join '')
                        gameplay_build_fingerprint_schema = 'gameplay_build_resource_set_bytes_v1'
                        gameplay_build_fingerprint = ('b' * 64 -join '')
                        summary_record_hash = ('c' * 64 -join '')
                        decision_count = 1
                        trace_complete = $true
                        persona_goal_reached = $true
                        path = $tracePath
                        validation_record_hash = ('d' * 64 -join '')
                        file_sha256 = Get-Sha256 -Path $tracePath
                    }
                }
            }
        }
        $makeArtifact = {
            param([string] $Platform, [string] $Schema)
            $invocationId = "fixture-invocation-$Platform"
            $traces = @($tracesByPlatform[$Platform])
            [pscustomobject]@{
                schema = $Schema
                invocation_id = $invocationId
                invocation_manifest_hash = ('e' * 64 -join '')
                invocation_manifest = [pscustomobject]@{
                    schema = 'persona_strict_invocation_manifest_v1'
                    invocation_id = $invocationId
                    execution_platform = $Platform
                    fragment_id = 'basin_fill_proof'
                    expected_members = @($traces)
                    members = @($traces)
                    cohort_size = 4
                    passed = $true
                    failure_count = 0
                    failures = @()
                }
                traces = $traces
            }
        }
        $nativeArtifact = & $makeArtifact 'native' 'persona_native_trace_artifact_manifest_v1'
        $webArtifact = & $makeArtifact 'web' 'persona_web_trace_artifact_manifest_v1'
        $validated = @(Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
            -WebArtifact $webArtifact -GateRunRoot $fixtureRoot)
        if ($validated.Count -ne 8) {
            throw 'Self-test exact cohort was not accepted.'
        }

        $badWebArtifact = $webArtifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $badWebArtifact.traces[0].path = $badWebArtifact.traces[1].path
        $badWebArtifact.traces[0].file_sha256 = $badWebArtifact.traces[1].file_sha256
        $duplicateRejected = $false
        try {
            [void](Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
                -WebArtifact $badWebArtifact -GateRunRoot $fixtureRoot)
        } catch {
            $duplicateRejected = $true
        }
        if (-not $duplicateRejected) {
            throw 'Self-test duplicate canonical primary path was accepted.'
        }

        $badRunIdArtifact = $webArtifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $badRunIdArtifact.traces[0].run_id = $badRunIdArtifact.traces[1].run_id
        $duplicateRunIdRejected = $false
        try {
            [void](Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
                -WebArtifact $badRunIdArtifact -GateRunRoot $fixtureRoot)
        } catch {
            $duplicateRunIdRejected = $true
        }
        if (-not $duplicateRunIdRejected) {
            throw 'Self-test duplicate primary run_id was accepted.'
        }

        $badDigestArtifact = $webArtifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $duplicateDigestPath = Join-Path $fixtureRoot 'web-duplicate-digest.jsonl'
        Copy-Item -LiteralPath ([string]$badDigestArtifact.traces[1].path) `
            -Destination $duplicateDigestPath -ErrorAction Stop
        $badDigestArtifact.traces[0].path = $duplicateDigestPath
        $badDigestArtifact.traces[0].file_sha256 = `
            [string]$badDigestArtifact.traces[1].file_sha256
        $duplicateDigestRejected = $false
        try {
            [void](Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
                -WebArtifact $badDigestArtifact -GateRunRoot $fixtureRoot)
        } catch {
            $duplicateDigestRejected = $true
        }
        if (-not $duplicateDigestRejected) {
            throw 'Self-test duplicate primary file_sha256 was accepted.'
        }

        $badMatrixArtifact = $webArtifact | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $badMatrixArtifact.traces[0].repeat_index = 7
        $matrixRejected = $false
        try {
            [void](Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
                -WebArtifact $badMatrixArtifact -GateRunRoot $fixtureRoot)
        } catch {
            $matrixRejected = $true
        }
        if (-not $matrixRejected) {
            throw 'Self-test invalid persona/repeat matrix was accepted.'
        }

        $nativeManifestPath = Join-Path $fixtureRoot 'native.json'
        $webManifestPath = Join-Path $fixtureRoot 'web.json'
        $previewPath = Join-Path $fixtureRoot 'preview.json'
        $reportPath = Join-Path $fixtureRoot 'report.json'
        Write-JsonFile -Document $nativeArtifact -Path $nativeManifestPath
        Write-JsonFile -Document $webArtifact -Path $webManifestPath
        Write-JsonFile -Document ([ordered]@{ schema = 'persona_decision_library_v3' }) `
            -Path $previewPath
        $greenReport = [pscustomobject]@{
            schema = 'persona_cross_platform_validation_v1'
            passed = $true
            issue_count = 0
            issues = @()
            native_manifest = $nativeManifestPath
            web_manifest = $webManifestPath
            combined_preview = $previewPath
        }
        Write-JsonFile -Document $greenReport -Path $reportPath
        Assert-GreenCombinedReport -Report $greenReport `
            -NativeManifestPath $nativeManifestPath -WebManifestPath $webManifestPath `
            -PreviewPath $previewPath -Description 'self-test report'

        $fixtureCanonical = Join-Path $fixtureRoot 'canonical.json'
        [System.IO.File]::WriteAllText($fixtureCanonical, "before`n")
        $nativeManifestHash = Get-Sha256 -Path $nativeManifestPath
        $webManifestHash = Get-Sha256 -Path $webManifestPath
        $fixtureArchivePath = Join-Path $fixtureRoot 'archive'
        $fixtureArchive = Copy-ArchiveInputs -Members $validated `
            -NativeManifestPath $nativeManifestPath -WebManifestPath $webManifestPath `
            -CombinedReportPath $reportPath -CombinedPreviewPath $previewPath `
            -CanonicalLibraryPath $fixtureCanonical -ArchiveDirectory $fixtureArchivePath
        if ((Get-Sha256 -Path $fixtureArchive.SourceNativeManifestPath) -ne $nativeManifestHash -or
            (Get-Sha256 -Path $fixtureArchive.SourceWebManifestPath) -ne $webManifestHash) {
            throw 'Self-test did not preserve source manifests byte-for-byte.'
        }
        foreach ($rebasedManifestPath in @(
            $fixtureArchive.RebasedNativeManifestPath,
            $fixtureArchive.RebasedWebManifestPath)) {
            $rebasedManifest = Read-JsonFile -Path $rebasedManifestPath `
                -Description 'self-test rebased artifact manifest'
            foreach ($trace in @($rebasedManifest.traces)) {
                $rebasedTracePath = Get-ExistingPath -Path ([string]$trace.path) `
                    -PathType Leaf -Description 'self-test rebased trace'
                if (-not (Test-PathWithinRoot -Path $rebasedTracePath -Root $fixtureArchivePath) -or
                    (Get-Sha256 -Path $rebasedTracePath) -ne [string]$trace.file_sha256) {
                    throw 'Self-test rebased manifest is not bound to an archived exact trace.'
                }
            }
        }
        Write-ArchiveIndex -ArchiveDirectory $fixtureArchivePath `
            -RunId 'self-test-run' -SourceRunDirectory $fixtureRoot `
            -Members $fixtureArchive.Members `
            -PreimageSha256 (Get-Sha256 -Path $fixtureCanonical) `
            -CandidateSha256 (Get-Sha256 -Path $previewPath) -Promoted $false
        $fixtureArchiveIndex = Read-JsonFile `
            -Path (Join-Path $fixtureArchivePath 'archive-index.json') `
            -Description 'self-test archive index'
        $indexedRunIds = @($fixtureArchiveIndex.traces | ForEach-Object {
            [string]$_.run_id
        } | Sort-Object -Unique)
        $indexedDigests = @($fixtureArchiveIndex.traces | ForEach-Object {
            [string]$_.file_sha256
        } | Sort-Object -Unique)
        if (@($fixtureArchiveIndex.traces).Count -ne 8 -or
            $indexedRunIds.Count -ne 8 -or $indexedDigests.Count -ne 8) {
            throw 'Self-test archive index did not retain eight unique run IDs and file digests.'
        }

        $fixtureCandidate = Join-Path $fixtureRoot 'candidate.json'
        $fixtureBackup = Join-Path $fixtureArchivePath 'atomic-backup.json'
        [System.IO.File]::WriteAllText($fixtureCandidate, "after`n")
        Invoke-AtomicFileReplace -CandidatePath $fixtureCandidate `
            -DestinationPath $fixtureCanonical -BackupPath $fixtureBackup -Token 'self-test'
        if ([System.IO.File]::ReadAllText($fixtureCanonical) -ne "after`n" -or
            [System.IO.File]::ReadAllText($fixtureBackup) -ne "before`n") {
            throw 'Self-test atomic replacement or backup failed.'
        }

        $concurrentRoot = Join-Path $fixtureRoot 'concurrent-rollback'
        New-Item -ItemType Directory -Path $concurrentRoot | Out-Null
        $concurrentPreimage = Join-Path $concurrentRoot 'preimage.json'
        $concurrentCanonical = Join-Path $concurrentRoot 'canonical.json'
        $concurrentCandidate = Join-Path $concurrentRoot 'candidate.json'
        $concurrentBackup = Join-Path $concurrentRoot 'atomic-backup.json'
        [System.IO.File]::WriteAllText($concurrentPreimage, "before`n")
        [System.IO.File]::WriteAllText($concurrentCanonical, "concurrent`n")
        [System.IO.File]::WriteAllText($concurrentCandidate, "after`n")
        $concurrentFinalizeCalls = [System.Collections.Generic.List[string]]::new()
        $concurrentFinalize = {
            [void]$concurrentFinalizeCalls.Add('called')
        }.GetNewClosure()
        $concurrentRejected = $false
        $concurrentFailureMessage = ''
        try {
            Invoke-GuardedCanonicalPromotion `
                -CandidatePath $concurrentCandidate `
                -DestinationPath $concurrentCanonical `
                -AtomicBackupPath $concurrentBackup `
                -ArchivedPreimagePath $concurrentPreimage `
                -ExpectedPreimageSha256 (Get-Sha256 -Path $concurrentPreimage) `
                -ExpectedCandidateSha256 (Get-Sha256 -Path $concurrentCandidate) `
                -WorkDirectory $concurrentRoot -Token 'concurrent-self-test' `
                -Finalize $concurrentFinalize
        } catch {
            $concurrentRejected = $true
            $concurrentFailureMessage = $_.Exception.Message
        }
        $concurrentRetainedSource = Join-Path $concurrentRoot `
            'decision_library.concurrent-self-test.rollback-source.json'
        if (-not $concurrentRejected -or
            $concurrentFailureMessage -notmatch 'Verified rollback restored' -or
            $concurrentFinalizeCalls.Count -ne 0 -or
            [System.IO.File]::ReadAllText($concurrentCanonical) -ne "concurrent`n" -or
            [System.IO.File]::ReadAllText($concurrentBackup) -ne "concurrent`n" -or
            [System.IO.File]::ReadAllText($concurrentRetainedSource) -ne "concurrent`n") {
            throw 'Self-test concurrent canonical change was not rejected and restored exactly.'
        }

        $finalizeFailureRoot = Join-Path $fixtureRoot 'finalize-failure-rollback'
        New-Item -ItemType Directory -Path $finalizeFailureRoot | Out-Null
        $finalizePreimage = Join-Path $finalizeFailureRoot 'preimage.json'
        $finalizeCanonical = Join-Path $finalizeFailureRoot 'canonical.json'
        $finalizeCandidate = Join-Path $finalizeFailureRoot 'candidate.json'
        $finalizeBackup = Join-Path $finalizeFailureRoot 'atomic-backup.json'
        [System.IO.File]::WriteAllText($finalizePreimage, "before`n")
        [System.IO.File]::WriteAllText($finalizeCanonical, "before`n")
        [System.IO.File]::WriteAllText($finalizeCandidate, "after`n")
        $finalizeCalls = [System.Collections.Generic.List[string]]::new()
        $failingFinalize = {
            [void]$finalizeCalls.Add('called')
            throw 'injected post-replacement archive/index failure'
        }.GetNewClosure()
        $finalizeFailureRejected = $false
        $finalizeFailureMessage = ''
        try {
            Invoke-GuardedCanonicalPromotion `
                -CandidatePath $finalizeCandidate `
                -DestinationPath $finalizeCanonical `
                -AtomicBackupPath $finalizeBackup `
                -ArchivedPreimagePath $finalizePreimage `
                -ExpectedPreimageSha256 (Get-Sha256 -Path $finalizePreimage) `
                -ExpectedCandidateSha256 (Get-Sha256 -Path $finalizeCandidate) `
                -WorkDirectory $finalizeFailureRoot -Token 'finalize-self-test' `
                -Finalize $failingFinalize
        } catch {
            $finalizeFailureRejected = $true
            $finalizeFailureMessage = $_.Exception.Message
        }
        $finalizeRetainedSource = Join-Path $finalizeFailureRoot `
            'decision_library.finalize-self-test.rollback-source.json'
        if (-not $finalizeFailureRejected -or
            $finalizeFailureMessage -notmatch 'Verified rollback restored' -or
            $finalizeCalls.Count -ne 1 -or
            [System.IO.File]::ReadAllText($finalizeCanonical) -ne "before`n" -or
            [System.IO.File]::ReadAllText($finalizeBackup) -ne "before`n" -or
            [System.IO.File]::ReadAllText($finalizeRetainedSource) -ne "before`n") {
            throw 'Self-test post-replacement finalization failure was not rolled back exactly.'
        }

        $guardSuccessRoot = Join-Path $fixtureRoot 'guard-success'
        New-Item -ItemType Directory -Path $guardSuccessRoot | Out-Null
        $guardSuccessPreimage = Join-Path $guardSuccessRoot 'preimage.json'
        $guardSuccessCanonical = Join-Path $guardSuccessRoot 'canonical.json'
        $guardSuccessCandidate = Join-Path $guardSuccessRoot 'candidate.json'
        $guardSuccessBackup = Join-Path $guardSuccessRoot 'atomic-backup.json'
        $guardSuccessMarker = Join-Path $guardSuccessRoot 'finalized.txt'
        [System.IO.File]::WriteAllText($guardSuccessPreimage, "before`n")
        [System.IO.File]::WriteAllText($guardSuccessCanonical, "before`n")
        [System.IO.File]::WriteAllText($guardSuccessCandidate, "after`n")
        $successfulFinalize = {
            [System.IO.File]::WriteAllText($guardSuccessMarker, 'finalized')
        }.GetNewClosure()
        Invoke-GuardedCanonicalPromotion `
            -CandidatePath $guardSuccessCandidate `
            -DestinationPath $guardSuccessCanonical `
            -AtomicBackupPath $guardSuccessBackup `
            -ArchivedPreimagePath $guardSuccessPreimage `
            -ExpectedPreimageSha256 (Get-Sha256 -Path $guardSuccessPreimage) `
            -ExpectedCandidateSha256 (Get-Sha256 -Path $guardSuccessCandidate) `
            -WorkDirectory $guardSuccessRoot -Token 'success-self-test' `
            -Finalize $successfulFinalize
        if ([System.IO.File]::ReadAllText($guardSuccessCanonical) -ne "after`n" -or
            [System.IO.File]::ReadAllText($guardSuccessBackup) -ne "before`n" -or
            [System.IO.File]::ReadAllText($guardSuccessMarker) -ne 'finalized') {
            throw 'Self-test guarded promotion success path did not finalize exactly.'
        }

        if ($realCanonicalHash -ne '' -and
            (Get-Sha256 -Path $script:CanonicalLibraryPath) -ne $realCanonicalHash) {
            throw 'Self-test altered the project canonical decision library.'
        }
        Write-Host '[PERSONA_PROMOTION_SELF_TEST] PASS'
    } finally {
        $fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
        if ((Test-PathWithinRoot -Path $fixtureFull -Root $selfTestParent) -and
            (Test-Path -LiteralPath $sentinel -PathType Leaf)) {
            Remove-Item -LiteralPath $fixtureFull -Recurse -Force
        }
    }
}

if ($SelfTest) {
    Invoke-PromotionSelfTest
    exit 0
}

$gateRunRoot = Get-ExistingPath -Path $GateRunDirectory -PathType Container `
    -Description 'gate run directory'
$godotExecutable = Get-ExistingPath -Path $GodotPath -PathType Leaf `
    -Description 'Godot executable'
$projectRoot = Get-ExistingPath -Path $script:ProjectRoot -PathType Container `
    -Description 'Godot project directory'
$canonicalLibrary = Get-ExistingPath -Path $script:CanonicalLibraryPath -PathType Leaf `
    -Description 'canonical persona decision library'
$nodeExecutable = (Get-Command node -CommandType Application -ErrorAction Stop).Source
$reporterPath = Get-ExistingPath `
    -Path (Join-Path $projectRoot 'tests\web\persona-validation-reporter.mjs') `
    -PathType Leaf -Description 'combined persona validation reporter'
$distillerPath = Get-ExistingPath `
    -Path (Join-Path $projectRoot 'tools\distill_persona_decision_library.gd') `
    -PathType Leaf -Description 'persona decision distiller'

$nativeManifestPath = Get-ExistingPath `
    -Path (Join-Path $gateRunRoot 'native-persona-trace-manifest.json') `
    -PathType Leaf -Description 'native artifact manifest'
$webManifestPath = Get-ExistingPath `
    -Path (Join-Path $gateRunRoot 'playwright\persona-trace-manifest.json') `
    -PathType Leaf -Description 'Web artifact manifest'
$combinedPreviewPath = Get-ExistingPath `
    -Path (Join-Path $gateRunRoot 'persona-decision-library.combined.preview.json') `
    -PathType Leaf -Description 'combined distillation preview'
$combinedReportPath = Get-ExistingPath `
    -Path (Join-Path $gateRunRoot 'persona-cross-platform-validation.json') `
    -PathType Leaf -Description 'combined validation report'

$nativeArtifact = Read-JsonFile -Path $nativeManifestPath -Description 'native artifact manifest'
$webArtifact = Read-JsonFile -Path $webManifestPath -Description 'Web artifact manifest'
$combinedReport = Read-JsonFile -Path $combinedReportPath -Description 'combined validation report'
Assert-GreenCombinedReport -Report $combinedReport -NativeManifestPath $nativeManifestPath `
    -WebManifestPath $webManifestPath -PreviewPath $combinedPreviewPath `
    -Description 'gate combined validation report'
$members = @(Get-ValidatedTraceMembers -NativeArtifact $nativeArtifact `
    -WebArtifact $webArtifact -GateRunRoot $gateRunRoot)

$runId = (Get-Item -LiteralPath $gateRunRoot).Name
if ($runId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "Gate run directory name is not a safe archive ID: $runId"
}
$canonicalPreimageSha256 = Get-Sha256 -Path $canonicalLibrary
if ($Promote) {
    New-Item -ItemType Directory -Path $script:CohortArchiveRoot -Force | Out-Null
    $workDirectory = Join-Path $script:CohortArchiveRoot $runId
    if (Test-Path -LiteralPath $workDirectory) {
        throw "Cohort archive already exists; refusing to merge or overwrite it: $workDirectory"
    }
    Write-Host "[PERSONA_PROMOTION] Durable archive: $workDirectory"
} else {
    $dryRunParent = Join-Path $gateRunRoot 'promotion-dry-run'
    New-Item -ItemType Directory -Path $dryRunParent -Force | Out-Null
    $workDirectory = Join-Path $dryRunParent (
        '{0}-{1}-{2}' -f ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')), $PID,
        [Guid]::NewGuid().ToString('N'))
    Write-Host "[PERSONA_PROMOTION] DRY RUN; canonical library will not be replaced."
    Write-Host "[PERSONA_PROMOTION] Run-owned validation archive: $workDirectory"
}

$archive = Copy-ArchiveInputs -Members $members -NativeManifestPath $nativeManifestPath `
    -WebManifestPath $webManifestPath -CombinedReportPath $combinedReportPath `
    -CombinedPreviewPath $combinedPreviewPath -CanonicalLibraryPath $canonicalLibrary `
    -ArchiveDirectory $workDirectory
if ((Get-Sha256 -Path $archive.PreimagePath) -ne $canonicalPreimageSha256 -or
    -not (Test-FilesByteIdentical -LeftPath $archive.PreimagePath -RightPath $canonicalLibrary)) {
    throw 'Archived canonical preimage differs from the canonical library.'
}

$candidatePath = Join-Path $workDirectory 'decision_library.redistilled.json'
$traceArguments = @($archive.Members | ForEach-Object { "--trace=$($_.ArchivedPath)" })
$godotArguments = @(
    '--headless',
    '--path', $projectRoot,
    '--script', 'res://tools/distill_persona_decision_library.gd',
    '--',
    "--library=$($archive.PreimagePath)"
) + $traceArguments + @("--output=$candidatePath")
Write-Host '[PERSONA_PROMOTION] Re-distilling the archived eight-trace cohort from the frozen preimage.'
& $godotExecutable @godotArguments
if ($LASTEXITCODE -ne 0) {
    throw "Archived cohort distillation failed with exit code $LASTEXITCODE."
}
$candidatePath = Get-ExistingPath -Path $candidatePath -PathType Leaf `
    -Description 'archived-cohort distillation candidate'

$redistilledReportPath = Join-Path $workDirectory 'persona-cross-platform-validation.redistilled.json'
Write-Host '[PERSONA_PROMOTION] Revalidating the candidate against rebased, self-contained manifests.'
& $nodeExecutable $reporterPath '--validate-combined' `
    $archive.RebasedNativeManifestPath $archive.RebasedWebManifestPath `
    $candidatePath $redistilledReportPath
if ($LASTEXITCODE -ne 0) {
    throw "Archived cohort combined validation failed with exit code $LASTEXITCODE."
}
$redistilledReport = Read-JsonFile -Path $redistilledReportPath `
    -Description 'redistilled combined validation report'
Assert-GreenCombinedReport -Report $redistilledReport `
    -NativeManifestPath $archive.RebasedNativeManifestPath `
    -WebManifestPath $archive.RebasedWebManifestPath `
    -PreviewPath $candidatePath -Description 'redistilled combined validation report'

$candidateSha256 = Get-Sha256 -Path $candidatePath
$gatePreviewSha256 = Get-Sha256 -Path $combinedPreviewPath
if ($candidateSha256 -ne $gatePreviewSha256 -or
    -not (Test-FilesByteIdentical -LeftPath $candidatePath -RightPath $combinedPreviewPath)) {
    throw 'Archived-cohort candidate is not byte/hash-identical to the gate combined preview.'
}
if ((Get-Sha256 -Path $canonicalLibrary) -ne $canonicalPreimageSha256 -or
    -not (Test-FilesByteIdentical -LeftPath $canonicalLibrary -RightPath $archive.PreimagePath)) {
    throw 'Canonical library changed after the frozen preimage was captured.'
}

if ($Promote) {
    $atomicBackupPath = Join-Path $workDirectory 'decision_library.atomic-backup.json'
    Write-Host '[PERSONA_PROMOTION] Atomically replacing the canonical library.'
    $finalizePromotion = {
        $postimagePath = Join-Path $workDirectory 'decision_library.postimage.json'
        Copy-Item -LiteralPath $canonicalLibrary -Destination $postimagePath `
            -ErrorAction Stop
        if ((Get-Sha256 -Path $postimagePath) -ne $candidateSha256 -or
            -not (Test-FilesByteIdentical -LeftPath $postimagePath `
                -RightPath $candidatePath) -or
            -not (Test-FilesByteIdentical -LeftPath $postimagePath `
                -RightPath $canonicalLibrary)) {
            throw 'Archived postimage is not byte-identical to the promoted canonical library.'
        }
        Write-ArchiveIndex -ArchiveDirectory $workDirectory -RunId $runId `
            -SourceRunDirectory $gateRunRoot -Members $archive.Members `
            -PreimageSha256 $canonicalPreimageSha256 `
            -CandidateSha256 $candidateSha256 -Promoted $true
    }.GetNewClosure()
    Invoke-GuardedCanonicalPromotion -CandidatePath $candidatePath `
        -DestinationPath $canonicalLibrary -AtomicBackupPath $atomicBackupPath `
        -ArchivedPreimagePath $archive.PreimagePath `
        -ExpectedPreimageSha256 $canonicalPreimageSha256 `
        -ExpectedCandidateSha256 $candidateSha256 -WorkDirectory $workDirectory `
        -Token $runId -Finalize $finalizePromotion
} else {
    Write-ArchiveIndex -ArchiveDirectory $workDirectory -RunId $runId `
        -SourceRunDirectory $gateRunRoot -Members $archive.Members `
        -PreimageSha256 $canonicalPreimageSha256 -CandidateSha256 $candidateSha256 `
        -Promoted $false
}

if (-not $Promote -and (Get-Sha256 -Path $canonicalLibrary) -ne $canonicalPreimageSha256) {
    throw 'Dry run altered the canonical library.'
}
if ($Promote) {
    Write-Host "[PERSONA_PROMOTION] PASS promoted=$canonicalLibrary archive=$workDirectory"
} else {
    Write-Host "[PERSONA_PROMOTION] PASS dry-run-only archive=$workDirectory"
    Write-Host '[PERSONA_PROMOTION] Re-run the same command with -Promote only after reviewing this result.'
}
