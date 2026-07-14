param(
    [string]$MemoryPath = ".ai_memory",
    [switch]$VerifyArchive,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-HealthError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Get-TextMetrics {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $lineLengths = @($text -split "`r?`n" | ForEach-Object { $_.Length })
    $maximumLine = if ($lineLengths.Count -gt 0) { ($lineLengths | Measure-Object -Maximum).Maximum } else { 0 }
    return [pscustomobject]@{
        Bytes = (Get-Item -LiteralPath $Path).Length
        Characters = $text.Length
        Lines = $lineLengths.Count
        MaxLineCharacters = $maximumLine
    }
}

if (-not (Test-Path -LiteralPath $MemoryPath)) {
    throw "Memory path does not exist: $MemoryPath"
}

$resolvedMemory = (Resolve-Path -LiteralPath $MemoryPath).Path
$indexPath = Join-Path $resolvedMemory "index.json"
if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "Missing memory index: $indexPath"
}
$index = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json
if (-not ($index.PSObject.Properties.Name -contains "budgets")) {
    Add-HealthError "index.json is missing budgets."
}

$startupCount = @($index.startup_order).Count
$startupLimit = [int]$index.budgets.startup.max_files
if ($startupCount -ne $startupLimit) {
    Add-HealthError "Startup file count mismatch: $startupCount / limit $startupLimit"
}
$startupCharacters = 0
foreach ($entry in @($index.startup_order)) {
    $entryPath = Join-Path $resolvedMemory $entry
    if (-not (Test-Path -LiteralPath $entryPath)) {
        Add-HealthError "Missing startup file: $entry"
        continue
    }
    $startupCharacters += (Get-TextMetrics $entryPath).Characters
}
if ($startupCharacters -gt [int]$index.budgets.startup.hard_max_characters) {
    Add-HealthError "Startup hard character budget exceeded: $startupCharacters"
} elseif ($startupCharacters -gt [int]$index.budgets.startup.warn_characters) {
    $warnings.Add("Startup warning character budget exceeded: $startupCharacters")
}

$indexMetrics = Get-TextMetrics $indexPath
if ($indexMetrics.Characters -gt [int]$index.budgets.index.hard_max_characters) {
    Add-HealthError "index.json hard character budget exceeded: $($indexMetrics.Characters)"
}

$activePath = Join-Path $resolvedMemory "activeContext.md"
if (Test-Path -LiteralPath $activePath) {
    $activeMetrics = Get-TextMetrics $activePath
    if ($activeMetrics.Characters -gt [int]$index.budgets.active_context.hard_max_characters) {
        Add-HealthError "activeContext hard character budget exceeded: $($activeMetrics.Characters)"
    }
    if ($activeMetrics.Lines -gt [int]$index.budgets.active_context.hard_max_lines) {
        Add-HealthError "activeContext line budget exceeded: $($activeMetrics.Lines)"
    }
    if ($activeMetrics.MaxLineCharacters -gt [int]$index.budgets.active_context.max_single_line_characters) {
        Add-HealthError "activeContext single-line budget exceeded: $($activeMetrics.MaxLineCharacters)"
    }
} else {
    Add-HealthError "Missing activeContext.md."
}

$progressPath = Join-Path $resolvedMemory "progress.md"
if (Test-Path -LiteralPath $progressPath) {
    $progressMetrics = Get-TextMetrics $progressPath
    if ($progressMetrics.Characters -gt [int]$index.budgets.progress.hard_max_characters) {
        Add-HealthError "progress hard character budget exceeded: $($progressMetrics.Characters)"
    }
    if ($progressMetrics.Lines -gt [int]$index.budgets.progress.hard_max_lines) {
        Add-HealthError "progress line budget exceeded: $($progressMetrics.Lines)"
    }
}

$requirementsPath = Join-Path $resolvedMemory "requirements\current.md"
$requirementState = "MISSING"
$requirementVersion = -1
if (Test-Path -LiteralPath $requirementsPath) {
    $requirementsText = Get-Content -Raw -Encoding UTF8 $requirementsPath
    $stateMatch = [regex]::Match($requirementsText, '(?m)^- \*\*state\*\*: \[([^\]]+)\]')
    $versionMatch = [regex]::Match($requirementsText, '(?m)^- \*\*baseline_version\*\*: (\d+)')
    if ($stateMatch.Success) { $requirementState = $stateMatch.Groups[1].Value }
    if ($versionMatch.Success) { $requirementVersion = [int]$versionMatch.Groups[1].Value }
    if (-not $stateMatch.Success -or -not $versionMatch.Success) {
        Add-HealthError "Requirement baseline metadata is invalid."
    }
} else {
    Add-HealthError "Missing requirements/current.md."
}

