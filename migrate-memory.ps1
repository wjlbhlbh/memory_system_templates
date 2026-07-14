param(
    [string]$TargetPath = ".",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$memoryPath = Join-Path $targetRoot ".ai_memory"
$indexPath = Join-Path $memoryPath "index.json"
$templateMemory = Join-Path $scriptRoot ".ai_memory-pro"
$templateIndexPath = Join-Path $templateMemory "index.json"
if (-not (Test-Path -LiteralPath $indexPath)) { throw "Missing project memory index: $indexPath" }

$oldIndex = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json
$currentRequirements = Join-Path $memoryPath "requirements\current.md"
$isCurrent = ($oldIndex.version -eq "2.0.0" -and ($oldIndex.PSObject.Properties.Name -contains "budgets") -and (-not ($oldIndex.PSObject.Properties.Name -contains "bootstrap_order")) -and @($oldIndex.startup_order).Count -eq 3 -and (Test-Path -LiteralPath $currentRequirements))
if ($isCurrent) {
    Write-Output "Memory system is already current (2.0.0)."
    return
}
if (-not (Test-Path -LiteralPath $templateIndexPath)) { throw "Migration requires the template repository containing .ai_memory-pro." }

Write-Output "Migration plan:"
Write-Output "- Back up .ai_memory with SHA-256 manifest."
Write-Output "- Upgrade index.json to 2.0.0 and enforce three-file startup."
Write-Output "- Remove bootstrap_order and add requirement lifecycle files."
if (-not $Apply) {
    Write-Output "DRY RUN: no files were changed."
    return
}

function Write-AtomicText {
    param([string]$Path, [string]$Content)
    $tempPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Get-RelativeMemoryPath {
    param([string]$FullPath)
    $prefix = $memoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "File is outside .ai_memory: $FullPath" }
    return $FullPath.Substring($prefix.Length)
}

$archiveRoot = Join-Path $targetRoot ".ai_memory_archive"
$migrationId = "migration-" + (Get-Date).ToString("yyyyMMdd-HHmmssfff")
$finalArchive = Join-Path $archiveRoot $migrationId
$stagingArchive = Join-Path $archiveRoot (".staging-" + [guid]::NewGuid().ToString("N"))
$originalIndexBytes = [IO.File]::ReadAllBytes($indexPath)
$activePath = Join-Path $memoryPath "activeContext.md"
$agentRulesPath = Join-Path $memoryPath "agentRules.md"
$originalActiveBytes = if (Test-Path -LiteralPath $activePath) { [IO.File]::ReadAllBytes($activePath) } else { $null }
$originalAgentRulesBytes = if (Test-Path -LiteralPath $agentRulesPath) { [IO.File]::ReadAllBytes($agentRulesPath) } else { $null }
$requirementsPath = Join-Path $memoryPath "requirements"
$requirementsAdded = -not (Test-Path -LiteralPath $requirementsPath)

try {
    New-Item -ItemType Directory -Path $stagingArchive -Force | Out-Null
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $memoryPath -Recurse -File) {
        $relative = Get-RelativeMemoryPath $file.FullName
        $archiveFile = Join-Path $stagingArchive $relative
        $archiveDirectory = Split-Path -Parent $archiveFile
        if (-not (Test-Path -LiteralPath $archiveDirectory)) { New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $archiveFile
        $hash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $relativeForward = $relative.Replace('\', '/')
        $records.Add([ordered]@{
            source_path = ".ai_memory/$relativeForward"
            archive_path = ".ai_memory_archive/$migrationId/$relativeForward"
            bytes = $file.Length
            characters = $text.Length
            lines = ($text -split "`r?`n").Count
            sha256 = $hash
            preservation = "exact byte-for-byte pre-migration snapshot"
        })
    }
    $manifest = [ordered]@{
        archive_version = "1.0.0"
        created_at = (Get-Date).ToString("o")
        repository_branch = "unknown"
        repository_head = "unknown"
        purpose = "Preserve the complete pre-2.0 project memory before migration."
        policy = "Immutable migration backup. Never edit in place; verify SHA-256."
        files = @($records | ForEach-Object { $_ })
    }
    [IO.File]::WriteAllText((Join-Path $stagingArchive "manifest.json"), ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)
    Move-Item -LiteralPath $stagingArchive -Destination $finalArchive

    $templateIndexText = [IO.File]::ReadAllText($templateIndexPath, [Text.Encoding]::UTF8)
    Write-AtomicText -Path $indexPath -Content $templateIndexText

    $requirementsTemplate = Join-Path $templateMemory "requirements"
    if (-not (Test-Path -LiteralPath $requirementsPath)) {
        Copy-Item -LiteralPath $requirementsTemplate -Destination $requirementsPath -Recurse
        Get-ChildItem -LiteralPath $requirementsPath -Recurse -File | ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8).Replace("__DATE__", (Get-Date).ToString("yyyy-MM-dd"))
            [IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom)
        }
    }

    if (Test-Path -LiteralPath $activePath) {
        $activeText = [IO.File]::ReadAllText($activePath, [Text.Encoding]::UTF8)
        if ($activeText -notmatch 'Requirement Baseline') {
            Write-AtomicText -Path $activePath -Content ("<!-- REQUIREMENT_BASELINE -->`n- **Requirement Baseline**: 0 ([UNINITIALIZED])`n`n" + $activeText)
        }
    }

    if (Test-Path -LiteralPath $agentRulesPath) {
        $rulesText = [IO.File]::ReadAllText($agentRulesPath, [Text.Encoding]::UTF8)
        if ($rulesText -notmatch 'Latest User Intent Wins') {
            $lifecycleLines = @(
                ''
                '## Requirement lifecycle'
                '- Initialize `requirements/current.md` when it is `[UNINITIALIZED]` and the user supplies requirements or a PRD.'
                '- Apply **Latest User Intent Wins** and preserve replaced versions as `SUPERSEDED` events.'
                '- Requirement synchronization does not mean implementation or verification is complete.'
            )
            Write-AtomicText -Path $agentRulesPath -Content ($rulesText.TrimEnd() + (($lifecycleLines -join "`n")) + "`n")
        }
    }

    foreach ($helper in @("memory-health.ps1", "record-requirement-change.ps1", "compact-memory.ps1", "migrate-memory.ps1", "search-memory.ps1")) {
        $source = Join-Path $scriptRoot $helper
        $destination = Join-Path $targetRoot $helper
        if ((Test-Path -LiteralPath $source) -and (-not (Test-Path -LiteralPath $destination))) {
            [IO.File]::WriteAllText($destination, [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8), $utf8NoBom)
        }
    }

    Get-ChildItem -LiteralPath $finalArchive -Recurse -File | ForEach-Object { $_.IsReadOnly = $true }
    Write-Output "APPLIED: memory migration completed."
    Write-Output "Backup: $finalArchive"
} catch {
    [IO.File]::WriteAllBytes($indexPath, $originalIndexBytes)
    if ($null -ne $originalActiveBytes) { [IO.File]::WriteAllBytes($activePath, $originalActiveBytes) }
    if ($null -ne $originalAgentRulesBytes) { [IO.File]::WriteAllBytes($agentRulesPath, $originalAgentRulesBytes) }
    if ($requirementsAdded -and (Test-Path -LiteralPath $requirementsPath)) {
        $resolvedRequirements = (Resolve-Path -LiteralPath $requirementsPath).Path
        $memoryPrefix = $memoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if ($resolvedRequirements.StartsWith($memoryPrefix, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedRequirements -Recurse -Force }
    }
    if (Test-Path -LiteralPath $stagingArchive) { Remove-Item -LiteralPath $stagingArchive -Recurse -Force }
    throw
}
