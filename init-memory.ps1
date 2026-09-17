param(
    [ValidateSet("Pro")]
    [string]$Mode = "Pro",
    [string]$TargetPath = ".",
    [string]$ProjectName = "",
    [ValidateSet("None", "Common", "AGENTS", "CLAUDE", "CODEX", "OPENCODE", "ANTIGRAVITY")]
    [string]$Adapter = "Common"
)

$ErrorActionPreference = "Stop"

function Detect-TechStack {
    param([string]$Root)

    $frontend = "TBD"
    $backend = "TBD"
    $database = "TBD"
    $test = "TBD"

    if (Test-Path (Join-Path $Root "package.json")) { $frontend = "Node.js / frontend project (package.json detected)" }
    if (Test-Path (Join-Path $Root "requirements.txt")) { $backend = "Python (requirements.txt detected)" }
    elseif (Test-Path (Join-Path $Root "pyproject.toml")) { $backend = "Python (pyproject.toml detected)" }
    elseif (Test-Path (Join-Path $Root "pom.xml")) { $backend = "Java (pom.xml detected)" }
    elseif (Test-Path (Join-Path $Root "Cargo.toml")) { $backend = "Rust (Cargo.toml detected)" }

    if (Test-Path (Join-Path $Root "docker-compose.yml")) { $database = "Check docker-compose.yml" }
    elseif (Test-Path (Join-Path $Root "docker-compose.yaml")) { $database = "Check docker-compose.yaml" }

    if (Test-Path (Join-Path $Root "pytest.ini")) { $test = "pytest" }
    elseif (Test-Path (Join-Path $Root "vitest.config.ts")) { $test = "Vitest" }
    elseif (Test-Path (Join-Path $Root "jest.config.js")) { $test = "Jest" }

    return @{
        Frontend = $frontend
        Backend = $backend
        Database = $database
        Test = $test
    }
}

function Get-FileText {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-FirstNonEmptyLine {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    foreach ($line in Get-Content $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("#")) {
            return $trimmed
        }
    }

    return $null
}

