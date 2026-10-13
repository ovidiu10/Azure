<#
.SYNOPSIS
    Turn harvested Database Watcher KQL into Grafana alert rules.

.DESCRIPTION
    WHY A TEMPLATE INSTEAD OF GENERATED JSON

    The Azure Data Explorer plugin's query model (field names, pluginVersion,
    resultFormat, expression wiring) changes between plugin releases. Rather than
    hard-code a schema that silently rots, this script clones a rule you already
    built and verified in the UI, and swaps in the KQL and metadata. Whatever
    works in your Grafana keeps working.

.PARAMETER Template
    A rule exported from Grafana, used as the shape for every generated rule.
    Accepts the array returned by the provisioning API or a single rule object.

.PARAMETER QueryRef
    refId of the query whose KQL gets replaced. Expressions are left untouched.

.PARAMETER Shape
    How the expression chain decides to fire.

    RowPresence (default) - the KQL carries its own threshold and returns rows only
    when the condition is already breached, which is how every Database Watcher
    template is written. Rewires Reduce to Count and Threshold to > 0, and sets
    noDataState to OK because zero rows is the healthy state.

    Preserve - leave the template's expressions alone. Use when the template and the
    KQL are both value-based, meaning the query returns an unfiltered measurement and
    the Threshold expression judges it.

    Getting this wrong produces a rule that can never fire and reports no error.

.PARAMETER Post
    Send the generated rules to Grafana. Requires -Grafana and -Token.

