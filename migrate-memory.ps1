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
$activePath = Join-Path $memoryPath "activeContext.md"
$agentRulesPath = Join-Path $memoryPath "agentRules.md"

if (-not (Test-Path -LiteralPath $indexPath)) { throw "Missing project memory index: $indexPath" }

$oldIndex = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json
$isCurrent = (
    $oldIndex.version -eq "3.0.0" -and
    @($oldIndex.startup_order).Count -eq 1 -and
    @($oldIndex.startup_order)[0] -eq "activeContext.md" -and
    [int]$oldIndex.budgets.startup.max_files -eq 1 -and
    [int]$oldIndex.budgets.active_context.hard_max_characters -gt 0 -and
    [int]$oldIndex.budgets.task_pack.hard_max_characters -gt 0 -and
    @($oldIndex.compact_contract).Count -gt 0 -and
    (Test-Path -LiteralPath $activePath)
)
if ($isCurrent) {
    Write-Output "Memory system is already current (3.0.0)."
    return
}
if (-not (Test-Path -LiteralPath $templateIndexPath)) { throw "Migration requires the template repository containing .ai_memory-pro." }

Write-Output "Migration plan:"
Write-Output "- Back up the complete .ai_memory tree with a SHA-256 manifest."
Write-Output "- Preserve the old active context in a bounded task pack or immutable archive."
Write-Output "- Upgrade to one-file state-aware startup: activeContext.md only."
Write-Output "- Keep project-specific routes and metadata in index.json, but remove it from startup."
Write-Output "- Refresh runtime helper scripts."
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

function Set-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-RelativeMemoryPath {
    param([string]$FullPath)
    $prefix = $memoryPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "File is outside .ai_memory: $FullPath" }
    return $FullPath.Substring($prefix.Length)
}

function Get-CompactField {
    param([string]$Text, [string[]]$Labels, [string]$Fallback)

    foreach ($label in $Labels) {
        $match = [regex]::Match($Text, ('(?m)^- \*\*' + [regex]::Escape($label) + '\*\*:\s*(.+)$'))
        if ($match.Success) {
            $value = ($match.Groups[1].Value -replace '\s+', ' ').Trim()
            if ($value.Length -gt 240) { return $value.Substring(0, 237) + "..." }
            return $value
        }
    }
    return $Fallback
}

$archiveRoot = Join-Path $targetRoot ".ai_memory_archive"
$migrationId = "migration-v3-" + (Get-Date).ToString("yyyyMMdd-HHmmssfff")
$finalArchive = Join-Path $archiveRoot $migrationId
$stagingArchive = Join-Path $archiveRoot (".staging-" + [guid]::NewGuid().ToString("N"))
$requirementsPath = Join-Path $memoryPath "requirements"
$requirementsAdded = -not (Test-Path -LiteralPath $requirementsPath)
$taskPackRoot = Join-Path $memoryPath "task-packs"
$taskPackName = "migrated-active-context-$migrationId.md"
$taskPackPath = Join-Path $taskPackRoot $taskPackName
$taskPackCreated = $false

$originalIndexBytes = [IO.File]::ReadAllBytes($indexPath)
$originalActiveBytes = if (Test-Path -LiteralPath $activePath) { [IO.File]::ReadAllBytes($activePath) } else { $null }
$originalAgentRulesBytes = if (Test-Path -LiteralPath $agentRulesPath) { [IO.File]::ReadAllBytes($agentRulesPath) } else { $null }
$oldActiveText = if (Test-Path -LiteralPath $activePath) { [IO.File]::ReadAllText($activePath, [Text.Encoding]::UTF8) } else { "" }
$oldActiveLineCount = if ($oldActiveText) { @($oldActiveText -split "`r?`n").Count } else { 0 }
$helperNames = @("search-memory.ps1", "memory-health.ps1", "record-requirement-change.ps1", "compact-memory.ps1", "migrate-memory.ps1", "claude-context-health.ps1")
$helperSnapshots = @{}
foreach ($helper in $helperNames) {
    $source = Join-Path $scriptRoot $helper
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $destination = Join-Path $targetRoot $helper
    $helperSnapshots[$destination] = [pscustomobject]@{
        Existed = Test-Path -LiteralPath $destination
        Bytes = if (Test-Path -LiteralPath $destination) { [IO.File]::ReadAllBytes($destination) } else { $null }
    }
}