function Detect-VersionRequirements {
    param([string]$Root)

    $items = New-Object System.Collections.Generic.List[string]

    $pythonVersion = $null
    $pythonSource = $null
    $nodeVersion = $null
    $nodeSource = $null
    $javaVersion = $null
    $javaSource = $null
    $rustVersion = $null
    $rustSource = $null

    $pythonVersion = Get-FirstNonEmptyLine (Join-Path $Root ".python-version")
    if ($pythonVersion) {
        $pythonSource = ".python-version"
    }

    if (-not $pythonVersion) {
        $pyprojectPath = Join-Path $Root "pyproject.toml"
        $pyproject = Get-FileText $pyprojectPath
        if ($pyproject) {
            if ($pyproject -match '(?m)^\s*requires-python\s*=\s*["'']([^"'']+)["'']') {
                $pythonVersion = $matches[1].Trim()
                $pythonSource = "pyproject.toml: requires-python"
            } elseif ($pyproject -match '(?ms)\[tool\.poetry\.dependencies\](.*?)(^\[|\z)') {
                $poetrySection = $matches[1]
                if ($poetrySection -match '(?m)^\s*python\s*=\s*["'']([^"'']+)["'']') {
                    $pythonVersion = $matches[1].Trim()
                    $pythonSource = "pyproject.toml: [tool.poetry.dependencies].python"
                }
            }
        }
    }

    if (-not $pythonVersion) {
        $runtimeTxt = Get-FirstNonEmptyLine (Join-Path $Root "runtime.txt")
        if ($runtimeTxt -and $runtimeTxt -match '^python-?(.+)$') {
            $pythonVersion = $matches[1].Trim()
            $pythonSource = "runtime.txt"
        }
    }

    $nodeVersion = Get-FirstNonEmptyLine (Join-Path $Root ".nvmrc")
    if ($nodeVersion) {
        $nodeSource = ".nvmrc"
    }

    if (-not $nodeVersion) {
        $nodeVersion = Get-FirstNonEmptyLine (Join-Path $Root ".node-version")
        if ($nodeVersion) {
            $nodeSource = ".node-version"
        }
    }

    $packageJsonPath = Join-Path $Root "package.json"
    if ((-not $nodeVersion) -and (Test-Path $packageJsonPath)) {
        try {
            $packageJson = Get-Content -Raw $packageJsonPath -Encoding UTF8 | ConvertFrom-Json
            if ($packageJson.engines.node) {
                $nodeVersion = [string]$packageJson.engines.node
                $nodeSource = "package.json: engines.node"
            }
        } catch {
        }
    }

    $pomPath = Join-Path $Root "pom.xml"
    if (Test-Path $pomPath) {
        try {
            $pom = [xml](Get-Content -Raw $pomPath -Encoding UTF8)
            $properties = $pom.project.properties
            if ($properties) {
                foreach ($candidate in @("maven.compiler.release", "java.version", "maven.compiler.source", "maven.compiler.target")) {
                    $value = $properties.$candidate
                    if ($value -and $value.ToString().Trim()) {
                        $javaVersion = $value.ToString().Trim()
                        $javaSource = "pom.xml: $candidate"
                        break
                    }
                }
            }
        } catch {
        }
    }

    $rustToolchain = Get-FirstNonEmptyLine (Join-Path $Root "rust-toolchain")
    if ($rustToolchain) {
        $rustVersion = $rustToolchain
        $rustSource = "rust-toolchain"
    }

    if (-not $rustVersion) {
        $rustToolchainToml = Get-FileText (Join-Path $Root "rust-toolchain.toml")
        if ($rustToolchainToml -and $rustToolchainToml -match '(?m)^\s*channel\s*=\s*["'']([^"'']+)["'']') {
            $rustVersion = $matches[1].Trim()
            $rustSource = "rust-toolchain.toml: channel"
        }
    }

    if (-not $rustVersion) {
        $cargoToml = Get-FileText (Join-Path $Root "Cargo.toml")
        if ($cargoToml -and $cargoToml -match '(?m)^\s*rust-version\s*=\s*["'']([^"'']+)["'']') {
            $rustVersion = $matches[1].Trim()
            $rustSource = "Cargo.toml: rust-version"
        }
    }

    $dockerfilePath = Join-Path $Root "Dockerfile"
    $dockerfile = Get-FileText $dockerfilePath
    if ($dockerfile) {
        if ((-not $pythonVersion) -and ($dockerfile -match '(?im)^\s*FROM\s+python:([^\s]+)')) {
            $pythonVersion = $matches[1].Trim()
            $pythonSource = "Dockerfile"
        }
        if ((-not $nodeVersion) -and ($dockerfile -match '(?im)^\s*FROM\s+node:([^\s]+)')) {
            $nodeVersion = $matches[1].Trim()
            $nodeSource = "Dockerfile"
        }
        if ((-not $javaVersion) -and ($dockerfile -match '(?im)^\s*FROM\s+(?:eclipse-temurin|openjdk|amazoncorretto):([^\s]+)')) {
            $javaVersion = $matches[1].Trim()
            $javaSource = "Dockerfile"
        }
        if ((-not $rustVersion) -and ($dockerfile -match '(?im)^\s*FROM\s+rust:([^\s]+)')) {
            $rustVersion = $matches[1].Trim()
            $rustSource = "Dockerfile"
        }
    }

    if ($pythonVersion) {
        $items.Add("- **Python version requirement**: $pythonVersion (source: $pythonSource)")
    }
    if ($nodeVersion) {
        $items.Add("- **Node version requirement**: $nodeVersion (source: $nodeSource)")
    }
    if ($javaVersion) {
        $items.Add("- **Java version requirement**: $javaVersion (source: $javaSource)")
    }
    if ($rustVersion) {
        $items.Add("- **Rust version requirement**: $rustVersion (source: $rustSource)")
    }

    if ($items.Count -eq 0) {
        return "- **Runtime/toolchain version requirement**: no explicit requirement detected; leave empty if the project has no hard constraint."
    }

    return ($items -join "`r`n")
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$resolvedTarget = (Resolve-Path $TargetPath).Path
$templateName = ".ai_memory-pro"
$templatePath = Join-Path $scriptRoot $templateName
$destination = Join-Path $resolvedTarget ".ai_memory"

if (-not $ProjectName) {
    $ProjectName = Split-Path $resolvedTarget -Leaf
}

if (Test-Path $destination) {
    throw "Target path already exists: $destination"
}

Copy-Item -Recurse -Force $templatePath $destination

$dateText = Get-Date -Format "yyyy-MM-dd"
$tech = Detect-TechStack -Root $resolvedTarget
$versionRequirements = Detect-VersionRequirements -Root $resolvedTarget

function Replace-InFile {
    param(
        [string]$Path,
        [hashtable]$Replacements
    )

    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    foreach ($key in $Replacements.Keys) {
        $content = $content.Replace($key, $Replacements[$key])
    }
    Write-TextFile -Path $Path -Content $content
}

$commonReplacements = @{
    "__PROJECT_NAME__" = $ProjectName
    "__PROJECT_PATH__" = $resolvedTarget
    "__DATE__" = $dateText
    "__OS__" = $env:OS
    "__SHELL__" = "PowerShell"
    "__FRONTEND__" = $tech.Frontend
    "__BACKEND__" = $tech.Backend
    "__DATABASE__" = $tech.Database
    "__TEST__" = $tech.Test
    "__VERSION_REQUIREMENTS__" = $versionRequirements
}

Get-ChildItem -Path $destination -Recurse -File | ForEach-Object {
    if ($_.Extension -in @(".md", ".json", ".jsonl")) {
        Replace-InFile -Path $_.FullName -Replacements $commonReplacements
    }
}

function Copy-MemoryHelperScript {
    param(
        [string]$SourceFileName,
        [string]$DestinationFileName
    )

    $source = Join-Path $scriptRoot $SourceFileName
    $destinationFile = Join-Path $resolvedTarget $DestinationFileName

    if ((Test-Path $source) -and (-not (Test-Path $destinationFile))) {
        $content = [System.IO.File]::ReadAllText($source, [System.Text.Encoding]::UTF8)
        Write-TextFile -Path $destinationFile -Content $content
    }
}

Copy-MemoryHelperScript -SourceFileName "search-memory.ps1" -DestinationFileName "search-memory.ps1"
Copy-MemoryHelperScript -SourceFileName "memory-health.ps1" -DestinationFileName "memory-health.ps1"
Copy-MemoryHelperScript -SourceFileName "record-requirement-change.ps1" -DestinationFileName "record-requirement-change.ps1"
Copy-MemoryHelperScript -SourceFileName "compact-memory.ps1" -DestinationFileName "compact-memory.ps1"
Copy-MemoryHelperScript -SourceFileName "migrate-memory.ps1" -DestinationFileName "migrate-memory.ps1"
Copy-MemoryHelperScript -SourceFileName "claude-context-health.ps1" -DestinationFileName "claude-context-health.ps1"

function Copy-AdapterTemplate {
    param(
        [string]$TemplateRelativePath,
        [string]$DestinationFileName
    )

    $adapterTemplate = Join-Path $scriptRoot $TemplateRelativePath
    $adapterDestination = Join-Path $resolvedTarget $DestinationFileName

    if (Test-Path $adapterDestination) {
        throw "Tool entry file already exists: $adapterDestination"
    }

    $content = [System.IO.File]::ReadAllText($adapterTemplate, [System.Text.Encoding]::UTF8)
    Write-TextFile -Path $adapterDestination -Content $content
    return (Split-Path $adapterDestination -Leaf)
}

$generatedAdapters = New-Object System.Collections.Generic.List[string]
$adapterSummary = "No tool entry file generated"
if ($Adapter -ne "None") {
    switch ($Adapter) {
        "Common" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\AGENTS.md.template" -DestinationFileName "AGENTS.md"))
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\CLAUDE.md.template" -DestinationFileName "CLAUDE.md"))
        }
        "AGENTS" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\AGENTS.md.template" -DestinationFileName "AGENTS.md"))
        }
        "CLAUDE" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\CLAUDE.md.template" -DestinationFileName "CLAUDE.md"))
        }
        "CODEX" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\CODEX.template.md" -DestinationFileName "AGENTS.md"))
        }
        "OPENCODE" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\OPENCODE.template.md" -DestinationFileName "AGENTS.md"))
        }
        "ANTIGRAVITY" {
            $generatedAdapters.Add((Copy-AdapterTemplate -TemplateRelativePath "tool_adapters\\ANTIGRAVITY.template.md" -DestinationFileName "AGENTS.md"))
        }
    }

    $adapterSummary = "Generated tool entry files: $($generatedAdapters -join ', ')"
}

