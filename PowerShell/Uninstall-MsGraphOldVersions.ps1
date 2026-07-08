<#
.SYNOPSIS
    Uninstalls all old versions of the Microsoft.Graph meta-module and every
    Microsoft.Graph.* sub-module, keeping only the latest version currently
    installed on the machine.

.DESCRIPTION
    For each installed module whose name is "Microsoft.Graph" or starts with
    "Microsoft.Graph.":
        1. Find every installed version.
        2. Identify the highest version (latest already installed).
        3. Uninstall every other version.

    Microsoft.Graph.Authentication is uninstalled LAST because every other
    Microsoft.Graph.* sub-module depends on it.

    Run from an elevated PowerShell session if the modules live under a system
    path (e.g. C:\Program Files\WindowsPowerShell\Modules). Close all other
    PowerShell sessions before running so module files are not locked.

.PARAMETER WhatIf
    Shows which versions would be removed without actually removing them.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    .\Uninstall-MsGraphOldVersions.ps1 -WhatIf

.EXAMPLE
    .\Uninstall-MsGraphOldVersions.ps1 -Force
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Pre-flight checks -------------------------------------------------------
if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()
              ).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
} else {
    $isAdmin = $true # non-Windows: assume sufficient permission
}

$otherSessions = @(Get-Process -Name powershell, pwsh -ErrorAction SilentlyContinue) |
                 Where-Object { $_.Id -ne $PID }
if ($otherSessions.Count -gt 0) {
    Write-Warning ("There are {0} other PowerShell session(s) running. Close them before continuing or modules may be locked." -f $otherSessions.Count)
}

# --- Collect installed Microsoft.Graph / Microsoft.Graph.* modules ----------
Write-Host 'Scanning installed modules...' -ForegroundColor Cyan

# Get-InstalledModule -AllVersions does NOT accept wildcards or multiple names,
# so first discover the distinct module names, then query each one for all
# installed versions.
$names = Get-InstalledModule -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -eq 'Microsoft.Graph' -or $_.Name -like 'Microsoft.Graph.*' } |
         Select-Object -ExpandProperty Name -Unique

$installed = foreach ($n in $names) {
    Get-InstalledModule -Name $n -AllVersions -ErrorAction SilentlyContinue
}

if (-not $installed) {
    Write-Host 'No Microsoft.Graph or Microsoft.Graph.* modules are installed. Nothing to do.' -ForegroundColor Yellow
    return
}

# Group by module name and figure out which version to keep (the highest).
$plan = $installed |
    Group-Object -Property Name |
    ForEach-Object {
        $sorted = $_.Group | Sort-Object -Property { [version]($_.Version -replace '-.*$') } -Descending
        [pscustomobject]@{
            Name           = $_.Name
            KeepVersion    = $sorted[0].Version
            RemoveVersions = @($sorted | Select-Object -Skip 1 | ForEach-Object Version)
        }
    }

$toRemove = $plan | Where-Object { $_.RemoveVersions.Count -gt 0 }

if (-not $toRemove) {
    Write-Host 'Only the latest version of each Microsoft.Graph / Microsoft.Graph.* module is installed. Nothing to remove.' -ForegroundColor Green
    return
}

# --- Show plan ---------------------------------------------------------------
Write-Host ''
Write-Host 'The following old versions will be uninstalled:' -ForegroundColor Cyan
$toRemove | ForEach-Object {
    Write-Host ('  {0,-40} keep {1,-12} remove {2}' -f $_.Name, $_.KeepVersion, ($_.RemoveVersions -join ', '))
}

$moduleCount  = ($toRemove | Measure-Object).Count
$versionCount = ($toRemove | ForEach-Object { $_.RemoveVersions.Count } |
                 Measure-Object -Sum).Sum

Write-Host ''
Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host ('Summary: {0} module(s), {1} version(s) to uninstall.' -f $moduleCount, $versionCount) -ForegroundColor Yellow
Write-Host '------------------------------------------------------------' -ForegroundColor DarkGray

# --- Checkpoint: ask the user before doing anything --------------------------
if ($WhatIfPreference) {
    Write-Host 'WhatIf mode — no changes will be made.' -ForegroundColor Yellow
}
elseif (-not $Force) {
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes',  'Proceed and uninstall the listed versions.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&No',   'Cancel and exit without changes.')
        [System.Management.Automation.Host.ChoiceDescription]::new('&List', 'Show the full list again, then ask again.')
    )

    do {
        $reply = $Host.UI.PromptForChoice(
            'Confirm uninstall',
            'Do you want to continue and uninstall the old Microsoft.Graph / Microsoft.Graph.* versions listed above?',
            $choices,
            1  # default = No
        )

        switch ($reply) {
            0 { break }
            1 {
                Write-Host 'Aborted by user. No modules were uninstalled.' -ForegroundColor Yellow
                return
            }
            2 {
                Write-Host ''
                $toRemove | ForEach-Object {
                    Write-Host ('  {0,-40} keep {1,-12} remove {2}' -f $_.Name, $_.KeepVersion, ($_.RemoveVersions -join ', '))
                }
                Write-Host ''
            }
        }
    } while ($reply -eq 2)
}

# --- Uninstall order:
#       1. sub-modules (Microsoft.Graph.*)         except Authentication
#       2. Microsoft.Graph (meta-module)
#       3. Microsoft.Graph.Authentication          (everything depends on it)
# ----------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]

$subOthers     = @($toRemove | Where-Object { $_.Name -like 'Microsoft.Graph.*' -and $_.Name -ne 'Microsoft.Graph.Authentication' })
$metaModule    = @($toRemove | Where-Object { $_.Name -eq 'Microsoft.Graph' })
$authentication = @($toRemove | Where-Object { $_.Name -eq 'Microsoft.Graph.Authentication' })

$ordered = $subOthers + $metaModule + $authentication

$total = ($ordered | ForEach-Object { $_.RemoveVersions.Count } |
          Measure-Object -Sum).Sum
$done  = 0

foreach ($entry in $ordered) {
    foreach ($ver in $entry.RemoveVersions) {
        $done++
        $pct = [int](($done / [math]::Max($total,1)) * 100)
        Write-Progress -Activity 'Uninstalling old Microsoft.Graph modules' `
                       -Status ("{0} {1}" -f $entry.Name, $ver) `
                       -PercentComplete $pct

        try {
            if (-not $isAdmin) {
                $loc = (Get-InstalledModule -Name $entry.Name -RequiredVersion $ver -ErrorAction SilentlyContinue).InstalledLocation
                if ($loc -and $loc -notlike "*$env:USERPROFILE*") {
                    throw 'Requires elevation (system-scope module).'
                }
            }

            Remove-Module -FullyQualifiedName @{ModuleName=$entry.Name; ModuleVersion=$ver} `
                          -Force -ErrorAction SilentlyContinue

            if ($PSCmdlet.ShouldProcess("$($entry.Name) $ver", 'Uninstall-Module')) {
                Uninstall-Module -Name $entry.Name -RequiredVersion $ver -Force -ErrorAction Stop
            }
            $state = 'Uninstalled'
        } catch {
            $state = "Failed: $($_.Exception.Message)"
            Write-Warning ("Could not uninstall {0} {1}: {2}" -f $entry.Name, $ver, $_.Exception.Message)
        }

        $results.Add([pscustomobject]@{
            Name    = $entry.Name
            Version = $ver
            State   = $state
        })
    }
}

Write-Progress -Activity 'Uninstalling old Microsoft.Graph modules' -Completed

# --- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
$results | Format-Table -AutoSize
