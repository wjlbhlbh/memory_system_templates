param(
    [string]$MemoryPath = ".ai_memory",
    [string]$Query = "",
    [string]$Tag = "",
    [string]$TaskId = "",
    [string]$Type = "",
    [string]$Since = "",
    [ValidateRange(1, 1000)]
    [int]$Limit = 50,
    [switch]$VerifyHash,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$resolvedMemory = (Resolve-Path -LiteralPath $MemoryPath).Path
$projectRoot = Split-Path -Parent $resolvedMemory
$indexPath = Join-Path $resolvedMemory "history/index.jsonl"
if (-not (Test-Path -LiteralPath $indexPath)) { throw "Missing memory history index: $indexPath" }

$records = @()
foreach ($line in Get-Content -Encoding UTF8 $indexPath) {
    if (-not $line.Trim()) { continue }
    $records += ($line | ConvertFrom-Json)
}

if ($Query) {
    $escapedQuery = [regex]::Escape($Query)
    $records = @($records | Where-Object {
        (($_.summary -as [string]) -match $escapedQuery) -or
        (($_.path -as [string]) -match $escapedQuery) -or
        (($_.task_id -as [string]) -match $escapedQuery) -or
        (($_.source_file -as [string]) -match $escapedQuery)
    })
}
if ($Tag) { $records = @($records | Where-Object { @($_.tags) -contains $Tag }) }
if ($TaskId) { $records = @($records | Where-Object { ($_.task_id -as [string]) -eq $TaskId }) }
if ($Type) { $records = @($records | Where-Object { ($_.type -as [string]) -eq $Type }) }
if ($Since) {
    $sinceDate = [DateTime]::Parse($Since)
    $records = @($records | Where-Object {
        try { [DateTime]::Parse(($_.date -as [string])) -ge $sinceDate } catch { $false }
    })
}

$records = @($records | Sort-Object date -Descending | Select-Object -First $Limit)

function Resolve-RecordPath {
    param([string]$RecordPath)
    if ($RecordPath -match '^\.ai_memory(_archive)?[/\\]') {
        return Join-Path $projectRoot ($RecordPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    }
    return Join-Path $resolvedMemory ($RecordPath.Replace('/', [IO.Path]::DirectorySeparatorChar))
}

if ($VerifyHash) {
    foreach ($record in $records) {
        $resolvedRecordPath = Resolve-RecordPath ([string]$record.path)
        if (-not (Test-Path -LiteralPath $resolvedRecordPath)) { throw "Indexed history path does not exist: $($record.path)" }
        if ($record.PSObject.Properties.Name -contains "sha256" -and $record.sha256) {
            $actualHash = (Get-FileHash -LiteralPath $resolvedRecordPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne ([string]$record.sha256).ToLowerInvariant()) { throw "History SHA-256 mismatch: $($record.path)" }
        }
    }
}

if ($Json) {
    $resultArray = @($records | ForEach-Object { $_ })
    ConvertTo-Json -InputObject $resultArray -Depth 10
    return
}

foreach ($record in $records) {
    $tags = (@($record.tags) -join ",")
    Write-Output "$($record.date) [$($record.task_id)] $($record.path) type=$($record.type) tags=$tags restore_required=$($record.restore_required)"
    Write-Output "  $($record.summary)"
}
