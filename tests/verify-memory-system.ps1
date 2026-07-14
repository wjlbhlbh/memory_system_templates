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

    Assert-True ($ActiveContext -match "context budget|active window|rolling window|bounded active window") "$Name activeContext.md must define a bounded active window."
    Assert-True ($ActiveContext -match "history/|task-packs/") "$Name activeContext.md must point overflow detail to task packs or history."
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
    Assert-True ($lineCount -le 200) "MEMORY.md must stay short enough for startup; current line count: $lineCount"
    Assert-True ($memoryHub -match "Fast startup|startup_order") "MEMORY.md must explain Fast startup."
    Assert-True ($memoryHub -match "Current status") "MEMORY.md must expose current status."
    Assert-True ($memoryHub -match "Resume Reads") "MEMORY.md must point to resume reads."
    Assert-True ($memoryHub -match "memory type|procedural|semantic|episodic") "MEMORY.md must explain memory types."
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
    Assert-True ($index.PSObject.Properties.Name -contains "budgets") "index.json must define machine-verifiable memory budgets."
    Assert-True (-not ($index.PSObject.Properties.Name -contains "bootstrap_order")) "index.json must not expose a full bootstrap_order that can be mistaken for mandatory startup reads."
    Assert-True ($index.budgets.startup.max_files -eq 3) "Startup budget must allow exactly three files."
    Assert-True ($index.budgets.startup.hard_max_characters -gt 0) "Startup budget must define a hard character limit."
    Assert-True ($index.budgets.active_context.hard_max_characters -gt 0) "activeContext budget must define a hard character limit."
    Assert-True ($index.budgets.active_context.max_single_line_characters -gt 0) "activeContext budget must define a single-line limit."

    Assert-True ($index.startup_order.Count -eq $index.budgets.startup.max_files) "startup_order must contain exactly the budgeted number of files."
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
    Assert-True ($requiredText -match "Load non-startup memory files only when relevant") "Startup rules must explicitly defer non-startup files until relevant."
    Assert-True ($requiredText -match "raw wording|real intent") "Startup rules must require intent translation before implementation."
    Assert-True ($requiredText -match "context compression|session resume|model switch") "Startup rules must define resume behavior after context resets."
    Assert-ToolAgnosticText -Text $requiredText -Name "index.json required_before_work"
    Assert-True ($requiredText -match "explicit UTF-8|UTF-8") "Startup rules must require explicit UTF-8 reads or writes for memory files."

    $intentRules = ($index.intent_translation_contract -join "`n")
    Assert-True ($intentRules -match "confirmed facts|open questions") "index.json must define an intent translation contract."

    $writeTriggers = ($index.memory_write_triggers -join "`n")
    Assert-True ($writeTriggers -match "activeContext\.md") "index.json must define activeContext.md write triggers."
    Assert-True ($writeTriggers -match "verified checkpoints|checkpoint") "index.json must require checkpoint-based verified writes."
    Assert-True ($writeTriggers -match "single-writer|single writer|single-writer files") "index.json must define single-writer primary memory files."

    $resumeRules = ($index.resume_protocol -join "`n")
    Assert-True ($resumeRules -match "activeContext\.md") "index.json must define resume instructions around activeContext.md."
    Assert-True ($requiredText -match "masterTaskLedger\.md") "Startup rules must mention the master task ledger for multi-agent work."
    Assert-True ($requiredText -match "task-packs") "Startup rules must mention task packs for complex tasks."
    Assert-True ($requiredText -match "Requirement Checklist") "Startup rules must require requirements coverage before completion."

    Assert-True ($index.PSObject.Properties.Name -contains "memory_types") "index.json must classify files by memory type."
    Assert-True ($index.memory_types.procedural.Count -gt 0) "index.json must define procedural memory files."
    Assert-True ($index.memory_types.semantic.Count -gt 0) "index.json must define semantic memory files."
    Assert-True ($index.memory_types.episodic.Count -gt 0) "index.json must define episodic memory files."
    Assert-True ($index.PSObject.Properties.Name -contains "module_memory") "index.json must point to module-level memory."
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
    Assert-True ($activeContext -match 'index\.json') "activeContext.md must mention index.json in the entry rules."
    Assert-True ($activeContext -match 'startup_order') "activeContext.md must use startup_order for Fast startup."
    Assert-True ($activeContext -notmatch '\[WIP\].{0,20}example|\[WIP\].{0,20}sample') "activeContext.md must not contain template WIP examples."
    Assert-True ($activeContext -notmatch 'Read all Markdown files|all Markdown files|every Markdown file') "activeContext.md must not require full memory reads on every startup."
    Assert-True ($activeContext -match 'Raw Wording|raw wording') "activeContext.md must include a raw user wording field."
    Assert-True ($activeContext -match 'Real Intent|real intent') "activeContext.md must include a real intent field."
    Assert-True ($activeContext -match 'Resume Reads|resume reads') "activeContext.md must include resume reads."
    Assert-True ($activeContext -match 'Requirement Baseline') "activeContext.md must expose the current requirement baseline version."
    Assert-True ($activeContext -match 'main agent') "activeContext.md must define main-agent ownership."

    $agentRules = Get-Content -Raw -Encoding UTF8 $agentRulesPath
    Assert-True ($agentRules -notmatch 'all Markdown files|every Markdown file') "agentRules.md must not require full memory reads on every startup."
    Assert-True ($agentRules -match "Fast startup") "agentRules.md must describe the fast startup protocol."
    Assert-True ($agentRules -match "L1[\s\S]*direct execution") "L1 tasks should default to direct execution without waiting for confirmation."
    Assert-True ($agentRules -match "demand-driven") "Memory writes should be demand-driven, not mandatory for every file."
    Assert-True ($agentRules -match 'real intent|raw wording') "agentRules.md must require intent translation."
    Assert-True ($agentRules -match 'context compression|resume|model switch') "agentRules.md must define resume behavior after context resets."
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
            Assert-True ($adapterText -match 'startup_order|Fast startup|fast startup') "$adapterName must point agents to the fast startup flow."
            Assert-True ($adapterText -match 'real intent|raw wording') "$adapterName must require intent translation."
            Assert-True ($adapterText -match 'context compression|checkpoint|resume|model switch') "$adapterName must define checkpointed resume behavior."
            Assert-True ($adapterText -match 'Startup Summary') "$adapterName must require a startup summary after Fast startup."
            Assert-ToolAgnosticText -Text $adapterText -Name $adapterName
        }
    }
}