$todoPath = Join-Path $destination "SETUP_TODO.md"
$todo = @"
# Setup TODO

Initialized at: $dateText
Project name: $ProjectName
Project path: $resolvedTarget
Template mode: Pro
Tool adapter: $Adapter

## Fill these first
1. When the first real requirement or PRD arrives, initialize `requirements/current.md` and append `requirements/change-log.jsonl` before implementation.
2. Derive projectbrief.md business goals, users, success criteria, scope, non-goals, and do-not-break rules from the current requirement baseline. This file is on demand, not startup payload.
3. Check techContext.md and confirm detected stack/version requirements.
   - Do not repeatedly maintain stable host-machine facts such as Windows, PowerShell, or local machine versions.
   - Add runtime/toolchain versions only when the project truly depends on them.
   - If this script detected version requirements, verify that the source is a real project constraint.
4. Add the top 1-3 critical contracts in interfaces.md.
5. Fill architecture.md with the architecture map and core modules.
6. Keep activeContext.md as the single pointer-sized startup capsule. Put raw wording, acceptance detail, handoff evidence, and exact Resume Reads in the task pack.
7. If the project needs multiple LLM handoffs, split tasks in masterTaskLedger.md.
8. If a task has too much context, create a task pack under task-packs/ with required reading, do not read, acceptance, and handoff.
9. Keep root AGENTS.md and CLAUDE.md when possible so tool switching remains easy.
10. Run memory-health.ps1 after first initialization and every requirement baseline change. Claude Code users should also run claude-context-health.ps1.
11. If -Adapter did not generate entry files, copy the needed template from tool_adapters/ manually.

## Can be filled later
- decisionLog.md
- backlog.md
- pitfalls.md
- progress.md
- history/ archives; create them only when old logs or stale handoffs become long.

## Initialization result
- `.ai_memory` generated
- Project name, path, date, OS, and shell placeholders filled
- Static host facts usually do not need repeated manual maintenance
- $adapterSummary
- Runtime helpers generated: search, memory health, Claude context health, requirement change, compaction, and migration
- Initial requirement state is [UNINITIALIZED] until the first real user requirement or PRD is recorded
"@
Write-TextFile -Path $todoPath -Content $todo

Write-Output "Initialized .ai_memory at: $destination"
Write-Output "Mode: $Mode"
Write-Output "Project: $ProjectName"
Write-Output "Adapter: $Adapter"
Write-Output "Next: open .ai_memory\\SETUP_TODO.md"
