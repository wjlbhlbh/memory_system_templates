param(
    [string]$MemoryPath = ".ai_memory",
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^REQ-\d{3,}$')]
    [string]$RequirementId,
    [Parameter(Mandatory = $true)]
    [string]$Title,
    [Parameter(Mandatory = $true)]
    [string]$Statement,
    [ValidateSet("added", "modified", "removed", "replaced")]
    [string]$ChangeType = "modified",
    [string]$SourceType = "user",
    [string]$SourceRef = "direct-user-expression",
    [string[]]$AffectedMemory = @("requirements/current.md", "activeContext.md")
)

$ErrorActionPreference = "Stop"
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$resolvedMemory = (Resolve-Path -LiteralPath $MemoryPath).Path
$currentPath = Join-Path $resolvedMemory "requirements\current.md"
$changeLogPath = Join-Path $resolvedMemory "requirements\change-log.jsonl"
$activeContextPath = Join-Path $resolvedMemory "activeContext.md"

foreach ($requiredPath in @($currentPath, $changeLogPath, $activeContextPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Missing requirement lifecycle file: $requiredPath"
    }
}

function Write-AtomicUtf8 {
    param([string]$Path, [string]$Content)

    $tempPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

$current = [IO.File]::ReadAllText($currentPath, [Text.Encoding]::UTF8)
$activeContext = [IO.File]::ReadAllText($activeContextPath, [Text.Encoding]::UTF8)
$eventLines = @([IO.File]::ReadAllLines($changeLogPath, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
$events = @($eventLines | ForEach-Object { $_ | ConvertFrom-Json })
$priorEvents = @($events | Where-Object { $_.requirement_id -eq $RequirementId -and $_.status -eq "active" })
$previousVersion = if ($priorEvents.Count -gt 0) { [int](($priorEvents | Measure-Object version -Maximum).Maximum) } else { $null }
$requirementVersion = if ($null -eq $previousVersion) { 1 } else { $previousVersion + 1 }
$baselineMatch = [regex]::Match($current, '(?m)^- \*\*baseline_version\*\*: (\d+)\s*$')
$baselineVersion = if ($baselineMatch.Success) { [int]$baselineMatch.Groups[1].Value + 1 } else { 1 }
$timestamp = (Get-Date).ToString("o")
$actualChangeType = if ($null -eq $previousVersion) { "added" } else { $ChangeType }

$current = [regex]::Replace($current, '(?m)^- \*\*state\*\*: .*$', '- **state**: [ACTIVE]', 1)
$current = [regex]::Replace($current, '(?m)^- \*\*baseline_version\*\*: .*$', ('- **baseline_version**: {0}' -f $baselineVersion), 1)
$current = [regex]::Replace($current, '(?m)^- \*\*updated_at\*\*: .*$', ('- **updated_at**: {0}' -f $timestamp), 1)
$current = [regex]::Replace($current, '(?m)^- \*\*latest_source\*\*: .*$', ('- **latest_source**: {0} / {1}' -f $SourceType, $SourceRef), 1)

$activeStart = '<!-- REQUIREMENTS_ACTIVE_START -->'
$activeEnd = '<!-- REQUIREMENTS_ACTIVE_END -->'
$activePattern = '(?ms)(?<start>' + [regex]::Escape($activeStart) + '\s*)(?<body>.*?)(?<end>\s*' + [regex]::Escape($activeEnd) + ')'
$activeMatch = [regex]::Match($current, $activePattern)
if (-not $activeMatch.Success) {
    throw "requirements/current.md is missing active requirement markers."
}

$body = $activeMatch.Groups['body'].Value.Trim()
$escapedId = [regex]::Escape($RequirementId)
$sectionPattern = '(?ms)^### ' + $escapedId + '\b.*?(?=^### REQ-\d{3,}\b|\z)'
if ($ChangeType -eq "removed") {
    $body = [regex]::Replace($body, $sectionPattern, '').Trim()
} else {
    $affectedText = ($AffectedMemory | ForEach-Object { '`{0}`' -f $_ }) -join ", "
    $section = @(
        ('### {0} {1}' -f $RequirementId, $Title)
        ('- **title**: {0}' -f $Title)
        ('- **version**: {0}' -f $requirementVersion)
        ('- **statement**: {0}' -f $Statement)
        ('- **source_ref**: {0} / {1}' -f $SourceType, $SourceRef)
        '- **implementation_status**: implementation_pending'
        '- **verification_status**: not_verified'
        ('- **affected_memory**: {0}' -f $affectedText)
    ) -join "`n"

    if ([regex]::IsMatch($body, $sectionPattern)) {
        $body = [regex]::Replace($body, $sectionPattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $section }, 1).Trim()
    } elseif ($body) {
        $body = "$body`n`n$section"
    } else {
        $body = $section
    }
}
$current = [regex]::Replace($current, $activePattern, [Text.RegularExpressions.MatchEvaluator]{
    param($match)
    return $activeStart + "`n" + $body.Trim() + "`n" + $activeEnd
}, 1)

if ($null -ne $previousVersion) {
    $supersededStart = '<!-- REQUIREMENTS_SUPERSEDED_START -->'
    $supersededEnd = '<!-- REQUIREMENTS_SUPERSEDED_END -->'
    $supersededPattern = '(?ms)(?<start>' + [regex]::Escape($supersededStart) + '\s*)(?<body>.*?)(?<end>\s*' + [regex]::Escape($supersededEnd) + ')'
    $supersededMatch = [regex]::Match($current, $supersededPattern)
    if (-not $supersededMatch.Success) {
        throw "requirements/current.md is missing superseded requirement markers."
    }
    $supersededBody = $supersededMatch.Groups['body'].Value.Trim()
    $supersededLine = '- {0} v{1} -> v{2}; source: {3} / {4}.' -f $RequirementId, $previousVersion, $requirementVersion, $SourceType, $SourceRef
    if ($supersededBody -notmatch [regex]::Escape($supersededLine)) {
        $supersededBody = if ($supersededBody) { "$supersededBody`n$supersededLine" } else { $supersededLine }
    }
    $current = [regex]::Replace($current, $supersededPattern, [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $supersededStart + "`n" + $supersededBody.Trim() + "`n" + $supersededEnd
    }, 1)
}

$baselineLine = '- **Requirement Baseline**: {0} ({1} v{2})' -f $baselineVersion, $RequirementId, $requirementVersion
if ($activeContext -match '(?m)^- \*\*Requirement Baseline\*\*:') {
    $activeContext = [regex]::Replace($activeContext, '(?m)^- \*\*Requirement Baseline\*\*:.*$', $baselineLine, 1)
} else {
    $activeContext = "<!-- REQUIREMENT_BASELINE -->`n$baselineLine`n`n$activeContext"
}

$event = [ordered]@{
    event_id = "REQEVT-$((Get-Date).ToString('yyyyMMddHHmmssfff'))-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    requirement_id = $RequirementId
    version = $requirementVersion
    timestamp = $timestamp
    source_type = $SourceType
    source_ref = $SourceRef
    raw_summary = $Statement
    change_type = $actualChangeType
    previous_version = $previousVersion
    status = if ($ChangeType -eq "removed") { "removed" } else { "active" }
    affected_memory = @($AffectedMemory)
    implementation_status = "implementation_pending"
    verification_status = "not_verified"
}
$eventJson = $event | ConvertTo-Json -Depth 8 -Compress
$newLog = (($eventLines + $eventJson) -join "`n") + "`n"

Write-AtomicUtf8 -Path $currentPath -Content $current
Write-AtomicUtf8 -Path $changeLogPath -Content $newLog
Write-AtomicUtf8 -Path $activeContextPath -Content $activeContext

[pscustomobject]@{
    RequirementId = $RequirementId
    RequirementVersion = $requirementVersion
    BaselineVersion = $baselineVersion
    ChangeType = $actualChangeType
    PreviousVersion = $previousVersion
}
