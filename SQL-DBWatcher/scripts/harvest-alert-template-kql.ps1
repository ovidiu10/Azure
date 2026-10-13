<#
.SYNOPSIS
    Harvest the KQL from Database Watcher's built-in alert rule templates.

.DESCRIPTION
    The alert templates are only exposed through the watcher's "Alert templates"
    blade in the portal, and you cannot create them against an ADX cluster that has
    public access disabled - which is exactly the situation this whole design solves.

    So: create the rules ONCE while ADX public access is still on (or in a throwaway
    lab subscription), export the resource group's ARM template, and pull every query
    out in one shot. You then port that KQL into Grafana alert rules, which
    kql-to-grafana-rules.ps1 automates.

    Repeat this whenever Microsoft revises the templates - they are versioned
    year-month-day.number on the Alert templates blade.

.PARAMETER ResourceGroup
    Resource group containing the created alert rules. This is NOT the watcher
    resource group unless you created the templates there.

.PARAMETER OutDir
    Where to write the .kql files. Gitignored by default - exported ARM contains
    subscription and resource ids.

.EXAMPLE
    ./harvest-alert-template-kql.ps1 -ResourceGroup rg-alert-template-lab
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [string] $OutDir = './alert-templates'
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# .NET file APIs resolve relative paths against the process working directory, which
# is not PowerShell's current location. Pin it to an absolute path once.
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

Write-Host "Exporting ARM template from resource group: $ResourceGroup"
$export = az group export --name $ResourceGroup --skip-all-params -o json
if ($LASTEXITCODE -ne 0) {
    throw "az group export failed. Not every resource type supports export; if this resource group contains preview resources, create the alert rules in a resource group of their own."
}
[IO.File]::WriteAllText((Join-Path $OutDir '_export.json'), $export)

Write-Host 'Extracting scheduled query rules...'
$rules = ($export | ConvertFrom-Json).resources |
    Where-Object { $_.type -eq 'Microsoft.Insights/scheduledQueryRules' }

if (-not $rules) {
    Write-Warning "Found 0 alert rules in $ResourceGroup. Create the built-in templates from the watcher's 'Alert templates' blade first."
    return
}

Write-Host "Found $(@($rules).Count) alert rules."

foreach ($rule in $rules) {
    $rawName = if ($rule.name) { $rule.name } else { 'unnamed' }
    $safe = ($rawName -replace '[^\w.\-]', '') -replace '^\[', ''
    if (-not $safe) { $safe = "rule-$(Get-Random)" }

    $header = @(
        "// Rule:        $rawName"
        "// Description: $($rule.properties.description)"
        "// Severity:    $($rule.properties.severity)"
        "// Frequency:   $($rule.properties.evaluationFrequency)"
        "// Window:      $($rule.properties.windowSize)"
        '//'
        '// Porting to Grafana:'
        '//   - set the ADX data source query format to Table'
        '//   - replace hardcoded time filters with $__timeFilter(sample_time_utc)'
        '//   - keep an identity column (managed_instance_name, resource_id) so Grafana'
        '//     emits one alert instance per SQL MI'
        '//   - move the threshold into a Threshold expression where practical'
        ''
        $rule.properties.criteria.allOf[0].query
    ) -join "`n"

    $path = Join-Path $OutDir "$safe.kql"
    [IO.File]::WriteAllText($path, $header)
    Write-Host "  $rawName -> $path"
}

Write-Host ''
Write-Host "Wrote $(@($rules).Count) .kql files to $OutDir/"
Write-Host 'Review them, then generate Grafana rules with:'
Write-Host "  ./kql-to-grafana-rules.ps1 -Template template.json -KqlDir $OutDir"
