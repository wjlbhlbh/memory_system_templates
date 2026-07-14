param(
    [string]$MemoryPath = ".ai_memory",
    [string]$ActiveContextReplacementPath = "",
    [string]$ProgressReplacementPath = "",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$resolvedMemory = (Resolve-Path -LiteralPath $MemoryPath).Path
$projectRoot = Split-Path -Parent $resolvedMemory
$indexPath = Join-Path $resolvedMemory "index.json"
$historyIndexPath = Join-Path $resolvedMemory "history\index.jsonl"
$index = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json

function Get-MetricsFromBytes {
    param([byte[]]$Bytes)
    $text = $strictUtf8.GetString($Bytes)
    $lineLengths = @($text -split "`r?`n" | ForEach-Object { $_.Length })
    $maximumLine = if ($lineLengths.Count -gt 0) { ($lineLengths | Measure-Object -Maximum).Maximum } else { 0 }
    return [pscustomobject]@{
        Text = $text
        Bytes = $Bytes.Length
        Characters = $text.Length
        Lines = $lineLengths.Count
        MaxLineCharacters = $maximumLine
    }
}

function Write-AtomicBytes {
    param([string]$Path, [byte[]]$Bytes)
    $tempPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllBytes($tempPath, $Bytes)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

$replacements = New-Object System.Collections.Generic.List[object]
if ($ActiveContextReplacementPath) {
    $replacement = (Resolve-Path -LiteralPath $ActiveContextReplacementPath).Path
    $replacements.Add([pscustomobject]@{ Name = "activeContext.md"; Target = (Join-Path $resolvedMemory "activeContext.md"); Replacement = $replacement; Budget = $index.budgets.active_context })
}
if ($ProgressReplacementPath) {
    $replacement = (Resolve-Path -LiteralPath $ProgressReplacementPath).Path
    $replacements.Add([pscustomobject]@{ Name = "progress.md"; Target = (Join-Path $resolvedMemory "progress.md"); Replacement = $replacement; Budget = $index.budgets.progress })
}
if ($replacements.Count -eq 0) {
    throw "Provide at least one replacement path."
}

$prepared = New-Object System.Collections.Generic.List[object]
foreach ($item in $replacements) {
    if (-not (Test-Path -LiteralPath $item.Target)) { throw "Missing target memory file: $($item.Target)" }
    $originalBytes = [IO.File]::ReadAllBytes($item.Target)
    $replacementBytes = [IO.File]::ReadAllBytes($item.Replacement)
    $originalMetrics = Get-MetricsFromBytes $originalBytes
    $replacementMetrics = Get-MetricsFromBytes $replacementBytes
    if ($replacementMetrics.Characters -gt [int]$item.Budget.hard_max_characters) {
        throw "$($item.Name) replacement exceeds hard character budget."
    }
    if ($item.Budget.PSObject.Properties.Name -contains "hard_max_lines") {
        if ($replacementMetrics.Lines -gt [int]$item.Budget.hard_max_lines) { throw "$($item.Name) replacement exceeds line budget." }
    }
    if ($item.Budget.PSObject.Properties.Name -contains "max_single_line_characters") {
        if ($replacementMetrics.MaxLineCharacters -gt [int]$item.Budget.max_single_line_characters) { throw "$($item.Name) replacement exceeds single-line budget." }
    }
    $prepared.Add([pscustomobject]@{
        Name = $item.Name
        Target = $item.Target
        OriginalBytes = $originalBytes
        OriginalMetrics = $originalMetrics
        ReplacementBytes = $replacementBytes
        ReplacementMetrics = $replacementMetrics
        OriginalHash = (Get-FileHash -LiteralPath $item.Target -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

$startupCharacters = 0
foreach ($entry in @($index.startup_order)) {
    $matching = @($prepared | Where-Object { $_.Name -eq $entry }) | Select-Object -First 1
    if ($null -ne $matching) {
        $startupCharacters += $matching.ReplacementMetrics.Characters
    } else {
        $startupCharacters += ([IO.File]::ReadAllText((Join-Path $resolvedMemory $entry), [Text.Encoding]::UTF8)).Length
    }
}
if ($startupCharacters -gt [int]$index.budgets.startup.hard_max_characters) {
    throw "Replacement startup capsule exceeds hard character budget."
}

if (-not $Apply) {
    Write-Output "DRY RUN: no files were changed."
    foreach ($item in $prepared) {
        Write-Output "$($item.Name): $($item.OriginalMetrics.Characters) -> $($item.ReplacementMetrics.Characters) characters"
    }
    return
}

$archiveRoot = Join-Path $projectRoot ".ai_memory_archive"
$archiveId = (Get-Date).ToString("yyyyMMdd-HHmmssfff")
$finalArchive = Join-Path $archiveRoot $archiveId
$stagingArchive = Join-Path $archiveRoot (".staging-" + [guid]::NewGuid().ToString("N"))
$historyOriginal = [IO.File]::ReadAllBytes($historyIndexPath)
$archiveCommitted = $false

try {
    New-Item -ItemType Directory -Path $stagingArchive -Force | Out-Null
    $fileRecords = New-Object System.Collections.Generic.List[object]
    foreach ($item in $prepared) {
        $archiveFile = Join-Path $stagingArchive $item.Name
        [IO.File]::WriteAllBytes($archiveFile, $item.OriginalBytes)
        $copiedHash = (Get-FileHash -LiteralPath $archiveFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($copiedHash -ne $item.OriginalHash) { throw "Archive copy hash mismatch: $($item.Name)" }
        $fileRecords.Add([ordered]@{
            source_path = ".ai_memory/$($item.Name)"
            archive_path = ".ai_memory_archive/$archiveId/$($item.Name)"
            bytes = $item.OriginalMetrics.Bytes
            characters = $item.OriginalMetrics.Characters
            lines = $item.OriginalMetrics.Lines
            sha256 = $item.OriginalHash
            preservation = "exact byte-for-byte snapshot before replacement"
        })
    }

    $branch = "none"
    $head = "none"
    if (Test-Path -LiteralPath (Join-Path $projectRoot ".git")) {
        $branchResult = @(& git -C $projectRoot rev-parse --abbrev-ref HEAD)
        if ($LASTEXITCODE -eq 0 -and $branchResult.Count -gt 0) { $branch = [string]$branchResult[0] }
        $headResult = @(& git -C $projectRoot rev-parse HEAD)
        if ($LASTEXITCODE -eq 0 -and $headResult.Count -gt 0) { $head = [string]$headResult[0] }
    }

    $manifest = [ordered]@{
        archive_version = "1.0.0"
        created_at = (Get-Date).ToString("o")
        repository_branch = $branch
        repository_head = $head
        purpose = "Preserve exact memory files before bounded replacement."
        policy = "Immutable archive. Never edit in place; verify SHA-256."
        files = @($fileRecords | ForEach-Object { $_ })
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $stagingArchive "manifest.json"), $manifestJson, $utf8NoBom)

    Move-Item -LiteralPath $stagingArchive -Destination $finalArchive
    $archiveCommitted = $true

    foreach ($item in $prepared) {
        Write-AtomicBytes -Path $item.Target -Bytes $item.ReplacementBytes
    }

    $historyLines = @([IO.File]::ReadAllLines($historyIndexPath, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
    foreach ($record in $fileRecords) {
        $historyRecord = [ordered]@{
            date = (Get-Date).ToString("yyyy-MM-dd")
            type = "memory-compaction"
            tags = @("memory", "archive", "compaction")
            summary = "Exact pre-compaction snapshot of $($record.source_path)."
            path = $record.archive_path
            task_id = "none"
            source_file = $record.source_path
            verification_evidence = "SHA-256 $($record.sha256)"
            restore_required = $false
            sha256 = $record.sha256
            bytes = $record.bytes
            archive_id = $archiveId
        }
        $historyLines += ($historyRecord | ConvertTo-Json -Depth 8 -Compress)
    }
    Write-AtomicBytes -Path $historyIndexPath -Bytes $utf8NoBom.GetBytes((($historyLines -join "`n") + "`n"))

    Get-ChildItem -LiteralPath $finalArchive -Recurse -File | ForEach-Object { $_.IsReadOnly = $true }
    Write-Output "APPLIED: memory replacement and archive completed."
    Write-Output "Archive: $finalArchive"
} catch {
    foreach ($item in $prepared) {
        Write-AtomicBytes -Path $item.Target -Bytes $item.OriginalBytes
    }
    Write-AtomicBytes -Path $historyIndexPath -Bytes $historyOriginal
    if (Test-Path -LiteralPath $stagingArchive) {
        Remove-Item -LiteralPath $stagingArchive -Recurse -Force
    }
    if ($archiveCommitted -and (Test-Path -LiteralPath $finalArchive)) {
        Get-ChildItem -LiteralPath $finalArchive -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
        Remove-Item -LiteralPath $finalArchive -Recurse -Force
    }
    throw
}
