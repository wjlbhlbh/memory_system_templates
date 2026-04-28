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

    $frontend = "待确认"
    $backend = "待确认"
    $database = "待确认"
    $test = "待确认"

    if (Test-Path (Join-Path $Root "package.json")) { $frontend = "Node.js / 前端工程（检测到 package.json）" }
    if (Test-Path (Join-Path $Root "requirements.txt")) { $backend = "Python（检测到 requirements.txt）" }
    elseif (Test-Path (Join-Path $Root "pyproject.toml")) { $backend = "Python（检测到 pyproject.toml）" }
    elseif (Test-Path (Join-Path $Root "pom.xml")) { $backend = "Java（检测到 pom.xml）" }
    elseif (Test-Path (Join-Path $Root "Cargo.toml")) { $backend = "Rust（检测到 Cargo.toml）" }

    if (Test-Path (Join-Path $Root "docker-compose.yml")) { $database = "请查看 docker-compose.yml 确认" }
    elseif (Test-Path (Join-Path $Root "docker-compose.yaml")) { $database = "请查看 docker-compose.yaml 确认" }

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
        $items.Add("- **Python 版本要求**：$pythonVersion（来源：$pythonSource）")
    }
    if ($nodeVersion) {
        $items.Add("- **Node 版本要求**：$nodeVersion（来源：$nodeSource）")
    }
    if ($javaVersion) {
        $items.Add("- **Java 版本要求**：$javaVersion（来源：$javaSource）")
    }
    if ($rustVersion) {
        $items.Add("- **Rust 版本要求**：$rustVersion（来源：$rustSource）")
    }

    if ($items.Count -eq 0) {
        return "- **运行时/工具链版本要求**：未自动识别到明确要求；如项目无强约束，可留空。"
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
    throw "目标路径已存在: $destination"
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
    if ($_.Extension -in @(".md", ".json")) {
        Replace-InFile -Path $_.FullName -Replacements $commonReplacements
    }
}

function Copy-AdapterTemplate {
    param(
        [string]$TemplateRelativePath,
        [string]$DestinationFileName
    )

    $adapterTemplate = Join-Path $scriptRoot $TemplateRelativePath
    $adapterDestination = Join-Path $resolvedTarget $DestinationFileName

    if (Test-Path $adapterDestination) {
        throw "工具入口文件已存在: $adapterDestination"
    }

    $content = [System.IO.File]::ReadAllText($adapterTemplate, [System.Text.Encoding]::UTF8)
    Write-TextFile -Path $adapterDestination -Content $content
    return (Split-Path $adapterDestination -Leaf)
}

$generatedAdapters = New-Object System.Collections.Generic.List[string]
$adapterSummary = "未生成工具入口文件"
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

    $adapterSummary = "已生成工具入口文件：$($generatedAdapters -join '、')"
}

$todoPath = Join-Path $destination "SETUP_TODO.md"
$todo = @"
# 初始化待补事项 (Setup TODO)

初始化时间：$dateText
项目名称：$ProjectName
项目路径：$resolvedTarget
模板模式：Pro
工具适配器：$Adapter

## 只需要优先补这些
1. 在 projectbrief.md 中补齐业务目标、目标用户、成功标准、项目边界
2. 在 techContext.md 中确认自动探测出的技术栈是否准确
   - 不需要反复维护“Windows / PowerShell / 个人机器版本”这类稳定宿主机信息
   - 只有项目明确依赖某个运行时或工具链版本时，才补对应版本要求
   - 若脚本已识别出版本要求，优先核对其来源是否符合项目真实约束
3. 补 interfaces.md 中最关键的 1-3 个接口
4. 补 architecture.md 中总体架构与核心模块
5. 默认推荐保留根目录 `AGENTS.md` 和 `CLAUDE.md`，避免后续切换工具时忘记补入口文件
6. 如果你没有使用 `-Adapter` 自动生成入口文件，再从 `tool_adapters/` 里选择对应模板手工复制到项目根目录

## 可以后补的
- decisionLog.md
- backlog.md
- pitfalls.md
- progress.md

## 初始化结果
- `.ai_memory` 已生成
- 项目名、路径、日期、操作系统、默认终端已自动填入
- 宿主机静态环境信息默认无需你手工重复维护
- $adapterSummary
- 当前状态已设为可直接开始工作的初始态
"@
Write-TextFile -Path $todoPath -Content $todo

Write-Output "Initialized .ai_memory at: $destination"
Write-Output "Mode: $Mode"
Write-Output "Project: $ProjectName"
Write-Output "Adapter: $Adapter"
Write-Output "Next: open .ai_memory\\SETUP_TODO.md"