.EXAMPLE
    # 1. build ONE rule in the Grafana UI and confirm it fires
    # 2. export it as the template
    curl.exe -s -H "Authorization: Bearer $tok" "$G/api/v1/provisioning/alert-rules" |
        Out-File -Encoding ascii template.json

    # 3. generate and review
    ./kql-to-grafana-rules.ps1 -Template template.json -KqlDir ./alert-templates

    # 4. post
    ./kql-to-grafana-rules.ps1 -Template template.json -KqlDir ./alert-templates `
        -Post -Grafana $G -Token $tok
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Template,
    [string] $KqlDir  = './alert-templates',
    [string] $OutDir  = './alert-rules',
    [string] $QueryRef = 'A',
    [ValidateSet('RowPresence', 'Preserve')]
    [string] $Shape = 'RowPresence',
    [string] $FolderUid,
    [string] $RuleGroup,
    [switch] $Post,
    [string] $Grafana,
    [string] $Token
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Template)) { throw "Template not found: $Template" }
if (-not (Test-Path -LiteralPath $KqlDir))   { throw "KQL directory not found: $KqlDir" }
if ($Post -and (-not $Grafana -or -not $Token)) { throw '-Post requires -Grafana and -Token' }

# Kept as raw text so each rule can be deserialized fresh - reusing one object
# would make every generated rule share the same nested references.
$templateRaw = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Template))
$probe = $templateRaw | ConvertFrom-Json
if ($probe -is [array]) {
    if ($probe.Count -eq 0) { throw "No rules found in $Template" }
    $templateRaw = $probe[0] | ConvertTo-Json -Depth 100
}

$probeRule = $templateRaw | ConvertFrom-Json
if (-not ($probeRule.data | Where-Object { $_.refId -eq $QueryRef })) {
    $refs = ($probeRule.data | ForEach-Object { $_.refId }) -join ', '
    throw "Template has no query with refId '$QueryRef'. Use -QueryRef. Template refIds: $refs"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# .NET file APIs resolve relative paths against the process working directory, which
# is not PowerShell's current location. Pin it to an absolute path once.
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

$kqlFiles = Get-ChildItem -LiteralPath $KqlDir -Filter *.kql -File
if (-not $kqlFiles) { Write-Warning "No .kql files in $KqlDir"; return }

$warned = 0
$rewrote = 0
$shaped = 0
foreach ($f in $kqlFiles) {
    $lines = [IO.File]::ReadAllLines($f.FullName)

    # Header comments are metadata written by harvest-alert-template-kql.
    $title = ($lines | Where-Object { $_ -match '^//\s*Rule:' }        | Select-Object -First 1) -replace '^//\s*Rule:\s*', ''
    $desc  = ($lines | Where-Object { $_ -match '^//\s*Description:' } | Select-Object -First 1) -replace '^//\s*Description:\s*', ''
    $sev   = ($lines | Where-Object { $_ -match '^//\s*Severity:' }    | Select-Object -First 1) -replace '^//\s*Severity:\s*', ''

    if (-not $title) { $title = $f.BaseName }
    if (-not $sev)   { $sev = 'unknown' }

    # Strip the comment block so the rule carries only the query.
    $kql = (($lines | Where-Object { $_ -notmatch '^//' }) -join "`n").Trim()

    # Azure Monitor reaches the cluster with adx('<uri>/<db>').Table cross-service
    # syntax. Grafana's data source is already bound to the cluster and database,
    # so the prefix has to go or every query fails to resolve.
    if ($kql -match "adx\('[^']*'\)\.") {
        $kql = $kql -replace "adx\('[^']*'\)\.", ''
        $rewrote++
    }

    # These templates carry their own ago(lookback) window, so $__timeFilter is
    # optional. Only flag queries that have neither.
    if ($kql -notmatch '\$__timeFilter' -and $kql -notmatch '\bago\s*\(') {
        Write-Warning "$title has no `$__timeFilter and no ago() window - it will scan the whole table"
        $warned++
    }

    $rule = $templateRaw | ConvertFrom-Json

    # Empty uid makes Grafana assign one; reusing the template uid would overwrite it.
    $rule.uid   = ''
    $rule.title = $title

    # The export carries server-side fields. 'id' is the numeric primary key - leaving
    # it in makes every POST collide on alert_rule_pkey with the rule it was cloned from.
    foreach ($p in @('id', 'updated', 'provenance', 'namespace_uid')) {
        if ($rule.PSObject.Properties.Name -contains $p) { $rule.PSObject.Properties.Remove($p) }
    }

    if ($null -eq $rule.labels)      { $rule | Add-Member -NotePropertyName labels      -NotePropertyValue ([pscustomobject]@{}) -Force }
    if ($null -eq $rule.annotations) { $rule | Add-Member -NotePropertyName annotations -NotePropertyValue ([pscustomobject]@{}) -Force }
    $rule.labels      | Add-Member -NotePropertyName severity    -NotePropertyValue $sev  -Force
    $rule.annotations | Add-Member -NotePropertyName description -NotePropertyValue $desc -Force

    if ($FolderUid) { $rule.folderUID = $FolderUid }
    if ($RuleGroup) { $rule.ruleGroup = $RuleGroup }

    foreach ($d in $rule.data) {
        if ($d.refId -eq $QueryRef) { $d.model.query = $kql }
    }

    if ($Shape -eq 'RowPresence') {
        foreach ($d in $rule.data) {
            switch ($d.model.type) {
                'reduce' {
                    # Count the rows the query returned. The template was almost certainly
                    # built with 'last' against a metric column these queries do not have.
                    $d.model.reducer = 'count'
                    foreach ($c in $d.model.conditions) {
                        if ($c.reducer) { $c.reducer.type = 'count' }
                    }
                }
                'threshold' {
                    foreach ($c in $d.model.conditions) {
                        $c.evaluator.type = 'gt'
                        $c.evaluator.params = @(0)
                        # Hysteresis carried over from the template would keep the rule
                        # firing below its own threshold.
                        if ($c.PSObject.Properties.Name -contains 'unloadEvaluator') {
                            $c.PSObject.Properties.Remove('unloadEvaluator')
                        }
                    }
                }
            }
        }
        # Zero rows is healthy here, but Grafana treats NoData as its own condition and
        # would raise DatasourceNoData on every healthy evaluation.
        $rule.noDataState = 'OK'
        $shaped++
    }

    $outPath = Join-Path $OutDir "$($f.BaseName).json"
    # Depth matters - ConvertTo-Json defaults to 2 and would flatten the query model.
    [IO.File]::WriteAllText($outPath, ($rule | ConvertTo-Json -Depth 100))
    Write-Host "  $title -> $outPath"
}

Write-Host ''
Write-Host "Generated $($kqlFiles.Count) rule(s) in $OutDir/"
if ($rewrote -gt 0) { Write-Host "$rewrote rule(s) had the Azure Monitor adx('...') prefix removed." }
if ($shaped -gt 0) { Write-Host "$shaped rule(s) shaped as row-presence: Reduce=count, Threshold>0, noDataState=OK." }
if ($warned -gt 0) { Write-Host "$warned rule(s) have no time window and will scan the whole table." }

if ($Post) {
    Write-Host ''
    Write-Host "Posting to $Grafana ..."

    # X-Disable-Provenance keeps the rules editable in the UI. Without it Grafana
    # marks them as provisioned and read-only, and thresholds can only be changed
    # through the API.
    $headers = @{
        Authorization           = "Bearer $Token"
        'X-Disable-Provenance'  = 'true'
    }

    foreach ($r in Get-ChildItem -LiteralPath $OutDir -Filter *.json -File) {
        $body = [IO.File]::ReadAllText($r.FullName)
        $name = ($body | ConvertFrom-Json).title
        try {
            Invoke-RestMethod -Method Post -Uri "$($Grafana.TrimEnd('/'))/api/v1/provisioning/alert-rules" `
                -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
            Write-Host "  OK   $name"
        }
        catch {
            Write-Host "  FAIL $name - $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) { Write-Host "       $($_.ErrorDetails.Message)" }
        }
    }
}
