param(
    [string]$ProjectPath = ".",
    [string]$ClaudeConfigPath = (Join-Path $env:USERPROFILE ".claude"),
    [switch]$IncludeSessionMetrics,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-EstimatedTokenCount {
    param([string]$Text)

    if (-not $Text) { return 0 }
    $cjkCharacters = [regex]::Matches($Text, '[\p{IsCJKUnifiedIdeographs}\p{IsCJKSymbolsandPunctuation}\p{IsHiragana}\p{IsKatakana}\p{IsHangulSyllables}]').Count
    $otherCharacters = [Math]::Max(0, $Text.Length - $cjkCharacters)
    $lineOverhead = [Math]::Ceiling((@($Text -split "`r?`n").Count) / 2.0)
    return [int]($cjkCharacters + [Math]::Ceiling($otherCharacters / 3.0) + $lineOverhead)
}

function Test-PathScopedRule {
    param([string]$Text)
    return [regex]::IsMatch($Text, '(?ms)\A---\s*\r?\n.*?^paths\s*:.*?^---\s*$')
}

function Get-SkillDescription {
    param([string]$Text)
    $match = [regex]::Match($Text, '(?m)^description:\s*(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ""
}

function Convert-ToForwardPath {
    param([string]$Path)
    return ([IO.Path]::GetFullPath($Path)).Replace('\', '/')
}

$resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
try {
    $gitRoot = (& git -C $resolvedProject rev-parse --show-toplevel 2>$null).Trim()
    if ($gitRoot) { $resolvedProject = [IO.Path]::GetFullPath($gitRoot) }
} catch { }

$excludePatterns = @()
$userSettingsPath = Join-Path $ClaudeConfigPath "settings.json"
if (Test-Path -LiteralPath $userSettingsPath) {
    try {
        $settings = Get-Content -Raw -Encoding UTF8 $userSettingsPath | ConvertFrom-Json -Depth 50
        $excludePatterns += @($settings.claudeMdExcludes | Where-Object { $_ })
    } catch {
        $warnings.Add("Could not parse Claude settings.json for claudeMdExcludes.")
    }
}
$projectSettingsPath = Join-Path $resolvedProject ".claude\settings.local.json"
if (Test-Path -LiteralPath $projectSettingsPath) {
    try {
        $settings = Get-Content -Raw -Encoding UTF8 $projectSettingsPath | ConvertFrom-Json -Depth 50
        $excludePatterns += @($settings.claudeMdExcludes | Where-Object { $_ })
    } catch {
        $warnings.Add("Could not parse project settings.local.json for claudeMdExcludes.")
    }
}

function Test-ClaudeMdExcluded {
    param([string]$Path)
    $candidate = Convert-ToForwardPath -Path $Path
    foreach ($pattern in $excludePatterns) {
        $normalizedPattern = ([string]$pattern).Replace('\', '/')
        $wildcard = [Management.Automation.WildcardPattern]::new($normalizedPattern, [Management.Automation.WildcardOptions]::IgnoreCase)
        if ($wildcard.IsMatch($candidate)) { return $true }
    }
    return $false
}

$instructionCharacters = 0
$unscopedRuleCharacters = 0
$skillDescriptionCharacters = 0
$autoMemoryCharacters = 0
$memoryStartupCharacters = 0
$loadedInstructionFiles = 0
$unscopedRuleFiles = 0
$scopedRuleFiles = 0
$skillCount = 0
$sources = New-Object System.Collections.Generic.List[object]

foreach ($path in @(
    (Join-Path $ClaudeConfigPath "CLAUDE.md"),
    (Join-Path $resolvedProject "CLAUDE.md"),
    (Join-Path $resolvedProject ".claude\CLAUDE.md"),
    (Join-Path $resolvedProject "CLAUDE.local.md")
)) {
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and -not (Test-ClaudeMdExcluded -Path $path)) {
        $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        $instructionCharacters += $text.Length
        $loadedInstructionFiles++
        $sources.Add([pscustomobject]@{ category = "instruction"; path = $path; characters = $text.Length })
    }
}

foreach ($ruleRoot in @((Join-Path $ClaudeConfigPath "rules"), (Join-Path $resolvedProject ".claude\rules"))) {
    if (-not (Test-Path -LiteralPath $ruleRoot)) { continue }
    foreach ($rule in Get-ChildItem -LiteralPath $ruleRoot -Recurse -File -Filter "*.md") {
        if (Test-ClaudeMdExcluded -Path $rule.FullName) { continue }
        $text = [IO.File]::ReadAllText($rule.FullName, [Text.Encoding]::UTF8)
        if (Test-PathScopedRule -Text $text) {
            $scopedRuleFiles++
            continue
        }
        $unscopedRuleCharacters += $text.Length
        $unscopedRuleFiles++
        $sources.Add([pscustomobject]@{ category = "unscoped_rule"; path = $rule.FullName; characters = $text.Length })
    }
}

foreach ($skillRoot in @((Join-Path $ClaudeConfigPath "skills"), (Join-Path $resolvedProject ".claude\skills"))) {
    if (-not (Test-Path -LiteralPath $skillRoot)) { continue }
    foreach ($skill in Get-ChildItem -LiteralPath $skillRoot -Recurse -File -Filter "SKILL.md") {
        $description = Get-SkillDescription -Text ([IO.File]::ReadAllText($skill.FullName, [Text.Encoding]::UTF8))
        $skillDescriptionCharacters += $description.Length
        $skillCount++
    }
}

$projectKey = (Convert-ToForwardPath -Path $resolvedProject) -replace '[:/]', '-'
$projectKey = $projectKey.TrimStart('-')
$projectStateRoot = Join-Path (Join-Path $ClaudeConfigPath "projects") $projectKey
$autoMemoryPath = Join-Path $projectStateRoot "memory\MEMORY.md"
if (Test-Path -LiteralPath $autoMemoryPath) {
    $autoMemoryCharacters = [IO.File]::ReadAllText($autoMemoryPath, [Text.Encoding]::UTF8).Length
}

$memoryIndexPath = Join-Path $resolvedProject ".ai_memory\index.json"
if (Test-Path -LiteralPath $memoryIndexPath) {
    try {
        $memoryIndex = Get-Content -Raw -Encoding UTF8 $memoryIndexPath | ConvertFrom-Json
        foreach ($entry in @($memoryIndex.startup_order)) {
            $entryPath = Join-Path (Join-Path $resolvedProject ".ai_memory") $entry
            if (Test-Path -LiteralPath $entryPath -PathType Leaf) {
                $memoryStartupCharacters += [IO.File]::ReadAllText($entryPath, [Text.Encoding]::UTF8).Length
            }
        }
    } catch {
        $warnings.Add("Could not parse project .ai_memory/index.json.")
    }
}

$controllableText = New-Object Text.StringBuilder
foreach ($source in $sources) {
    [void]$controllableText.AppendLine([IO.File]::ReadAllText($source.path, [Text.Encoding]::UTF8))
}
if ($skillDescriptionCharacters -gt 0) { [void]$controllableText.Append(('x' * $skillDescriptionCharacters)) }
if ($autoMemoryCharacters -gt 0) { [void]$controllableText.Append(('x' * $autoMemoryCharacters)) }
if ($memoryStartupCharacters -gt 0) {
    try {
        foreach ($entry in @($memoryIndex.startup_order)) {
            $entryPath = Join-Path (Join-Path $resolvedProject ".ai_memory") $entry
            if (Test-Path -LiteralPath $entryPath -PathType Leaf) { [void]$controllableText.AppendLine([IO.File]::ReadAllText($entryPath, [Text.Encoding]::UTF8)) }
        }
    } catch { }
}
$estimatedControllableTokens = Get-EstimatedTokenCount -Text $controllableText.ToString()

if ($unscopedRuleCharacters -gt 10000) { $errors.Add("Unscoped Claude rules exceed 10,000 characters: $unscopedRuleCharacters") }
if ($memoryStartupCharacters -gt 1800) { $errors.Add("Project memory startup exceeds 1,800 characters: $memoryStartupCharacters") }
if ($estimatedControllableTokens -gt 12000) {
    $errors.Add("Estimated controllable startup exceeds 12,000 tokens: $estimatedControllableTokens")
} elseif ($estimatedControllableTokens -gt 9000) {
    $warnings.Add("Estimated controllable startup exceeds the 9,000-token warning level: $estimatedControllableTokens")
}
if ($skillDescriptionCharacters -gt 20000) { $warnings.Add("Skill descriptions exceed 20,000 characters: $skillDescriptionCharacters") }

$sessionMetrics = $null
if ($IncludeSessionMetrics -and (Test-Path -LiteralPath $projectStateRoot)) {
    $sessionFile = Get-ChildItem -LiteralPath $projectStateRoot -File -Filter "*.jsonl" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $sessionFile) {
        $initialCacheCreate = $null
        $compactTimestamps = New-Object System.Collections.Generic.List[datetime]
        $summaryCharacters = New-Object System.Collections.Generic.List[int]
        $largestToolResult = 0
        $expectSummary = $false
        foreach ($line in Get-Content -LiteralPath $sessionFile.FullName -Encoding UTF8) {
            try { $record = $line | ConvertFrom-Json -Depth 40 } catch { continue }
            if ($null -eq $initialCacheCreate -and $record.type -eq "assistant" -and $null -ne $record.message.usage) {
                $initialCacheCreate = [int]$record.message.usage.cache_creation_input_tokens
            }
            if ($record.type -eq "system" -and $record.subtype -eq "compact_boundary") {
                $compactTimestamps.Add([datetime]$record.timestamp)
                $expectSummary = $true
                continue
            }
            if ($expectSummary -and $record.type -eq "user") {
                $summaryText = if ($record.message.content -is [string]) { $record.message.content } else { (@($record.message.content | ForEach-Object { $_.text }) -join "") }
                $summaryCharacters.Add($summaryText.Length)
                $expectSummary = $false
            }
            if ($record.type -eq "user") {
                foreach ($block in @($record.message.content)) {
                    if ($block.type -eq "tool_result") {
                        $toolResultLength = ([string]$block.content).Length
                        if ($toolResultLength -gt $largestToolResult) { $largestToolResult = $toolResultLength }
                    }
                }
            }
        }
        $rapidCompactions = 0
        for ($i = 1; $i -lt $compactTimestamps.Count; $i++) {
            if (($compactTimestamps[$i] - $compactTimestamps[$i - 1]).TotalMinutes -lt 15) { $rapidCompactions++ }
        }
        $sessionMetrics = [ordered]@{
            file = $sessionFile.FullName
            last_write_time = $sessionFile.LastWriteTime.ToString("o")
            initial_cache_creation_tokens = $initialCacheCreate
            compactions = $compactTimestamps.Count
            rapid_compactions_under_15_minutes = $rapidCompactions
            summary_characters = @($summaryCharacters)
            max_summary_characters = if ($summaryCharacters.Count -gt 0) { ($summaryCharacters | Measure-Object -Maximum).Maximum } else { 0 }
            largest_tool_result_characters = $largestToolResult
            note = "Historical telemetry; start a fresh session after configuration changes for post-change verification."
        }
    }
}

$status = if ($errors.Count -eq 0) { "PASS" } else { "FAIL" }
$result = [ordered]@{
    status = $status
    project = $resolvedProject
    instruction_files = $loadedInstructionFiles
    instruction_characters = $instructionCharacters
    unscoped_rule_files = $unscopedRuleFiles
    unscoped_rule_characters = $unscopedRuleCharacters
    scoped_rule_files = $scopedRuleFiles
    skills = $skillCount
    skill_description_characters = $skillDescriptionCharacters
    auto_memory_characters = $autoMemoryCharacters
    memory_startup_characters = $memoryStartupCharacters
    estimated_controllable_startup_tokens = $estimatedControllableTokens
    estimated_token_method = "CJK characters + other characters / 3 + line overhead"
    excluded_patterns = @($excludePatterns)
    recent_session = $sessionMetrics
    warnings = @($warnings)
    errors = @($errors)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 10
} else {
    Write-Output "Status: $status"
    Write-Output "Instructions: $loadedInstructionFiles files / $instructionCharacters characters"
    Write-Output "Unscoped rules: $unscopedRuleFiles files / $unscopedRuleCharacters characters"
    Write-Output "Scoped rules: $scopedRuleFiles files"
    Write-Output "Skills: $skillCount / descriptions $skillDescriptionCharacters characters"
    Write-Output "Auto memory: $autoMemoryCharacters characters"
    Write-Output "Project memory startup: $memoryStartupCharacters characters"
    Write-Output "Estimated controllable startup: $estimatedControllableTokens tokens"
    if ($null -ne $sessionMetrics) {
        Write-Output "Latest historical session: initial $($sessionMetrics.initial_cache_creation_tokens) tokens / compactions $($sessionMetrics.compactions) / max summary $($sessionMetrics.max_summary_characters) characters"
    }
    foreach ($warning in $warnings) { Write-Output "WARN: $warning" }
    foreach ($healthError in $errors) { Write-Output "ERROR: $healthError" }
}

if ($errors.Count -gt 0) { exit 1 }
exit 0
