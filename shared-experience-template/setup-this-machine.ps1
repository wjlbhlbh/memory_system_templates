$ErrorActionPreference = 'Stop'
$experienceDir = (Resolve-Path -LiteralPath $PSScriptRoot).Path
[Environment]::SetEnvironmentVariable('AI_EXPERIENCE_DIR', $experienceDir, 'User')
$env:AI_EXPERIENCE_DIR = $experienceDir
Write-Output "AI_EXPERIENCE_DIR=$experienceDir"
Write-Output 'Restart AI tools to pick up the user environment variable.'