try {
    New-Item -ItemType Directory -Path $stagingArchive -Force | Out-Null
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in Get-ChildItem -LiteralPath $memoryPath -Recurse -File) {
        $relative = Get-RelativeMemoryPath $file.FullName
        $archiveFile = Join-Path $stagingArchive $relative
        $archiveDirectory = Split-Path -Parent $archiveFile
        if (-not (Test-Path -LiteralPath $archiveDirectory)) { New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null }
        Copy-Item -LiteralPath $file.FullName -Destination $archiveFile
        $relativeForward = $relative.Replace('\', '/')
        $records.Add([ordered]@{
            source_path = ".ai_memory/$relativeForward"
            archive_path = ".ai_memory_archive/$migrationId/$relativeForward"
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
            preservation = "exact byte-for-byte pre-migration snapshot"
        })
    }

    $branch = "unknown"
    $head = "unknown"
    try { $branch = (& git -C $targetRoot branch --show-current 2>$null).Trim() } catch { }
    try { $head = (& git -C $targetRoot rev-parse HEAD 2>$null).Trim() } catch { }
    $manifest = [ordered]@{
        archive_version = "1.0.0"
        created_at = (Get-Date).ToString("o")
        repository_branch = $branch
        repository_head = $head
        purpose = "Preserve the complete pre-3.0 project memory before state-aware startup migration."
        policy = "Immutable migration backup. Never edit in place; verify SHA-256."
        files = $records.ToArray()
    }
    [IO.File]::WriteAllText((Join-Path $stagingArchive "manifest.json"), ($manifest | ConvertTo-Json -Depth 10), $utf8NoBom)
    Move-Item -LiteralPath $stagingArchive -Destination $finalArchive

    if (-not (Test-Path -LiteralPath $taskPackRoot)) { New-Item -ItemType Directory -Path $taskPackRoot -Force | Out-Null }
    if ($oldActiveText) {
        $archivePointer = ".ai_memory_archive/$migrationId/activeContext.md"
        if ($oldActiveText.Length -le 7000 -and $oldActiveLineCount -le 140) {
            $taskPackText = @"
# Migrated pre-V3 active context

- **Source**: ``$archivePointer``
- **Purpose**: preserve the former startup state without loading it in every session
- **Migration**: $migrationId

## Preserved content

$oldActiveText
"@
        } else {
            $taskPackText = @"
# Migrated pre-V3 active context

- **Source**: ``$archivePointer``
- **Purpose**: the former active context exceeded the task-pack budget and remains available only in the immutable archive
- **Migration**: $migrationId
- **Next action**: open the archived file only when the user explicitly continues that work
"@
        }
        Write-AtomicText -Path $taskPackPath -Content $taskPackText
        $taskPackCreated = $true
    }

    $templateIndex = Get-Content -Raw -Encoding UTF8 $templateIndexPath | ConvertFrom-Json
    if ($oldIndex.PSObject.Properties.Name -contains "bootstrap_order") {
        $oldIndex.PSObject.Properties.Remove("bootstrap_order")
    }
    Set-ObjectProperty -Object $oldIndex -Name "version" -Value "3.0.0"
    Set-ObjectProperty -Object $oldIndex -Name "startup_order" -Value ([object]@("activeContext.md"))
    if (-not ($oldIndex.PSObject.Properties.Name -contains "budgets")) { Set-ObjectProperty -Object $oldIndex -Name "budgets" -Value ([pscustomobject]@{}) }
    Set-ObjectProperty -Object $oldIndex.budgets -Name "startup" -Value $templateIndex.budgets.startup
    Set-ObjectProperty -Object $oldIndex.budgets -Name "active_context" -Value $templateIndex.budgets.active_context
    Set-ObjectProperty -Object $oldIndex.budgets -Name "task_pack" -Value $templateIndex.budgets.task_pack
    Set-ObjectProperty -Object $oldIndex.budgets -Name "progress" -Value $templateIndex.budgets.progress
    if (-not ($oldIndex.budgets.PSObject.Properties.Name -contains "index")) { Set-ObjectProperty -Object $oldIndex.budgets -Name "index" -Value ([pscustomobject]@{ hard_max_characters = 12000 }) }
    Set-ObjectProperty -Object $oldIndex -Name "required_before_work" -Value $templateIndex.required_before_work
    Set-ObjectProperty -Object $oldIndex -Name "compact_contract" -Value $templateIndex.compact_contract
    Set-ObjectProperty -Object $oldIndex -Name "health_checks" -Value $templateIndex.health_checks
    Set-ObjectProperty -Object $oldIndex -Name "resume_protocol" -Value @(
        "Read activeContext.md only after a fresh start or compaction."
        "Read the exact task pack and Resume Reads only for a real continuation."
        "Start a clean session between unrelated tasks instead of replaying conversation history."
    )
    if ($oldIndex.PSObject.Properties.Name -contains "file_roles") {
        Set-ObjectProperty -Object $oldIndex.file_roles -Name "projectbrief.md" -Value "on-demand durable project constitution"
        Set-ObjectProperty -Object $oldIndex.file_roles -Name "activeContext.md" -Value "only startup capsule"
        Set-ObjectProperty -Object $oldIndex.file_roles -Name "index.json" -Value "machine routes and budgets; never startup payload"
    }
    Write-AtomicText -Path $indexPath -Content ($oldIndex | ConvertTo-Json -Depth 50 -Compress)

    $baselineLine = "- **Requirement Baseline**: 0 ([UNINITIALIZED])"
    $baselineMatch = [regex]::Match($oldActiveText, '(?m)^- \*\*Requirement Baseline\*\*:\s*(.+)$')
    if ($baselineMatch.Success) { $baselineLine = "- **Requirement Baseline**: " + $baselineMatch.Groups[1].Value.Trim() }
    $stateMatch = [regex]::Match($oldActiveText, '\[(WIP|AWAITING_QA|REWORK|IDLE|PARKED)\]')
    $state = if ($stateMatch.Success) { "[$($stateMatch.Groups[1].Value)]" } elseif ($oldActiveText) { "[PARKED]" } else { "[IDLE]" }
    $taskIdMatch = [regex]::Match($baselineLine, '(REQ-\d+\s+v\d+)')
    $taskId = if ($taskIdMatch.Success) { $taskIdMatch.Groups[1].Value -replace '\s+', '-' } else { "none" }
    $currentGoalLabel = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5b2T5YmN55uu5qCH"))
    $recentCheckpointLabel = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5pyA6L+R5bey6aqM6K+BIENoZWNrcG9pbnQ="))
    $recentUnverifiedLabel = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5pyA6L+R5pyq6aqM6K+B5bel5L2c"))
    $goal = Get-CompactField -Text $oldActiveText -Labels @("Goal", $currentGoalLabel) -Fallback "Resume pre-V3 state only when the user explicitly asks."
    $checkpoint = Get-CompactField -Text $oldActiveText -Labels @("Latest verified checkpoint", $recentCheckpointLabel) -Fallback "Pre-V3 state preserved in the task pack and immutable archive."
    $unverified = Get-CompactField -Text $oldActiveText -Labels @("Unverified work", $recentUnverifiedLabel) -Fallback "See the migrated task pack when continuation is requested."
    $taskPackReference = if ($taskPackCreated) { "task-packs/$taskPackName" } else { "none" }
    $archiveReference = if ($oldActiveText) { ".ai_memory_archive/$migrationId/activeContext.md" } else { "none" }
    $capsule = @"
# Active Context Capsule
<!-- REQUIREMENT_BASELINE -->
$baselineLine
- **State**: $state
- **Task ID**: $taskId
- **Goal**: $goal
- **Stage**: migrated
- **Latest verified checkpoint**: $checkpoint
- **Unverified work**: $unverified
- **Next action**: follow the latest user request; open the task pack only for an explicit continuation
- **Blockers**: none recorded by migration
- **Do not break**: preserve existing project state and concurrent work
- **Task pack**: $taskPackReference
- **Resume Reads**: none
- **Archive pointer**: $archiveReference
- **Updated**: $((Get-Date).ToString("yyyy-MM-dd"))

## Capsule contract
- This is the only startup memory file. Keep it below 1,800 characters and 30 lines.
- If State is IDLE/PARKED or the task does not match the latest user request, do not open the old task pack.
- For a real continuation, read only the exact Task pack and Resume Reads listed above.
- Store raw wording, acceptance details, logs and handoff detail in the task pack or history, never here.
- After context compaction, reread only this capsule; never replay startup files or prior summaries.
"@
    Write-AtomicText -Path $activePath -Content $capsule

    $requirementsTemplate = Join-Path $templateMemory "requirements"
    if (-not (Test-Path -LiteralPath $requirementsPath)) {
        Copy-Item -LiteralPath $requirementsTemplate -Destination $requirementsPath -Recurse
        Get-ChildItem -LiteralPath $requirementsPath -Recurse -File | ForEach-Object {
            $text = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8).Replace("__DATE__", (Get-Date).ToString("yyyy-MM-dd"))
            [IO.File]::WriteAllText($_.FullName, $text, $utf8NoBom)
        }
    }

    if (Test-Path -LiteralPath $agentRulesPath) {
        $rulesText = [IO.File]::ReadAllText($agentRulesPath, [Text.Encoding]::UTF8)
        if ($rulesText -notmatch 'V3 state-aware startup override') {
            $override = @"
## V3 state-aware startup override
- This section supersedes any older Fast startup wording below: read activeContext.md only.
- index.json and projectbrief.md are on demand and must never be startup payload.
- After compaction, reread only the capsule and its exact task pack when continuation requires it.
- Never preserve full files, full tool output or prior summary text in handoff memory.

"@
            Write-AtomicText -Path $agentRulesPath -Content ($override + $rulesText)
        }
    }

    foreach ($helper in $helperNames) {
        $source = Join-Path $scriptRoot $helper
        $destination = Join-Path $targetRoot $helper
        if (Test-Path -LiteralPath $source) {
            [IO.File]::WriteAllText($destination, [IO.File]::ReadAllText($source, [Text.Encoding]::UTF8), $utf8NoBom)
        }
    }

    Get-ChildItem -LiteralPath $finalArchive -Recurse -File | ForEach-Object { $_.IsReadOnly = $true }
    Write-Output "APPLIED: memory migration to 3.0.0 completed."
    Write-Output "Backup: $finalArchive"
    Write-Output "Startup: activeContext.md only"
    Write-Output "Migrated task pack: $taskPackReference"
} catch {
    [IO.File]::WriteAllBytes($indexPath, $originalIndexBytes)
    if ($null -ne $originalActiveBytes) {
        [IO.File]::WriteAllBytes($activePath, $originalActiveBytes)
    } elseif (Test-Path -LiteralPath $activePath) {
        Remove-Item -LiteralPath $activePath -Force
    }
    if ($null -ne $originalAgentRulesBytes) { [IO.File]::WriteAllBytes($agentRulesPath, $originalAgentRulesBytes) }
    foreach ($destination in $helperSnapshots.Keys) {
        $snapshot = $helperSnapshots[$destination]
        if ($snapshot.Existed) {
            [IO.File]::WriteAllBytes($destination, $snapshot.Bytes)
        } elseif (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    if ($taskPackCreated -and (Test-Path -LiteralPath $taskPackPath)) { Remove-Item -LiteralPath $taskPackPath -Force }
    if ($requirementsAdded -and (Test-Path -LiteralPath $requirementsPath)) { Remove-Item -LiteralPath $requirementsPath -Recurse -Force }
    if (Test-Path -LiteralPath $stagingArchive) { Remove-Item -LiteralPath $stagingArchive -Recurse -Force }
    throw
}