function Assert-FastStartupRules {
    param([string]$Root)

    $activeContext = Get-Content -Raw -Encoding UTF8 (Join-Path $Root ".ai_memory-pro\activeContext.md")
    Assert-True ($activeContext -notmatch "\[WIP\]") "activeContext.md must not contain template WIP markers."
    Assert-True ($activeContext -match "\[IDLE\]") "activeContext.md should start from an explicit IDLE state."
    Assert-True ($activeContext -match 'Raw Wording|raw wording') "activeContext.md must include a raw user wording field."
    Assert-True ($activeContext -match 'Real Intent|real intent') "activeContext.md must include a real intent field."
    Assert-True ($activeContext -match 'Resume Reads|resume reads') "activeContext.md must include resume reads."
    Assert-True ($activeContext -match 'Requirement Baseline') "activeContext.md must expose the current requirement baseline version."
    Assert-True ($activeContext -match 'main agent') "activeContext.md must define main-agent ownership."

    $agentRules = Get-Content -Raw -Encoding UTF8 (Join-Path $Root ".ai_memory-pro\agentRules.md")
    Assert-True ($agentRules -notmatch "all Markdown files|every Markdown file") "agentRules.md must not require full memory reads on every startup."
    Assert-True ($agentRules -match "Fast startup") "agentRules.md must describe the fast startup protocol."
    Assert-True ($agentRules -match "L1[\s\S]*direct execution") "L1 tasks should default to direct execution without waiting for confirmation."
    Assert-True ($agentRules -match "demand-driven") "Memory writes should be demand-driven, not mandatory for every file."
    Assert-True ($agentRules -match 'real intent|raw wording') "agentRules.md must require intent translation."
    Assert-True ($agentRules -match 'context compression|resume|model switch') "agentRules.md must define resume behavior after context resets."
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
        Assert-True ($adapterText -match "startup_order|Fast startup|fast startup") "$($adapter.Name) must point agents to the fast startup flow."
        Assert-True ($adapterText -match 'real intent|raw wording') "$($adapter.Name) must require intent translation."
        Assert-True ($adapterText -match 'context compression|checkpoint|resume|model switch') "$($adapter.Name) must define checkpointed resume behavior."
        Assert-True ($adapterText -match 'Startup Summary') "$($adapter.Name) must require a startup summary after Fast startup."
        Assert-True ($adapterText -match 'requirements/current\.md') "$($adapter.Name) must trigger first requirement initialization."
        Assert-True ($adapterText -match 'Latest User Intent Wins') "$($adapter.Name) must apply direct requirement replacement."
        Assert-True ($adapterText -match 'SUPERSEDED') "$($adapter.Name) must preserve superseded requirement history."
        Assert-True ($adapterText -match 'does not mean implementation') "$($adapter.Name) must separate requirement sync from implementation."
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
    Write-Output "Checking project Fast startup memory..."
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

    Write-Output "Checking latest-user-wins requirement updates..."
    $requirementTool = Join-Path $Root "record-requirement-change.ps1"
    Assert-True (Test-Path $requirementTool) "Missing record-requirement-change.ps1."
    $generatedMemory = Join-Path $tempRoot ".ai_memory"
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

    $activeAfterRequirement = Get-Content -Raw -Encoding UTF8 (Join-Path $generatedMemory "activeContext.md")
    Assert-True ($activeAfterRequirement -match "Requirement Baseline.*2") "activeContext.md must expose the latest requirement baseline version."

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
