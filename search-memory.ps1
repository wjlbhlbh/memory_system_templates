param(
    [string]$MemoryPath = ".ai_memory",
    [string]$Query = "",
    [string]$Tag = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$indexPath = Join-Path $MemoryPath "history/index.jsonl"
if (-not (Test-Path $indexPath)) {
    throw "Missing memory history index: $indexPath"
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($line in Get-Content -Encoding UTF8 $indexPath) {
    if (-not $line.Trim()) { continue }
    $records.Add(($line | ConvertFrom-Json))
}

if ($Query) {
    $records = @($records | Where-Object {
        (($_.summary -as [string]) -match [regex]::Escape($Query)) -or
        (($_.path -as [string]) -match [regex]::Escape($Query)) -or
        (($_.task_id -as [string]) -match [regex]::Escape($Query)) -or
        (($_.source_file -as [string]) -match [regex]::Escape($Query))
    })
}

if ($Tag) {
    $records = @($records | Where-Object {
        $tags = @($_.tags)
        $tags -contains $Tag
    })
}

if ($Json) {
    $records | ConvertTo-Json -Depth 8
    return
}

foreach ($record in $records) {
    $tags = (@($record.tags) -join ",")
    Write-Output "$($record.date) [$($record.task_id)] $($record.path) tags=$tags restore_required=$($record.restore_required)"
    Write-Output "  $($record.summary)"
}
