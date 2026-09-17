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

    $rootPrefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($Path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($rootPrefix.Length)
    }

    return $Path
}

$externalDisplayPath = Join-Path ([IO.Path]::GetTempPath()) "memory-system-external-display-test.md"
$externalDisplayResult = Get-RelativePath $externalDisplayPath
Assert-True ($externalDisplayResult -eq $externalDisplayPath) "Get-RelativePath must preserve paths outside the verification root."

function Get-TextMetrics {
    param([string]$Path)

    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $lineLengths = @($text -split "`r?`n" | ForEach-Object { $_.Length })
    $maximumLine = if ($lineLengths.Count -gt 0) { ($lineLengths | Measure-Object -Maximum).Maximum } else { 0 }

    return [pscustomobject]@{
        Bytes = (Get-Item -LiteralPath $Path).Length
        Characters = $text.Length
        Lines = $lineLengths.Count
        MaxLineCharacters = $maximumLine
    }
}

function Assert-Utf8NoBom {
    param([System.IO.FileInfo]$File)

    $bytes = [System.IO.File]::ReadAllBytes($File.FullName)
    $relative = Get-RelativePath $File.FullName

    try {
        $text = $strictUtf8.GetString($bytes)
    } catch {
        throw "Invalid UTF-8: $relative"
    }

    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasUtf8Bom) "UTF-8 BOM is not allowed for agent-readable files: $relative"
    Assert-NoMojibakeText -Text $text -RelativePath $relative
    Assert-NoSensitiveMaterial -Text $text -RelativePath $relative
}

function Assert-NoMojibakeText {
    param(
        [string]$Text,
        [string]$RelativePath
    )

    $mojibakePattern = "\uFFFD|\u00C3.|\u00C2.|\u00E2\u20AC|\u9225|\u951B|\u9286|\u4E53|\u8E47\uE102\u20AC|\u6D93\u20AC|\u9428"
    Assert-True ($Text -notmatch $mojibakePattern) "Possible mojibake text in $RelativePath. Read/write agent-readable files as explicit UTF-8, then repair the readable source text before continuing."
    Assert-True ($Text -notmatch '[\x00-\x08\x0B\x0C\x0E-\x1F]') "Unexpected control character in $RelativePath. Check PowerShell here-string backtick escaping."
}

