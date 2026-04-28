param(
    [string]$TargetPath = ".",
    [ValidateSet("Common", "AGENTS", "CLAUDE")]
    [string]$Mode = "Common",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTarget = (Resolve-Path $TargetPath).Path

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Copy-Adapter {
    param(
        [string]$TemplateRelativePath,
        [string]$DestinationFileName,
        [switch]$Overwrite
    )

    $source = Join-Path $scriptRoot $TemplateRelativePath
    $destination = Join-Path $resolvedTarget $DestinationFileName

    if ((Test-Path $destination) -and (-not $Overwrite)) {
        Write-Output "Skip existing: $destination"
        return
    }

    $content = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
    Write-TextFile -Path $destination -Content $content
    Write-Output "Wrote: $destination"
}

switch ($Mode) {
    "Common" {
        Copy-Adapter -TemplateRelativePath "tool_adapters\\AGENTS.md.template" -DestinationFileName "AGENTS.md" -Overwrite:$Force
        Copy-Adapter -TemplateRelativePath "tool_adapters\\CLAUDE.md.template" -DestinationFileName "CLAUDE.md" -Overwrite:$Force
    }
    "AGENTS" {
        Copy-Adapter -TemplateRelativePath "tool_adapters\\AGENTS.md.template" -DestinationFileName "AGENTS.md" -Overwrite:$Force
    }
    "CLAUDE" {
        Copy-Adapter -TemplateRelativePath "tool_adapters\\CLAUDE.md.template" -DestinationFileName "CLAUDE.md" -Overwrite:$Force
    }
}