$changeLogPath = Join-Path $resolvedMemory "requirements\change-log.jsonl"
if ((Test-Path -LiteralPath $changeLogPath) -and $requirementVersion -ge 0) {
    $requirementEvents = @()
    foreach ($line in Get-Content -Encoding UTF8 $changeLogPath) {
        if (-not $line.Trim()) { continue }
        try {
            $record = $line | ConvertFrom-Json
            if ($record.status -ne "schema") { $requirementEvents += $record }
        } catch { }
    }
    if ($requirementVersion -ne $requirementEvents.Count) {
        Add-HealthError "Requirement baseline version does not match change log event count: $requirementVersion / $($requirementEvents.Count)"
    }
}

if ((Test-Path -LiteralPath $activePath) -and $requirementVersion -ge 0) {
    $activeText = Get-Content -Raw -Encoding UTF8 $activePath
    $activeBaselineMatch = [regex]::Match($activeText, '(?m)^- \*\*Requirement Baseline\*\*: (\d+)')
    if (-not $activeBaselineMatch.Success -or [int]$activeBaselineMatch.Groups[1].Value -ne $requirementVersion) {
        Add-HealthError "activeContext requirement baseline does not match requirements/current.md."
    }
}

foreach ($jsonlRelative in @("requirements\change-log.jsonl", "history\index.jsonl")) {
    $jsonlPath = Join-Path $resolvedMemory $jsonlRelative
    if (-not (Test-Path -LiteralPath $jsonlPath)) {
        Add-HealthError "Missing JSONL index: $jsonlRelative"
        continue
    }
    $lineNumber = 0
    foreach ($line in Get-Content -Encoding UTF8 $jsonlPath) {
        $lineNumber++
        if (-not $line.Trim()) { continue }
        try { $line | ConvertFrom-Json | Out-Null } catch { Add-HealthError "Invalid JSONL: ${jsonlRelative}:$lineNumber" }
    }
}

if ($VerifyArchive) {
    $projectRoot = Split-Path -Parent $resolvedMemory
    $archiveRoot = Join-Path $projectRoot ".ai_memory_archive"
    if (Test-Path -LiteralPath $archiveRoot) {
        foreach ($manifestFile in Get-ChildItem -LiteralPath $archiveRoot -Recurse -File -Filter "manifest.json") {
            try {
                $manifest = Get-Content -Raw -Encoding UTF8 $manifestFile.FullName | ConvertFrom-Json
                foreach ($fileRecord in @($manifest.files)) {
                    $archivePath = Join-Path $projectRoot ([string]$fileRecord.archive_path)
                    if (-not (Test-Path -LiteralPath $archivePath)) {
                        Add-HealthError "Archive file is missing: $($fileRecord.archive_path)"
                        continue
                    }
                    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($actualHash -ne ([string]$fileRecord.sha256).ToLowerInvariant()) {
                        Add-HealthError "Archive SHA-256 mismatch: $($fileRecord.archive_path)"
                    }
                }
            } catch {
                Add-HealthError "Invalid archive manifest: $($manifestFile.FullName)"
            }
        }
    }
}

$estimatedTokens = [Math]::Ceiling($startupCharacters / 3.0)
$status = if ($errors.Count -eq 0) { "PASS" } else { "FAIL" }
$result = [ordered]@{
    status = $status
    startup_files = $startupCount
    startup_file_limit = $startupLimit
    startup_characters = $startupCharacters
    estimated_tokens = $estimatedTokens
    requirement_baseline_version = $requirementVersion
    requirement_state = $requirementState
    warnings = @($warnings)
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-Output "Startup files: $startupCount / limit $startupLimit"
    Write-Output "Startup characters: $startupCharacters / hard limit $($index.budgets.startup.hard_max_characters)"
    Write-Output "Estimated tokens: $estimatedTokens / limit $($index.budgets.startup.estimated_token_limit)"
    Write-Output "Requirements baseline: $requirementVersion [$requirementState]"
    foreach ($warning in $warnings) { Write-Output "WARN: $warning" }
    foreach ($healthError in $errors) { Write-Output "ERROR: $healthError" }
    Write-Output "Overall status: $status"
}

if ($errors.Count -gt 0) { exit 1 }
exit 0