function Assert-NoSensitiveMaterial {
    param(
        [string]$Text,
        [string]$RelativePath
    )

    $secretPatterns = @(
        "-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----",
        "\bAKIA[0-9A-Z]{16}\b",
        "\bghp_[A-Za-z0-9_]{30,}\b",
        "\bsk-[A-Za-z0-9_-]{24,}\b",
        "\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
        "(postgres|mysql|mongodb)://[^`"\s]+:[^`"\s]+@"
    )

    foreach ($pattern in $secretPatterns) {
        Assert-True ($Text -notmatch $pattern) "Possible secret material in $RelativePath. Memory files must not store credentials, tokens, private keys, or connection strings."
    }
}

function Assert-ToolAgnosticText {
    param(
        [string]$Text,
        [string]$Name
    )

    Assert-True ($Text -notmatch "\b(view_file|read_file|edit_file|write_file|replace_in_file)\b") "$Name must not require or mention a specific file-tool API name."
    Assert-True ($Text -match "available (file )?(read|edit|write|search) capability|current environment|equivalent capability") "$Name must tell agents to use whatever equivalent capability exists in the current environment."
}

function Assert-NoHardcodedLocalDocPath {
    param([System.IO.FileInfo]$File)

    $relative = Get-RelativePath $File.FullName
    $text = Get-Content -Raw -Encoding UTF8 $File.FullName
    $forbiddenPatterns = @(
        "D:\\AIbiancheng\\memory_system_templates",
        "C:\\Users\\[^\\]+",
        "[A-Za-z]:\\[^`r`n]*\\memory_system_templates\\(init-memory|sync-tool-adapters|search-memory)\.ps1"
    )

    foreach ($pattern in $forbiddenPatterns) {
        Assert-True ($text -notmatch $pattern) "Public docs must not hardcode local machine paths. Use cloned repository variables or relative commands instead: $relative"
    }
}

function Assert-PrimaryMemoryWindowRules {
    param(
        [string]$ActiveContext,
        [string]$Progress,
        [string]$Name
    )

    Assert-True ($ActiveContext -match "only startup memory file|startup capsule") "$Name activeContext.md must define a bounded startup capsule."
    Assert-True ($ActiveContext -match "task pack|task-packs/|history") "$Name activeContext.md must route overflow detail to task packs or history."
    Assert-True ($ActiveContext -match "After context compaction") "$Name activeContext.md must define post-compaction recovery."
    Assert-True ($Progress -match "rolling window|active window") "$Name progress.md must define a bounded rolling window."
    Assert-True ($Progress -match "archive index|history/") "$Name progress.md must keep archive links instead of unlimited detail."
}

function Assert-PrimaryMemoryHealth {
    param([string]$MemoryPath)

    $activeContextPath = Join-Path $MemoryPath "activeContext.md"
    $progressPath = Join-Path $MemoryPath "progress.md"
    $activeContext = Get-Content -Raw -Encoding UTF8 $activeContextPath
    $progress = Get-Content -Raw -Encoding UTF8 $progressPath
    $index = Get-Content -Raw -Encoding UTF8 (Join-Path $MemoryPath "index.json") | ConvertFrom-Json
    $activeMetrics = Get-TextMetrics $activeContextPath
    $progressMetrics = Get-TextMetrics $progressPath

    Assert-True ($activeMetrics.Lines -le $index.budgets.active_context.hard_max_lines) "activeContext.md must stay within its active-window line budget; current line count: $($activeMetrics.Lines)"
    Assert-True ($activeMetrics.Characters -le $index.budgets.active_context.hard_max_characters) "activeContext hard character budget exceeded: $($activeMetrics.Characters)"
    Assert-True ($activeMetrics.MaxLineCharacters -le $index.budgets.active_context.max_single_line_characters) "activeContext single-line budget exceeded: $($activeMetrics.MaxLineCharacters)"
    Assert-True ($progressMetrics.Lines -le $index.budgets.progress.hard_max_lines) "progress.md must stay within its rolling-window line budget; current line count: $($progressMetrics.Lines)"
    Assert-True ($progressMetrics.Characters -le $index.budgets.progress.hard_max_characters) "progress hard character budget exceeded: $($progressMetrics.Characters)"

    $checkpointMatches = [regex]::Matches($progress, "CHK-\d{3}") | ForEach-Object { $_.Value }
    $duplicates = $checkpointMatches | Group-Object | Where-Object { $_.Count -gt 1 }
    Assert-True ($duplicates.Count -eq 0) "progress.md must not duplicate checkpoint ids."

    $resumeLine = ($activeContext -split "`n") | Where-Object { $_ -match "Resume Reads" } | Select-Object -First 1
    if ($resumeLine) {
        $resumeRefs = [regex]::Matches($resumeLine, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value }
        foreach ($ref in $resumeRefs) {
            if ($ref -match "\.(md|json|jsonl|txt)$") {
                Assert-True (Test-Path (Join-Path $MemoryPath $ref)) "activeContext.md Resume Reads references missing file: $ref"
            }
        }
    }
}

function Assert-MemoryHub {
    param([string]$MemoryPath)

    $memoryHubPath = Join-Path $MemoryPath "MEMORY.md"
    Assert-True (Test-Path $memoryHubPath) "Missing MEMORY.md hub in $MemoryPath"

    $memoryHub = Get-Content -Raw -Encoding UTF8 $memoryHubPath
    $lineCount = (Get-Content -Encoding UTF8 $memoryHubPath).Count
    Assert-True ($lineCount -le 200) "MEMORY.md must stay concise as an on-demand routing map; current line count: $lineCount"
    Assert-True ($memoryHub -match "State-aware startup") "MEMORY.md must explain state-aware startup."
    Assert-True ($memoryHub -match "activeContext\.md.*only") "MEMORY.md must identify activeContext.md as the only startup file."
    Assert-True ($memoryHub -match "never startup payload") "MEMORY.md must keep index.json and projectbrief.md out of startup."
    Assert-True ($memoryHub -match "Resume Reads") "MEMORY.md must point to resume reads."
    Assert-True ($memoryHub -match "module-map\.json|modules/README\.md") "MEMORY.md must point to module-level memory."
    Assert-True ($memoryHub -match "history/index\.jsonl") "MEMORY.md must point to the searchable history index."
}

function Assert-ModuleMemory {
    param([string]$MemoryPath)

    $moduleMapPath = Join-Path $MemoryPath "module-map.json"
    $modulesReadmePath = Join-Path $MemoryPath "modules\README.md"
    Assert-True (Test-Path $moduleMapPath) "Missing module-map.json in $MemoryPath"
    Assert-True (Test-Path $modulesReadmePath) "Missing modules/README.md in $MemoryPath"

    $moduleMapText = Get-Content -Raw -Encoding UTF8 $moduleMapPath
    $moduleMap = $moduleMapText | ConvertFrom-Json
    Assert-True ($moduleMapText -match "path_globs") "module-map.json must define path_globs."
    Assert-True ($moduleMapText -match "module_memory") "module-map.json must map modules to memory files."
    Assert-True ($moduleMap.modules.Count -ge 3) "module-map.json should include common frontend/backend/database overlays."

    $modulesReadme = Get-Content -Raw -Encoding UTF8 $modulesReadmePath
    Assert-True ($modulesReadme -match "overlay|module memory") "modules/README.md must explain module memory overlays."
    Assert-True ($modulesReadme -match "path_globs") "modules/README.md must explain path_globs."
}

function Assert-HistorySearchLayer {
    param([string]$Root, [string]$MemoryPath)

    $historyIndexPath = Join-Path $MemoryPath "history\index.jsonl"
    $searchScriptPath = Join-Path $Root "search-memory.ps1"
    Assert-True (Test-Path $historyIndexPath) "Missing history/index.jsonl in $MemoryPath"
    Assert-True (Test-Path $searchScriptPath) "Missing search-memory.ps1 at repository root."

    $historyIndexLines = Get-Content -Encoding UTF8 $historyIndexPath | Where-Object { $_.Trim() }
    Assert-True ($historyIndexLines.Count -ge 1) "history/index.jsonl must contain at least one seed record documenting the schema."
    foreach ($line in $historyIndexLines) {
        $record = $line | ConvertFrom-Json
        Assert-True ($record.date -and $record.tags -and $record.summary -and $record.path) "history/index.jsonl records must include date, tags, summary, and path."
        Assert-True ($record.PSObject.Properties.Name -contains "restore_required") "history/index.jsonl records must include restore_required."
    }

    $searchScript = Get-Content -Raw -Encoding UTF8 $searchScriptPath
    Assert-True ($searchScript -match "history/index\.jsonl") "search-memory.ps1 must search history/index.jsonl."
    Assert-True ($searchScript -match "Query") "search-memory.ps1 must support query text."
    Assert-True ($searchScript -match "Tag") "search-memory.ps1 must support tag filtering."
    foreach ($parameterName in @("TaskId", "Type", "Since", "Limit", "VerifyHash")) {
        Assert-True ($searchScript -match ("\$" + $parameterName + "\b")) "search-memory.ps1 must support $parameterName filtering."
    }
}

function Assert-TaskPackLifecycle {
    param([string]$MemoryPath)

    $taskPackReadmePath = Join-Path $MemoryPath "task-packs\README.md"
    $ledgerPath = Join-Path $MemoryPath "masterTaskLedger.md"
    $taskPackReadme = Get-Content -Raw -Encoding UTF8 $taskPackReadmePath
    $ledger = Get-Content -Raw -Encoding UTF8 $ledgerPath

    foreach ($status in @("DRAFT", "READY", "IN_PROGRESS", "VERIFYING", "DONE", "ARCHIVED")) {
        Assert-True ($taskPackReadme -match $status) "task-packs/README.md must define $status lifecycle state."
    }
    Assert-True ($taskPackReadme -match "masterTaskLedger\.md") "task-packs/README.md must require ledger back-links."
    Assert-True ($ledger -match "task-packs") "masterTaskLedger.md must link ledger tasks to task packs."
    Assert-True ($ledger -match "backlink") "masterTaskLedger.md must require task-pack backlinks."

    $taskPackFiles = Get-ChildItem -Path (Join-Path $MemoryPath "task-packs") -Filter "*.md" -File |
        Where-Object { $_.Name -ne "README.md" }
    foreach ($taskPack in $taskPackFiles) {
        $relative = $taskPack.FullName.Substring($MemoryPath.Length + 1).Replace("\", "/")
        Assert-True ($ledger -match [regex]::Escape($relative)) "Task pack has no masterTaskLedger.md reference: $relative"
    }
}

function Assert-TrustAndFreshness {
    param([string]$MemoryPath)

    foreach ($fileName in @("decisionLog.md", "interfaces.md", "pitfalls.md")) {
        $text = Get-Content -Raw -Encoding UTF8 (Join-Path $MemoryPath $fileName)
        Assert-True ($text -match "last_verified") "$fileName must include a last_verified field."
        Assert-True ($text -match "confidence") "$fileName must include a confidence field."
        Assert-True ($text -match "status") "$fileName must include a status field."
        Assert-True ($text -match "superseded_by") "$fileName must include a superseded_by field."
    }
}

function Assert-RequirementLifecycle {
    param([string]$MemoryPath)

    $currentPath = Join-Path $MemoryPath "requirements\current.md"
    $changeLogPath = Join-Path $MemoryPath "requirements\change-log.jsonl"
    Assert-True (Test-Path $currentPath) "Missing requirements/current.md in $MemoryPath"
    Assert-True (Test-Path $changeLogPath) "Missing requirements/change-log.jsonl in $MemoryPath"

    $current = Get-Content -Raw -Encoding UTF8 $currentPath
    Assert-True ($current -match "baseline_version") "requirements/current.md must expose baseline_version."
    Assert-True ($current -match "\[UNINITIALIZED\]") "New requirement baselines must start as [UNINITIALIZED]."
    Assert-True ($current -match "REQ-001") "requirements/current.md must define stable Requirement ID formatting."
    Assert-True ($current -match "implementation_status") "requirements/current.md must separate implementation status."
    Assert-True ($current -match "verification_status") "requirements/current.md must separate verification status."
    Assert-True ($current -match "SUPERSEDED") "requirements/current.md must keep a superseded requirement index."

    $records = @(Get-Content -Encoding UTF8 $changeLogPath | Where-Object { $_.Trim() })
    Assert-True ($records.Count -ge 1) "requirements/change-log.jsonl must contain a schema seed."
    foreach ($line in $records) {
        $record = $line | ConvertFrom-Json
        foreach ($field in @("event_id", "requirement_id", "version", "timestamp", "source_type", "source_ref", "raw_summary", "change_type", "status", "affected_memory", "implementation_status", "verification_status")) {
            Assert-True ($record.PSObject.Properties.Name -contains $field) "Requirement change records must include $field."
        }
    }
}

function Assert-IndexIsComplete {
    param([string]$MemoryPath)

    $indexPath = Join-Path $MemoryPath "index.json"
    Assert-True (Test-Path $indexPath) "Missing index.json in $MemoryPath"

    $index = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json
    Assert-True ($index.version -eq "3.0.0") "index.json must use the V3 state-aware schema."
    Assert-True ($index.PSObject.Properties.Name -contains "budgets") "index.json must define machine-verifiable memory budgets."
    Assert-True (-not ($index.PSObject.Properties.Name -contains "bootstrap_order")) "index.json must not expose a full bootstrap_order that can be mistaken for mandatory startup reads."
    Assert-True ($index.budgets.startup.max_files -eq 1) "Startup budget must allow exactly one file."
    Assert-True ($index.budgets.startup.hard_max_characters -gt 0) "Startup budget must define a hard character limit."
    Assert-True ($index.budgets.active_context.hard_max_characters -gt 0) "activeContext budget must define a hard character limit."
    Assert-True ($index.budgets.active_context.max_single_line_characters -gt 0) "activeContext budget must define a single-line limit."
    Assert-True ($index.budgets.task_pack.hard_max_characters -gt 0) "Task packs must define a hard character limit."
    Assert-True ($index.budgets.task_pack.hard_max_lines -gt 0) "Task packs must define a hard line limit."

    Assert-True ($index.startup_order.Count -eq $index.budgets.startup.max_files) "startup_order must contain exactly the budgeted number of files."
    Assert-True (@($index.startup_order)[0] -eq "activeContext.md") "activeContext.md must be the only startup file."
    Assert-True (-not (@($index.startup_order) -contains "index.json")) "index.json must never be startup payload."
    Assert-True (-not (@($index.startup_order) -contains "projectbrief.md")) "projectbrief.md must never be startup payload."
    $startupCharacters = 0
    foreach ($entry in $index.startup_order) {
        $entryPath = Join-Path $MemoryPath $entry
        Assert-True (Test-Path $entryPath) "startup_order references missing file: $entryPath"
        $startupCharacters += (Get-TextMetrics $entryPath).Characters
    }
    Assert-True ($startupCharacters -le $index.budgets.startup.hard_max_characters) "Startup capsule exceeds hard character budget: $startupCharacters"
    Assert-True ((Get-TextMetrics $indexPath).Characters -le $index.budgets.index.hard_max_characters) "index.json exceeds its hard character budget."

    $requiredText = ($index.required_before_work -join "`n")
    Assert-True ($requiredText -notmatch "Read all Markdown files under \.ai_memory in full") "Startup rules must not require reading every Markdown file in full."
    Assert-True ($requiredText -match "State-aware startup.*activeContext\.md only") "Startup rules must identify the single state-aware capsule."
    Assert-True ($requiredText -match "index\.json and projectbrief\.md are never startup payload") "Startup rules must keep durable configuration out of startup."
    Assert-True ($requiredText -match "read only the exact task pack and Resume Reads") "Startup rules must bound task continuation reads."
    Assert-True ($requiredText -match "only when the current task needs them") "Startup rules must defer durable memory until relevant."
    Assert-True ($requiredText -match "implementation, verification, production migration, deployment and real-device acceptance") "Startup rules must preserve delivery-state distinctions."

    $compactRules = ($index.compact_contract -join "`n")
    Assert-True ($compactRules -match "Never preserve full file bodies, full command output, prior summaries") "Compaction must reject bulky context replay."
    Assert-True ($compactRules -match "reread activeContext\.md only") "Compaction recovery must reload only the capsule."
    Assert-True ($compactRules -match "clean session between unrelated tasks") "Unrelated tasks must not inherit stale sessions."

    Assert-True ($index.PSObject.Properties.Name -contains "memory_types") "index.json must classify files by memory type."
    Assert-True ($index.memory_types.procedural.Count -gt 0) "index.json must define procedural memory files."
    Assert-True ($index.memory_types.semantic.Count -gt 0) "index.json must define semantic memory files."
    Assert-True ($index.memory_types.episodic.Count -gt 0) "index.json must define episodic memory files."
    Assert-True ($index.PSObject.Properties.Name -contains "on_demand_routes") "index.json must define on-demand routes."
    Assert-True ($index.on_demand_routes.requirements.Count -gt 0) "index.json must route requirement memory on demand."
    Assert-True ($index.PSObject.Properties.Name -contains "health_checks") "index.json must define memory health checks."
}

function Assert-GrowthControlFiles {
    param([string]$MemoryPath)

    $ledgerPath = Join-Path $MemoryPath "masterTaskLedger.md"
    $taskPackReadmePath = Join-Path $MemoryPath "task-packs\README.md"
    $historyReadmePath = Join-Path $MemoryPath "history\README.md"

    Assert-True (Test-Path $ledgerPath) "Missing masterTaskLedger.md in $MemoryPath"
    Assert-True (Test-Path $taskPackReadmePath) "Missing task-packs/README.md in $MemoryPath"
    Assert-True (Test-Path $historyReadmePath) "Missing history/README.md in $MemoryPath"

    $ledger = Get-Content -Raw -Encoding UTF8 $ledgerPath
    Assert-True ($ledger -match "IN_PROGRESS") "masterTaskLedger.md must define IN_PROGRESS ownership."
    Assert-True ($ledger -match "DONE") "masterTaskLedger.md must define DONE completion records."
    Assert-True ($ledger -match "verification evidence") "masterTaskLedger.md must require verification evidence."
    Assert-True ($ledger -match "locked files") "masterTaskLedger.md must track locked files."

    $taskPackReadme = Get-Content -Raw -Encoding UTF8 $taskPackReadmePath
    Assert-True ($taskPackReadme -match "required reading") "task-packs/README.md must define required reading."
    Assert-True ($taskPackReadme -match "do not read") "task-packs/README.md must define do-not-read boundaries."
    Assert-True ($taskPackReadme -match "acceptance") "task-packs/README.md must define acceptance criteria."
    Assert-True ($taskPackReadme -match "handoff") "task-packs/README.md must define handoff content."

    $historyReadme = Get-Content -Raw -Encoding UTF8 $historyReadmePath
    Assert-True ($historyReadme -match "archive") "history/README.md must define archive rules."
    Assert-True ($historyReadme -match "activeContext\.md") "history/README.md must protect activeContext.md from long-term bloat."
    Assert-True ($historyReadme -match "progress\.md") "history/README.md must protect progress.md from long-term bloat."
    Assert-True ($historyReadme -match "rolling window|active window") "history/README.md must define rolling-window compaction."
    Assert-True ($historyReadme -match "archive index") "history/README.md must require archive index links."
}

function Assert-ProjectFastStartupRules {
    param([string]$Root)

    $memoryPath = Join-Path $Root ".ai_memory"
    Assert-IndexIsComplete $memoryPath
    Assert-RequirementLifecycle $memoryPath

    $activeContextPath = Join-Path $memoryPath "activeContext.md"
    $agentRulesPath = Join-Path $memoryPath "agentRules.md"
    Assert-True (Test-Path $activeContextPath) "Missing activeContext.md in project memory."
    Assert-True (Test-Path $agentRulesPath) "Missing agentRules.md in project memory."

    $activeContext = Get-Content -Raw -Encoding UTF8 $activeContextPath
    Assert-True ($activeContext -match 'only startup memory file|startup capsule') "activeContext.md must declare itself as the only startup capsule."
    Assert-True ($activeContext -notmatch '\[WIP\].{0,20}example|\[WIP\].{0,20}sample') "activeContext.md must not contain template WIP examples."
    Assert-True ($activeContext -notmatch 'Read all Markdown files|all Markdown files|every Markdown file') "activeContext.md must not require full memory reads on every startup."
    Assert-True ($activeContext -match 'Resume Reads|resume reads') "activeContext.md must include resume reads."
    Assert-True ($activeContext -match 'Requirement Baseline') "activeContext.md must expose the current requirement baseline version."
    Assert-True ($activeContext -match '\*\*State\*\*') "activeContext.md must expose state."
    Assert-True ($activeContext -match '\*\*Task ID\*\*') "activeContext.md must expose the task id."
    Assert-True ($activeContext -match '\*\*Task pack\*\*') "activeContext.md must expose one exact task-pack pointer."
    Assert-True ($activeContext -match 'never replay startup files or prior summaries') "activeContext.md must prevent compaction replay."

    $agentRules = Get-Content -Raw -Encoding UTF8 $agentRulesPath
    Assert-True ($agentRules -notmatch 'all Markdown files|every Markdown file') "agentRules.md must not require full memory reads on every startup."
    Assert-True ($agentRules -match "State-aware startup") "agentRules.md must describe state-aware startup."
    Assert-True ($agentRules -match "activeContext\.md") "agentRules.md must identify activeContext.md as the startup capsule."
    Assert-True ($agentRules -match "index\.json.*projectbrief\.md") "agentRules.md must keep index.json and projectbrief.md out of startup."
    Assert-True ($agentRules -match "L1[\s\S]*direct execution") "L1 tasks should default to direct execution without waiting for confirmation."
    Assert-True ($agentRules -match "demand-driven") "Memory writes should be demand-driven, not mandatory for every file."
    Assert-True ($agentRules -match 'real intent|raw wording') "agentRules.md must require intent translation."
    Assert-True ($agentRules -match 'context compression') "agentRules.md must define resume behavior after context resets."
    Assert-True ($agentRules -match 'context compression[^\r\n]*activeContext\.md') "agentRules.md must reload only the capsule after compaction."
    Assert-True ($agentRules -match 'main agent') "agentRules.md must define a main-agent writer for primary memory files."
    Assert-True ($agentRules -match 'default encoding|implicit text output') "agentRules.md must reject implicit default-encoding writes for memory files."
    Assert-True ($agentRules -match 'explicit UTF-8|UTF-8') "agentRules.md must require explicit UTF-8 file reads or writes."
    Assert-True ($agentRules -match 'mojibake') "agentRules.md must say to stop and repair unreadable mojibake before business edits."
    Assert-ToolAgnosticText -Text $agentRules -Name "agentRules.md"
    Assert-True ($agentRules -match 'masterTaskLedger\.md') "agentRules.md must mention the master task ledger."
    Assert-True ($agentRules -match 'task-packs') "agentRules.md must mention task packs."
    Assert-True ($agentRules -match 'Requirement Checklist') "agentRules.md must require requirements coverage before completion."
    Assert-True ($agentRules -match 'requirements/current\.md') "agentRules.md must trigger requirement baseline loading."
    Assert-True ($agentRules -match 'UNINITIALIZED') "agentRules.md must define first requirement initialization."
    Assert-True ($agentRules -match 'Latest User Intent Wins') "agentRules.md must apply the latest explicit user requirement directly."
    Assert-True ($agentRules -match 'SUPERSEDED') "agentRules.md must preserve replaced requirement versions."
    Assert-True ($agentRules -match 'does not mean implementation') "agentRules.md must separate requirement synchronization from implementation completion."

    Assert-GrowthControlFiles $memoryPath
    Assert-MemoryHub $memoryPath
    Assert-ModuleMemory $memoryPath
    Assert-HistorySearchLayer -Root $Root -MemoryPath $memoryPath
    Assert-TaskPackLifecycle $memoryPath
    Assert-TrustAndFreshness $memoryPath
    Assert-PrimaryMemoryHealth $memoryPath
    $progressRulesPath = Join-Path $memoryPath "progress.md"
    if (Test-Path $progressRulesPath) {
        $progressRules = Get-Content -Raw -Encoding UTF8 $progressRulesPath
        Assert-PrimaryMemoryWindowRules -ActiveContext $activeContext -Progress $progressRules -Name $memoryPath
    }

    foreach ($adapterName in @("AGENTS.md", "CLAUDE.md")) {
        $adapterPath = Join-Path $Root $adapterName
        if (Test-Path $adapterPath) {
            $adapterText = Get-Content -Raw -Encoding UTF8 $adapterPath
            Assert-True ($adapterText -notmatch 'Read every Markdown file under `.ai_memory/` in full|all Markdown files|every Markdown file') "$adapterName must not require full Markdown reads."
            Assert-True ($adapterText -match 'activeContext\.md') "$adapterName must point agents to the startup capsule."
            Assert-True ($adapterText -match 'index\.json.*projectbrief\.md') "$adapterName must keep index.json and projectbrief.md out of startup."
            Assert-True ($adapterText -match 'Task pack') "$adapterName must use a precise task-pack continuation pointer."
            Assert-True ($adapterText -match 'Resume Reads') "$adapterName must bound continuation reads."
            Assert-ToolAgnosticText -Text $adapterText -Name $adapterName
        }
    }
}

function Assert-FastStartupRules {
    param([string]$Root)

    $activeContext = Get-Content -Raw -Encoding UTF8 (Join-Path $Root ".ai_memory-pro\activeContext.md")
    Assert-True ($activeContext -notmatch "\[WIP\]") "activeContext.md must not contain template WIP markers."
    Assert-True ($activeContext -match "\[IDLE\]") "activeContext.md should start from an explicit IDLE state."
    Assert-True ($activeContext -match 'Resume Reads|resume reads') "activeContext.md must include resume reads."
    Assert-True ($activeContext -match 'Requirement Baseline') "activeContext.md must expose the current requirement baseline version."
    Assert-True ($activeContext -match 'only startup memory file') "activeContext.md must declare itself as the sole startup capsule."
    Assert-True ($activeContext -match '\*\*State\*\*') "activeContext.md must expose state."
    Assert-True ($activeContext -match '\*\*Task ID\*\*') "activeContext.md must expose the task id."
    Assert-True ($activeContext -match '\*\*Task pack\*\*') "activeContext.md must expose one exact task-pack pointer."

    $agentRules = Get-Content -Raw -Encoding UTF8 (Join-Path $Root ".ai_memory-pro\agentRules.md")
    Assert-True ($agentRules -notmatch "all Markdown files|every Markdown file") "agentRules.md must not require full memory reads on every startup."
    Assert-True ($agentRules -match "State-aware startup") "agentRules.md must describe state-aware startup."
    Assert-True ($agentRules -match "activeContext\.md") "agentRules.md must identify activeContext.md as the startup capsule."
    Assert-True ($agentRules -match "index\.json.*projectbrief\.md") "agentRules.md must keep index.json and projectbrief.md out of startup."
    Assert-True ($agentRules -match "L1[\s\S]*direct execution") "L1 tasks should default to direct execution without waiting for confirmation."
    Assert-True ($agentRules -match "demand-driven") "Memory writes should be demand-driven, not mandatory for every file."
    Assert-True ($agentRules -match 'real intent|raw wording') "agentRules.md must require intent translation."
    Assert-True ($agentRules -match 'context compression') "agentRules.md must define resume behavior after context resets."
    Assert-True ($agentRules -match 'context compression[^\r\n]*activeContext\.md') "agentRules.md must reload only the capsule after compaction."
    Assert-True ($agentRules -match 'main agent') "agentRules.md must define a main-agent writer for primary memory files."
    Assert-True ($agentRules -match 'default encoding|implicit text output') "agentRules.md must reject implicit default-encoding writes for memory files."
    Assert-True ($agentRules -match 'explicit UTF-8|UTF-8') "agentRules.md must require explicit UTF-8 file reads or writes."
    Assert-True ($agentRules -match 'mojibake') "agentRules.md must say to stop and repair unreadable mojibake before business edits."
    Assert-ToolAgnosticText -Text $agentRules -Name ".ai_memory-pro/agentRules.md"
    Assert-True ($agentRules -match 'masterTaskLedger\.md') "agentRules.md must mention the master task ledger."
    Assert-True ($agentRules -match 'task-packs') "agentRules.md must mention task packs."
    Assert-True ($agentRules -match 'Requirement Checklist') "agentRules.md must require requirements coverage before completion."
    Assert-True ($agentRules -match 'requirements/current\.md') "agentRules.md must trigger requirement baseline loading."
    Assert-True ($agentRules -match 'UNINITIALIZED') "agentRules.md must define first requirement initialization."
    Assert-True ($agentRules -match 'Latest User Intent Wins') "agentRules.md must apply the latest explicit user requirement directly."
    Assert-True ($agentRules -match 'SUPERSEDED') "agentRules.md must preserve replaced requirement versions."
    Assert-True ($agentRules -match 'does not mean implementation') "agentRules.md must separate requirement synchronization from implementation completion."

    $progressRules = Get-Content -Raw -Encoding UTF8 (Join-Path $Root ".ai_memory-pro\progress.md")
    Assert-True ($progressRules -match 'main agent') "progress.md must define main-agent ownership."
    Assert-True ($progressRules -match 'checkpoint') "progress.md must require checkpoint-based writes."
    Assert-PrimaryMemoryWindowRules -ActiveContext $activeContext -Progress $progressRules -Name ".ai_memory-pro"

    Assert-RequirementLifecycle (Join-Path $Root ".ai_memory-pro")
    Assert-GrowthControlFiles (Join-Path $Root ".ai_memory-pro")
    Assert-MemoryHub (Join-Path $Root ".ai_memory-pro")
    Assert-ModuleMemory (Join-Path $Root ".ai_memory-pro")
    Assert-HistorySearchLayer -Root $Root -MemoryPath (Join-Path $Root ".ai_memory-pro")
    Assert-TaskPackLifecycle (Join-Path $Root ".ai_memory-pro")
    Assert-TrustAndFreshness (Join-Path $Root ".ai_memory-pro")
    Assert-PrimaryMemoryHealth (Join-Path $Root ".ai_memory-pro")

    $adapterFiles = Get-ChildItem -Path (Join-Path $Root "tool_adapters") -File
    foreach ($adapter in $adapterFiles) {
        $adapterText = Get-Content -Raw -Encoding UTF8 $adapter.FullName
        Assert-True ($adapterText -notmatch "Read every Markdown file under `.ai_memory/` in full|all Markdown files|every Markdown file") "$($adapter.Name) must not require full Markdown reads."
        Assert-True ($adapterText -match 'activeContext\.md') "$($adapter.Name) must point agents to the startup capsule."
        Assert-True ($adapterText -match 'index\.json.*projectbrief\.md') "$($adapter.Name) must keep index.json and projectbrief.md out of startup."
        Assert-True ($adapterText -match 'Task pack') "$($adapter.Name) must use a precise task-pack continuation pointer."
        Assert-True ($adapterText -match 'Resume Reads') "$($adapter.Name) must bound continuation reads."
        Assert-True ($adapterText -match 'requirements/current\.md') "$($adapter.Name) must initialize requirements on demand."
        Assert-True ($adapterText -match 'Latest User Intent Wins') "$($adapter.Name) must apply direct requirement replacement."
        Assert-True ($adapterText -match 'SUPERSEDED') "$($adapter.Name) must preserve superseded requirement history."
        Assert-ToolAgnosticText -Text $adapterText -Name $adapter.Name
    }
}

Write-Output "Checking repository text encodings..."
$agentReadableFiles = Get-ChildItem -Path $Root -Recurse -File |
    Where-Object {
        $_.FullName -notmatch "\\(\.git|\.archive|node_modules|dist|\.vite|coverage|playwright-report|test-results|logs|\.cache|tmp|tmp-common-adapter-test|tmp-sync-adapter-test)\\" -and
        $_.Extension -in @(".md", ".json", ".jsonl", ".template", ".txt", ".ps1")
    }

foreach ($file in $agentReadableFiles) {
    Assert-Utf8NoBom $file
}

Write-Output "Checking public docs for hardcoded local paths..."
$publicDocFiles = Get-ChildItem -Path $Root -Recurse -File |
    Where-Object {
        $_.FullName -notmatch "\\(\.git|\.archive|node_modules|dist|\.vite|coverage|playwright-report|test-results|logs|\.cache|tmp|tmp-common-adapter-test|tmp-sync-adapter-test)\\" -and
        $_.Extension -in @(".md", ".template", ".yml", ".yaml")
    }

foreach ($file in $publicDocFiles) {
    Assert-NoHardcodedLocalDocPath $file
}

$projectMemoryPath = Join-Path $Root ".ai_memory"
$templateMemoryPath = Join-Path $Root ".ai_memory-pro"
if ((Test-Path (Join-Path $projectMemoryPath "index.json")) -and (-not (Test-Path (Join-Path $templateMemoryPath "index.json")))) {
    Write-Output "Checking project state-aware startup memory..."
    Assert-ProjectFastStartupRules $Root
    Write-Output "Memory system verification passed."
    return
}

Write-Output "Checking memory indexes..."
Assert-True (-not (Test-Path (Join-Path $Root ".ai_memory-lite"))) "Lite template should not exist in Pro-only mode."
Assert-IndexIsComplete (Join-Path $Root ".ai_memory-pro")
Assert-FastStartupRules $Root

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
    Assert-ProjectFastStartupRules $tempRoot

    Write-Output "Checking generated memory health tool..."
    $generatedMemory = Join-Path $tempRoot ".ai_memory"
    $generatedHealthTool = Join-Path $tempRoot "memory-health.ps1"
    Assert-True (Test-Path $generatedHealthTool) "init-memory.ps1 must generate memory-health.ps1."
    foreach ($helperName in @("record-requirement-change.ps1", "compact-memory.ps1", "migrate-memory.ps1", "search-memory.ps1", "claude-context-health.ps1")) {
        Assert-True (Test-Path (Join-Path $tempRoot $helperName)) "init-memory.ps1 must generate $helperName."
    }
    $healthOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $generatedMemory 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Healthy generated memory must pass memory-health.ps1. Output: $($healthOutput -join ' ')"
    Assert-True (($healthOutput -join "`n") -match "Startup files: 1 / limit 1") "Health output must report the one-file startup budget."
    Assert-True (($healthOutput -join "`n") -match "Estimated tokens: .*CJK-aware static estimate") "Health output must report the CJK-aware token estimate."
    Assert-True (($healthOutput -join "`n") -match "Task packs: .*oversized 0") "Health output must report task-pack budget health."
    Assert-True (($healthOutput -join "`n") -match "Overall status: PASS") "Health output must report PASS."

    $extraEventRoot = Join-Path $tempRoot "extra-lifecycle-event"
    Copy-Item -LiteralPath $generatedMemory -Destination $extraEventRoot -Recurse
    $extraEvent = [ordered]@{ event_id = "manual-status-event"; requirement_id = "REQ-001"; version = 1; status = "active"; change_type = "status_update" }
    [IO.File]::AppendAllText((Join-Path $extraEventRoot "requirements\change-log.jsonl"), ("`n" + ($extraEvent | ConvertTo-Json -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
    $extraEventOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $extraEventRoot 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Additional lifecycle/status events must not invalidate a requirement baseline. Output: $($extraEventOutput -join ' ')"
    Assert-True (($extraEventOutput -join "`n") -match "additional lifecycle/status events") "Additional lifecycle/status events must produce an explicit warning."

    Write-Output "Checking Claude context health tool..."
    $generatedClaudeHealthTool = Join-Path $tempRoot "claude-context-health.ps1"
    $emptyClaudeConfig = Join-Path $tempRoot "empty-claude-config"
    New-Item -ItemType Directory -Path $emptyClaudeConfig | Out-Null
    $claudeHealthOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedClaudeHealthTool -ProjectPath $tempRoot -ClaudeConfigPath $emptyClaudeConfig -Json 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "A generated project with an empty Claude config must pass context health. Output: $($claudeHealthOutput -join ' ')"
    $claudeHealth = ($claudeHealthOutput -join "`n") | ConvertFrom-Json
    Assert-True ($claudeHealth.status -eq "PASS") "Claude context health JSON must report PASS."
    Assert-True ($claudeHealth.memory_startup_characters -le 1800) "Claude context health must enforce the startup capsule budget."
    Assert-True ($claudeHealth.estimated_token_method -match "CJK") "Claude context health must document its token estimate method."

    $bloatedRules = Join-Path $emptyClaudeConfig "rules"
    New-Item -ItemType Directory -Path $bloatedRules | Out-Null
    [IO.File]::WriteAllText((Join-Path $bloatedRules "unscoped.md"), ("X" * 10001), [Text.UTF8Encoding]::new($false))
    $bloatedClaudeOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedClaudeHealthTool -ProjectPath $tempRoot -ClaudeConfigPath $emptyClaudeConfig 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) "Unscoped Claude rules over 10,000 characters must fail context health."
    Assert-True (($bloatedClaudeOutput -join "`n") -match "Unscoped Claude rules exceed 10,000 characters") "Context health must identify unscoped-rule bloat."

    $mismatchRoot = Join-Path $tempRoot "baseline-mismatch"
    Copy-Item -LiteralPath $generatedMemory -Destination $mismatchRoot -Recurse
    $mismatchRequirementsPath = Join-Path $mismatchRoot "requirements\current.md"
    $mismatchRequirements = [IO.File]::ReadAllText($mismatchRequirementsPath, [Text.Encoding]::UTF8).Replace("- **baseline_version**: 0", "- **baseline_version**: 9")
    [IO.File]::WriteAllText($mismatchRequirementsPath, $mismatchRequirements, [Text.UTF8Encoding]::new($false))
    $mismatchOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $mismatchRoot 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) "A stale requirement baseline version must fail memory health."
    Assert-True (($mismatchOutput -join "`n") -match "Requirement change log has fewer events than the baseline version") "Baseline mismatch must report the requirement synchronization error."

    $inflatedRoot = Join-Path $tempRoot "inflated-memory"
    Copy-Item -LiteralPath $generatedMemory -Destination $inflatedRoot -Recurse
    [IO.File]::AppendAllText((Join-Path $inflatedRoot "activeContext.md"), ("X" * 200000), [Text.UTF8Encoding]::new($false))
    $inflatedOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $inflatedRoot 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) "A 205KB activeContext.md must fail memory-health.ps1."
    Assert-True (($inflatedOutput -join "`n") -match "activeContext hard character budget exceeded|activeContext single-line budget exceeded") "Inflated memory failure must identify the violated budget."

    Write-Output "Checking latest-user-wins requirement updates..."
    $requirementTool = Join-Path $Root "record-requirement-change.ps1"
    Assert-True (Test-Path $requirementTool) "Missing record-requirement-change.ps1."
    $requirementTitle = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5Yig6Zmk5p2D6ZmQ"))
    $requirementV1 = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5pmu6YCa55So5oi35Y+v55u05o6l5Yig6Zmk"))
    $requirementV2 = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("5pmu6YCa55So5oi35o+Q5Lqk55Sz6K+377yM55Sx566h55CG5ZGY5a6h5qC4"))
    & $requirementTool -MemoryPath $generatedMemory -RequirementId "REQ-001" -Title $requirementTitle -Statement $requirementV1 -SourceType "user" -SourceRef "turn-1" | Out-Null
    & $requirementTool -MemoryPath $generatedMemory -RequirementId "REQ-001" -Title $requirementTitle -Statement $requirementV2 -SourceType "user" -SourceRef "turn-2" | Out-Null

    $currentRequirements = Get-Content -Raw -Encoding UTF8 (Join-Path $generatedMemory "requirements\current.md")
    Assert-True ($currentRequirements.Contains($requirementV2)) "Latest explicit requirement must become the current baseline."
    Assert-True (-not $currentRequirements.Contains($requirementV1)) "Superseded requirement text must not remain active in the current baseline."
    Assert-True ($currentRequirements -match "REQ-001 v1 -> v2") "Current baseline must index the superseded version."
    Assert-True ($currentRequirements -match "implementation_pending") "Requirement synchronization must not claim implementation is complete."

    $requirementEvents = @(Get-Content -Encoding UTF8 (Join-Path $generatedMemory "requirements\change-log.jsonl") | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
    $reqEvents = @($requirementEvents | Where-Object { $_.requirement_id -eq "REQ-001" })
    Assert-True ($reqEvents.Count -eq 2) "Two explicit user requirements must create two audit events."
    Assert-True (($reqEvents | Sort-Object version | Select-Object -Last 1).previous_version -eq 1) "The replacement event must link to the superseded version."
    Assert-True (($reqEvents | Sort-Object version | Select-Object -Last 1).status -eq "active") "The newest requirement event must be active."

    $removalMemory = Join-Path $tempRoot "requirement-removal"
    Copy-Item -LiteralPath $generatedMemory -Destination $removalMemory -Recurse
    & $requirementTool -MemoryPath $removalMemory -RequirementId "REQ-001" -Title $requirementTitle -Statement "removed" -ChangeType "removed" -SourceType "user" -SourceRef "turn-3" | Out-Null
    & $requirementTool -MemoryPath $removalMemory -RequirementId "REQ-001" -Title $requirementTitle -Statement $requirementV1 -ChangeType "added" -SourceType "user" -SourceRef "turn-4" | Out-Null
    $removalEvents = @(Get-Content -Encoding UTF8 (Join-Path $removalMemory "requirements\change-log.jsonl") | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.requirement_id -eq "REQ-001" } | Sort-Object version)
    Assert-True (($removalEvents.version -join ",") -eq "1,2,3,4") "Requirement versions must stay monotonic across removal and reactivation."
    Assert-True ((Get-Content -Raw -Encoding UTF8 (Join-Path $removalMemory "requirements\current.md")).Contains($requirementV1)) "A reactivated latest requirement must return to the active baseline."

    $activeAfterRequirement = Get-Content -Raw -Encoding UTF8 (Join-Path $generatedMemory "activeContext.md")
    Assert-True ($activeAfterRequirement -match "Requirement Baseline.*2") "activeContext.md must expose the latest requirement baseline version."

    Write-Output "Checking safe memory compaction..."
    $generatedCompactTool = Join-Path $tempRoot "compact-memory.ps1"
    Assert-True (Test-Path $generatedCompactTool) "init-memory.ps1 must generate compact-memory.ps1."
    $replacementPath = Join-Path $tempRoot "activeContext.replacement.md"
    [IO.File]::WriteAllText($replacementPath, ($activeAfterRequirement.TrimEnd() + "`n- **Compaction Test Marker**: applied`n"), [Text.UTF8Encoding]::new($false))
    $beforeCompactionHash = (Get-FileHash -LiteralPath (Join-Path $generatedMemory "activeContext.md") -Algorithm SHA256).Hash.ToLowerInvariant()
    $archiveRoot = Join-Path $tempRoot ".ai_memory_archive"
    $dryRunOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedCompactTool -MemoryPath $generatedMemory -ActiveContextReplacementPath $replacementPath 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Compaction DryRun must succeed."
    Assert-True (($dryRunOutput -join "`n") -match "DRY RUN") "Compaction must default to DryRun."
    Assert-True (-not (Test-Path $archiveRoot)) "DryRun must not create an archive."

    $applyOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedCompactTool -MemoryPath $generatedMemory -ActiveContextReplacementPath $replacementPath -Apply 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Compaction Apply must succeed. Output: $($applyOutput -join ' ')"
    Assert-True ((Get-Content -Raw -Encoding UTF8 (Join-Path $generatedMemory "activeContext.md")) -match "Compaction Test Marker") "Compaction must apply the replacement file."
    $manifestFile = Get-ChildItem -LiteralPath $archiveRoot -Recurse -File -Filter "manifest.json" | Select-Object -First 1
    Assert-True ($null -ne $manifestFile) "Compaction must create an archive manifest."
    $manifest = Get-Content -Raw -Encoding UTF8 $manifestFile.FullName | ConvertFrom-Json
    $activeArchiveRecord = @($manifest.files | Where-Object { $_.source_path -eq ".ai_memory/activeContext.md" }) | Select-Object -First 1
    Assert-True ($null -ne $activeArchiveRecord) "Manifest must record the original activeContext.md."
    $archivedActivePath = Join-Path $tempRoot $activeArchiveRecord.archive_path
    Assert-True ((Get-FileHash -LiteralPath $archivedActivePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $beforeCompactionHash) "Archived activeContext.md must preserve the original SHA-256."
    Assert-True ((Get-Item -LiteralPath $archivedActivePath).IsReadOnly) "Archived memory files must be read-only."
    $legacyArchive = Join-Path $archiveRoot "legacy-manifest"
    New-Item -ItemType Directory -Path $legacyArchive | Out-Null
    $legacyPayloadPath = Join-Path $legacyArchive "payload.md"
    [IO.File]::WriteAllText($legacyPayloadPath, "legacy archive payload", [Text.UTF8Encoding]::new($false))
    $legacyManifest = [ordered]@{ archive = "legacy-manifest"; files = @([ordered]@{ path = "payload.md"; sha256 = (Get-FileHash -LiteralPath $legacyPayloadPath -Algorithm SHA256).Hash.ToLowerInvariant() }) }
    [IO.File]::WriteAllText((Join-Path $legacyArchive "manifest.json"), ($legacyManifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $verifiedArchiveOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $generatedMemory -VerifyArchive 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Untampered current and legacy archive manifests must pass hash verification."
    $generatedSearchTool = Join-Path $tempRoot "search-memory.ps1"
    $searchOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedSearchTool -MemoryPath $generatedMemory -Type "memory-compaction" -TaskId "none" -Since (Get-Date).ToString("yyyy-MM-dd") -Limit 1 -VerifyHash -Json 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Filtered archive search with hash verification must succeed. Output: $($searchOutput -join ' ')"
    $searchRecords = @(($searchOutput -join "`n") | ConvertFrom-Json)
    Assert-True ($searchRecords.Count -eq 1) "Search -Limit 1 must return exactly one matching record."
    Assert-True ($searchRecords[0].type -eq "memory-compaction") "Search -Type must filter archive records."
    (Get-Item -LiteralPath $archivedActivePath).IsReadOnly = $false
    [IO.File]::AppendAllText($archivedActivePath, "tamper", [Text.UTF8Encoding]::new($false))
    $tamperedArchiveOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $generatedHealthTool -MemoryPath $generatedMemory -VerifyArchive 2>&1)
    Assert-True ($LASTEXITCODE -ne 0) "Tampered archive must fail hash verification."
    Assert-True (($tamperedArchiveOutput -join "`n") -match "Archive SHA-256 mismatch") "Archive failure must identify the hash mismatch."

    Write-Output "Checking legacy memory migration..."
    $migrationTool = Join-Path $Root "migrate-memory.ps1"
    Assert-True (Test-Path $migrationTool) "Missing migrate-memory.ps1."
    $legacyRoot = Join-Path $tempRoot "legacy-project"
    New-Item -ItemType Directory -Path $legacyRoot | Out-Null
    & (Join-Path $Root "init-memory.ps1") -Mode Pro -TargetPath $legacyRoot -ProjectName "LegacyTest" -Adapter None | Out-Null
    $legacyMemory = Join-Path $legacyRoot ".ai_memory"
    Remove-Item -LiteralPath (Join-Path $legacyMemory "requirements") -Recurse -Force
    $legacyIndexPath = Join-Path $legacyMemory "index.json"
    $legacyIndex = Get-Content -Raw -Encoding UTF8 $legacyIndexPath | ConvertFrom-Json
    $legacyIndex.version = "1.2.0"
    $legacyIndex.startup_order = @("index.json", "MEMORY.md", "projectbrief.md", "activeContext.md", "agentRules.md")
    $legacyIndex.PSObject.Properties.Remove("budgets")
    $legacyIndex | Add-Member -NotePropertyName "bootstrap_order" -NotePropertyValue @("projectbrief.md", "activeContext.md", "progress.md") -Force
    [IO.File]::WriteAllText($legacyIndexPath, ($legacyIndex | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    $legacyHashBefore = (Get-FileHash -LiteralPath $legacyIndexPath -Algorithm SHA256).Hash

    $migrationDryRun = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $migrationTool -TargetPath $legacyRoot 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Migration DryRun must succeed."
    Assert-True (($migrationDryRun -join "`n") -match "DRY RUN") "Migration must default to DryRun."
    Assert-True ((Get-FileHash -LiteralPath $legacyIndexPath -Algorithm SHA256).Hash -eq $legacyHashBefore) "Migration DryRun must not modify index.json."
    Assert-True (-not (Test-Path (Join-Path $legacyRoot ".ai_memory_archive"))) "Migration DryRun must not create an archive."

    $migrationApply = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $migrationTool -TargetPath $legacyRoot -Apply 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Migration Apply must succeed. Output: $($migrationApply -join ' ')"
    Assert-True (Test-Path (Join-Path $legacyMemory "requirements\current.md")) "Migration must add requirements/current.md."
    $migratedIndex = Get-Content -Raw -Encoding UTF8 $legacyIndexPath | ConvertFrom-Json
    Assert-True ($migratedIndex.version -eq "3.0.0") "Migration must upgrade index version to 3.0.0."
    Assert-True ($migratedIndex.startup_order.Count -eq 1) "Migration must enforce the one-file startup capsule."
    Assert-True (@($migratedIndex.startup_order)[0] -eq "activeContext.md") "Migration must keep only activeContext.md in startup_order."
    Assert-True (-not ($migratedIndex.PSObject.Properties.Name -contains "bootstrap_order")) "Migration must remove bootstrap_order."
    Assert-Utf8NoBom (Get-Item (Join-Path $legacyMemory "agentRules.md"))
    Assert-True ((Get-Content -Raw -Encoding UTF8 (Join-Path $legacyMemory "agentRules.md")) -match 'read activeContext\.md only') "Migration override must preserve the activeContext.md filename without PowerShell escape corruption."
    $migratedTaskPack = Get-ChildItem -LiteralPath (Join-Path $legacyMemory "task-packs") -File -Filter "migrated-active-context-*.md" | Select-Object -First 1
    Assert-True ($null -ne $migratedTaskPack) "Migration must preserve old active context in a task pack."
    Assert-True ((Get-Content -Raw -Encoding UTF8 $migratedTaskPack.FullName) -match '\.ai_memory_archive/migration-v3-.+/activeContext\.md') "Migrated task pack must include the expanded archive path, not a literal variable name."
    $migrationManifests = @(Get-ChildItem -LiteralPath (Join-Path $legacyRoot ".ai_memory_archive") -Recurse -File -Filter "manifest.json")
    Assert-True ($migrationManifests.Count -eq 1) "Migration must create exactly one backup manifest."
    $legacyHealthOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $legacyRoot "memory-health.ps1") -MemoryPath $legacyMemory -VerifyArchive 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Migrated memory and backup archive must pass health verification. Output: $($legacyHealthOutput -join ' ')"
    $secondMigration = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $migrationTool -TargetPath $legacyRoot -Apply 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "Repeated migration must be idempotent."
    Assert-True (($secondMigration -join "`n") -match "already current") "Repeated migration must report that the project is already current."
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path $legacyRoot ".ai_memory_archive") -Recurse -File -Filter "manifest.json").Count -eq 1) "Repeated migration must not create another backup."
    $generatedMigration = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $legacyRoot "migrate-memory.ps1") -TargetPath $legacyRoot -Apply 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "The generated migration helper must be idempotent without a template checkout."
    Assert-True (($generatedMigration -join "`n") -match "already current") "The generated migration helper must recognize the current schema before requiring template assets."

    $setupTodo = Get-Content -Raw -Encoding UTF8 (Join-Path $tempRoot ".ai_memory\SETUP_TODO.md")
    Assert-True ($setupTodo -match "tool_adapters/") "SETUP_TODO.md must render tool_adapters/ literally."
    Assert-True ($setupTodo -notmatch ([char]9 + "ool_adapters/")) "SETUP_TODO.md must not contain a tab caused by PowerShell backtick escaping."

    Write-Output "Checking Lite mode is unavailable..."
    $liteRoot = Join-Path $tempRoot "lite"
    New-Item -ItemType Directory -Path $liteRoot | Out-Null
    $liteRejected = $false
    try {
        & (Join-Path $Root "init-memory.ps1") -Mode Lite -TargetPath $liteRoot -ProjectName "LiteTest" -Adapter None | Out-Null
    } catch {
        $liteRejected = ($_.Exception.Message -match "Cannot validate argument") -or ($_.Exception.GetType().FullName -match "ParameterBindingValidationException")
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
