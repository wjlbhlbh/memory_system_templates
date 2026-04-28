param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-RelativePath {
    param([string]$Path)
    return $Path.Substring($Root.Length + 1)
}

function Assert-Utf8NoBom {
    param([System.IO.FileInfo]$File)

    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $relative = Get-RelativePath $File.FullName

    try {
        $null = $strictUtf8.GetString($bytes)
    } catch {
        throw "Invalid UTF-8: $relative"
    }

    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasUtf8Bom) "UTF-8 BOM is not allowed for agent-readable files: $relative"
}

function Assert-IndexIsComplete {
    param([string]$MemoryPath)

    $indexPath = Join-Path $MemoryPath "index.json"
    Assert-True (Test-Path $indexPath) "Missing index.json in $MemoryPath"

    $index = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json
    foreach ($entry in $index.bootstrap_order) {
        $entryPath = Join-Path $MemoryPath $entry
        Assert-True (Test-Path $entryPath) "bootstrap_order references missing file: $entryPath"
    }
}

Write-Output "Checking repository text encodings..."
$agentReadableFiles = Get-ChildItem -Path $Root -Recurse -File |
    Where-Object {
        $_.FullName -notmatch "\\(\.git|\.archive|tmp-common-adapter-test|tmp-sync-adapter-test)\\" -and
        $_.Extension -in @(".md", ".json", ".template", ".txt")
    }

foreach ($file in $agentReadableFiles) {
    Assert-Utf8NoBom $file
}

Write-Output "Checking memory indexes..."
Assert-True (-not (Test-Path (Join-Path $Root ".ai_memory-lite"))) "Lite template should not exist in Pro-only mode."
Assert-IndexIsComplete (Join-Path $Root ".ai_memory-pro")

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("memory-system-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    Write-Output "Checking init-memory.ps1 output..."
    & (Join-Path $Root "init-memory.ps1") -Mode Pro -TargetPath $tempRoot -ProjectName "EncodingTest" -Adapter Common | Out-Null

    $generatedFiles = Get-ChildItem -Path $tempRoot -Recurse -File |
        Where-Object { $_.Extension -in @(".md", ".json") -or $_.Name -in @("AGENTS.md", "CLAUDE.md") }

    foreach ($file in $generatedFiles) {
        Assert-Utf8NoBom $file
    }

    Get-Content -Raw -Encoding UTF8 (Join-Path $tempRoot ".ai_memory\index.json") | ConvertFrom-Json | Out-Null

    Write-Output "Checking Lite mode is unavailable..."
    $liteRoot = Join-Path $tempRoot "lite"
    New-Item -ItemType Directory -Path $liteRoot | Out-Null
    $liteRejected = $false
    try {
        & (Join-Path $Root "init-memory.ps1") -Mode Lite -TargetPath $liteRoot -ProjectName "LiteTest" -Adapter None | Out-Null
    } catch {
        $liteRejected = $_.Exception.Message -match "Cannot validate argument"
    }
    Assert-True $liteRejected "Lite mode should be rejected."

    Write-Output "Checking sync-tool-adapters.ps1 output..."
    $syncRoot = Join-Path $tempRoot "sync"
    New-Item -ItemType Directory -Path $syncRoot | Out-Null
    & (Join-Path $Root "sync-tool-adapters.ps1") -TargetPath $syncRoot -Mode Common | Out-Null

    foreach ($fileName in @("AGENTS.md", "CLAUDE.md")) {
        Assert-Utf8NoBom (Get-Item (Join-Path $syncRoot $fileName))
    }
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Output "Memory system verification passed."
