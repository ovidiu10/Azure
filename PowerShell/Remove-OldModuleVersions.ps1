<#
.SYNOPSIS
  Keeps only the newest version of each PowerShell module in your user module folder,
  plus any exact versions that a kept module pins in its manifest (RequiredVersion),
  and deletes everything else.

.EXAMPLE
  ./Remove-OldModuleVersions.ps1 -WhatIf     # preview what would be removed
  ./Remove-OldModuleVersions.ps1             # actually remove old versions
  ./Remove-OldModuleVersions.ps1 -Name 'Az*','Microsoft.Graph*'   # limit deletion to some modules
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Name = '*',
    [string]$ModulePath = (Join-Path $HOME '.local/share/powershell/Modules')
)

if (-not (Test-Path $ModulePath)) { throw "Module path not found: $ModulePath" }

# --- 1. Inventory every module/version folder --------------------------------
$inventory = @{}   # moduleName -> list of @{Version; Dir}
foreach ($moduleDir in Get-ChildItem -Path $ModulePath -Directory) {
    $list = foreach ($d in Get-ChildItem -Path $moduleDir.FullName -Directory) {
        $v = $null
        if ([version]::TryParse($d.Name, [ref]$v)) {
            [pscustomobject]@{ Version = $v; Dir = $d }
        }
    }
    if ($list) { $inventory[$moduleDir.Name] = @($list | Sort-Object Version -Descending) }
}

# --- 2. Keep set: newest of each module ------------------------------------
$keep  = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[object]]::new()

foreach ($mod in $inventory.Keys) {
    $newest = $inventory[$mod][0]
    if ($keep.Add("$mod|$($newest.Version)")) { $queue.Enqueue(@($mod, $newest)) }
}

# --- 3. Also keep exact versions pinned by kept modules (recursively) ------
while ($queue.Count -gt 0) {
    $mod, $entry = $queue.Dequeue()
    $psd1 = Join-Path $entry.Dir.FullName "$mod.psd1"
    if (-not (Test-Path $psd1)) { continue }

    # Read only the RequiredModules entry from the manifest, so manifests that contain
    # logic elsewhere (e.g. $PSEdition checks, like ExchangeOnlineManagement) still work.
    $required = @()
    try {
        $ast  = [System.Management.Automation.Language.Parser]::ParseFile($psd1, [ref]$null, [ref]$null)
        $hash = $ast.Find({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $false)
        $pair = $hash.KeyValuePairs | Where-Object { $_.Item1.Value -eq 'RequiredModules' } | Select-Object -First 1
        if ($pair) {
            $expr = $pair.Item2.PipelineElements[0].Expression
            $required = @($expr.SafeGetValue())
        }
    }
    catch {
        Write-Warning "Could not read RequiredModules from $psd1 - its pinned dependencies (if any) are not protected."
        continue
    }

    foreach ($req in $required) {
        if ($req -isnot [hashtable] -or -not $req.RequiredVersion) { continue }
        $depName = $req.ModuleName
        $depVer  = [version]$req.RequiredVersion
        if (-not $inventory.ContainsKey($depName)) { continue }

        $match = $inventory[$depName] | Where-Object Version -eq $depVer | Select-Object -First 1
        if ($match -and $keep.Add("$depName|$depVer")) {
            Write-Verbose "Keeping $depName $depVer (pinned by $mod $($entry.Version))"
            $queue.Enqueue(@($depName, $match))
        }
    }
}

# --- 4. Delete everything not in the keep set ------------------------------
$freed = 0L
foreach ($mod in $inventory.Keys | Sort-Object) {
    if (-not ($Name | Where-Object { $mod -like $_ })) { continue }

    # Versions of this module that stay (newest first, plus any pinned ones)
    $keptVersions = ($inventory[$mod] |
        Where-Object { $keep.Contains("$mod|$($_.Version)") } |
        ForEach-Object { $_.Version }) -join ', '

    foreach ($entry in $inventory[$mod]) {
        if ($keep.Contains("$mod|$($entry.Version)")) { continue }

        $size  = (Get-ChildItem $entry.Dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
        $label = "$mod $($entry.Version) (keeping $keptVersions)"

        if ($PSCmdlet.ShouldProcess($label, 'Remove old version')) {
            Remove-Item -LiteralPath $entry.Dir.FullName -Recurse -Force
            $freed += $size
            Write-Host "Removed $label" -ForegroundColor Yellow
        }
    }
}

if (-not $WhatIfPreference) {
    '{0:N2} GB freed' -f ($freed / 1GB)
}