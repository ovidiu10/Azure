#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.Governance, Microsoft.Graph.Users, Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Azure PIM Role Management Script - Get current roles and request role activations

.DESCRIPTION
    This script provides functionality to:
    - Get current active PIM role assignments (both Entra ID and Azure Resource roles)
    - List eligible PIM roles that can be activated
    - Request activation of specific PIM roles
    - Display role information in a formatted output

.EXAMPLE
    .\pim.ps1
    # Runs the interactive menu to select operations

.EXAMPLE
    Get-CurrentPIMRoles
    # Gets all currently active PIM roles

.EXAMPLE
    Get-EligiblePIMRoles
    # Gets all eligible PIM roles that can be activated

.EXAMPLE
    Request-PIMRoleActivation
    # Interactive role activation process

.NOTES
    Author: Generated based on https://github.com/gcbikram/azure-pim-roles-activation
    Requires: Microsoft Graph PowerShell SDK and Azure PowerShell modules
#>

# Global variables
$Global:MgContext = $null
$Global:AzContext = $null
$Global:CurrentUserObjectId = $null

#region Connection Functions

function Initialize-Connections {
    <#
    .SYNOPSIS
        Initialize connections to Microsoft Graph and Azure
    #>
    Write-Host "Initializing connections..." -ForegroundColor Cyan
    
    # Check if already connected to Microsoft Graph
    $Global:MgContext = Get-MgContext
    if (-not $Global:MgContext) {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
        try {
            Connect-MgGraph #-Scopes "RoleManagement.ReadWrite.Directory", "Directory.Read.All" -NoWelcome
            $Global:MgContext = Get-MgContext
        }
        catch {
            throw "Failed to establish Microsoft Graph connection: $($_.Exception.Message)"
        }
    }
    
    if (-not $Global:MgContext) {
        throw "Failed to establish Microsoft Graph connection."
    }
    
    Write-Host "✓ Connected to Microsoft Graph - Tenant: $($Global:MgContext.TenantId)" -ForegroundColor Green
    Write-Host "✓ Account: $($Global:MgContext.Account)" -ForegroundColor Green
    
    # Check Azure PowerShell connection
    $Global:AzContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $Global:AzContext) {
        Write-Host "Connecting to Azure PowerShell..." -ForegroundColor Yellow
        try {
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $Global:AzContext = Get-AzContext -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "Warning: Could not connect to Azure PowerShell. Azure Resource roles will not be available." -ForegroundColor Yellow
        }
    }
    
    if ($Global:AzContext) {
        Write-Host "✓ Connected to Azure - Subscription: $($Global:AzContext.Subscription.Name)" -ForegroundColor Green
    } else {
        Write-Host "Note: Azure PowerShell not connected. Will only check Entra ID roles." -ForegroundColor Yellow
    }
    
    # Get current user object ID
    try {
        $currentUser = Get-MgUser -UserId $Global:MgContext.Account
        $Global:CurrentUserObjectId = $currentUser.Id
        Write-Host "✓ Current user: $($currentUser.DisplayName) ($($currentUser.UserPrincipalName))" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not retrieve user details." -ForegroundColor Yellow
        $Global:CurrentUserObjectId = $Global:MgContext.Account
    }
}

#endregion

#region Current Active Roles Functions

function Get-CurrentPIMRoles {
    <#
    .SYNOPSIS
        Get all currently active PIM role assignments for the current user
    #>
    Write-Host "`nRetrieving current active PIM roles..." -ForegroundColor Cyan
    
    $activeRoles = @()
    
    # Get active Entra ID roles
    $entraActiveRoles = Get-CurrentEntraIDRoles
    $activeRoles += $entraActiveRoles
    
    # Get active Azure Resource roles if connected
    if ($Global:AzContext) {
        $azureActiveRoles = Get-CurrentAzureResourceRoles
        $activeRoles += $azureActiveRoles
    }
    
    if ($activeRoles.Count -eq 0) {
        Write-Host "No active PIM roles found for current user." -ForegroundColor Yellow
        return @()
    }
    
    Write-Host "`nCurrently Active PIM Roles:" -ForegroundColor Green
    Write-Host "=============================" -ForegroundColor Green
    
    $activeRoles | ForEach-Object -Begin { $counter = 1 } -Process {
        Write-Host "$counter. $($_.DisplayName)" -ForegroundColor Yellow
        Write-Host "   Type: $($_.RoleType)" -ForegroundColor Cyan
        Write-Host "   Scope: $($_.ScopeDisplayName)" -ForegroundColor Gray
        if ($_.ExpirationTime) {
            Write-Host "   Expires: $($_.ExpirationTime)" -ForegroundColor Magenta
        }
        Write-Host ""
        $counter++
    }
    
    return $activeRoles
}

function Get-CurrentEntraIDRoles {
    <#
    .SYNOPSIS
        Get currently active Entra ID PIM roles
    #>
    $activeRoles = @()
    
    try {
        # Get active role assignments
        $myActiveRoles = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -ExpandProperty RoleDefinition -All -Filter "principalId eq '$Global:CurrentUserObjectId'"
        
        foreach ($role in $myActiveRoles) {
            $scopeDisplayName = "/"
            $scopeType = "Directory"
            
            if ($role.DirectoryScopeId -ne "/" -and $role.DirectoryScopeId) {
                $scopeDisplayName = $role.DirectoryScopeId
                $scopeType = "Custom"
            }
            
            $activeRoles += [PSCustomObject]@{
                DisplayName = $role.RoleDefinition.DisplayName
                RoleDefinitionId = $role.RoleDefinitionId
                PrincipalId = $role.PrincipalId
                DirectoryScopeId = $role.DirectoryScopeId
                ScopeDisplayName = $scopeDisplayName
                ScopeType = $scopeType
                RoleType = "Entra ID"
                ExpirationTime = $role.EndDateTime
                StartTime = $role.StartDateTime
            }
        }
    }
    catch {
        Write-Host "Warning: Failed to retrieve active Entra ID PIM roles: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    return $activeRoles
}

function Get-CurrentAzureResourceRoles {
    <#
    .SYNOPSIS
        Get currently active Azure Resource PIM roles
    #>
    $activeRoles = @()
    
    try {
        $headers = Get-AzureARMHeaders
        $url = "https://management.azure.com/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
        Write-Host "   Querying Azure Resource Manager for active role assignments..." -ForegroundColor Gray
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        foreach ($assignment in $response.value) {
            $scope = $assignment.properties.scope
            $roleDefinitionId = $assignment.properties.roleDefinitionId
            $roleDisplayName = $assignment.properties.roleDefinitionDisplayName
            
            # Parse scope information
            $scopeInfo = Get-ScopeDisplayInfo -Scope $scope
            
            $activeRoles += [PSCustomObject]@{
                DisplayName = $roleDisplayName
                RoleDefinitionId = $roleDefinitionId
                PrincipalId = $assignment.properties.principalId
                Scope = $scope
                ScopeDisplayName = $scopeInfo.DisplayName
                ScopeType = $scopeInfo.Type
                RoleType = "Azure Resource"
                ExpirationTime = $assignment.properties.endDateTime
                StartTime = $assignment.properties.startDateTime
            }
        }
    }
    catch {
        Write-Host "Warning: Failed to retrieve active Azure Resource PIM roles: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    return $activeRoles
}

#endregion

#region Eligible Roles Functions

function Get-EligiblePIMRoles {
    <#
    .SYNOPSIS
        Get all eligible PIM roles that can be activated
    #>
    Write-Host "`nRetrieving eligible PIM roles..." -ForegroundColor Cyan
    
    $eligibleRoles = @()
    
    # Get eligible Entra ID roles
    $entraRoles = Get-EntraIDEligibleRoles
    $eligibleRoles += $entraRoles
    
    # Get eligible Azure Resource roles if connected
    if ($Global:AzContext) {
        $azureRoles = Get-AzureResourceEligibleRoles
        $eligibleRoles += $azureRoles
    }
    
    if ($eligibleRoles.Count -eq 0) {
        Write-Host "No eligible PIM roles found for current user." -ForegroundColor Yellow
        return @()
    }
    
    Write-Host "`nEligible PIM Roles:" -ForegroundColor Green
    Write-Host "==================" -ForegroundColor Green
    Write-Host "Found $($entraRoles.Count) Entra ID roles and $(($eligibleRoles | Where-Object { $_.RoleType -eq 'Azure Resource' }).Count) Azure resource roles" -ForegroundColor Cyan
    
    Show-AvailableRoles -Roles $eligibleRoles
    
    return $eligibleRoles
}

function Get-EntraIDEligibleRoles {
    <#
    .SYNOPSIS
        Get eligible Entra ID PIM roles
    #>
    Write-Host "Retrieving eligible Entra ID PIM roles..." -ForegroundColor Gray
    $entraRoles = @()
    
    try {
        $myRoles = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -ExpandProperty RoleDefinition -All -Filter "principalId eq '$Global:CurrentUserObjectId'"
        
        foreach ($role in $myRoles) {
            $scopeDisplayName = "/"
            $scopeType = "Directory"
            
            if ($role.DirectoryScopeId -ne "/" -and $role.DirectoryScopeId) {
                $scopeDisplayName = $role.DirectoryScopeId
                $scopeType = "Custom"
            }
            
            $entraRoles += [PSCustomObject]@{
                DisplayName = $role.RoleDefinition.DisplayName
                RoleDefinitionId = $role.RoleDefinitionId
                PrincipalId = $role.PrincipalId
                DirectoryScopeId = $role.DirectoryScopeId
                ScopeDisplayName = $scopeDisplayName
                ScopeType = $scopeType
                RoleType = "Entra ID"
            }
        }
    }
    catch {
        Write-Host "Warning: Failed to retrieve Entra ID PIM roles: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    
    return $entraRoles
}

function Get-AzureResourceEligibleRoles {
    <#
    .SYNOPSIS
        Get eligible Azure Resource PIM roles
    #>
    try {
        Write-Host "Retrieving Azure resource PIM eligible roles..." -ForegroundColor Gray
        
        $headers = Get-AzureARMHeaders
        $url = "https://management.azure.com/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        
        $roleDefinitionCache = @{}
        $azureRoles = @()
        
        foreach ($assignment in $response.value) {
            $scope = $assignment.properties.scope
            $roleDefinitionId = $assignment.properties.roleDefinitionId
            $roleDisplayName = $assignment.properties.roleDefinitionDisplayName
            
            # Get the role display name if missing
            if ([string]::IsNullOrWhiteSpace($roleDisplayName)) {
                if ($roleDefinitionCache.ContainsKey($roleDefinitionId)) {
                    $roleDisplayName = $roleDefinitionCache[$roleDefinitionId]
                } else {
                    try {
                        $roleDefUrl = "https://management.azure.com$roleDefinitionId" + "?api-version=2022-04-01"
                        $roleDefResponse = Invoke-RestMethod -Uri $roleDefUrl -Headers $headers -Method Get
                        $roleDisplayName = $roleDefResponse.properties.roleName
                        $roleDefinitionCache[$roleDefinitionId] = $roleDisplayName
                    }
                    catch {
                        $roleDisplayName = "Unknown Role ($($roleDefinitionId.Split('/')[-1]))"
                    }
                }
            }
            
            $scopeInfo = Get-ScopeDisplayInfo -Scope $scope
            
            $azureRoles += [PSCustomObject]@{
                DisplayName = $roleDisplayName
                RoleDefinitionId = $roleDefinitionId
                PrincipalId = $assignment.properties.principalId
                Scope = $scope
                ScopeDisplayName = $scopeInfo.DisplayName
                ScopeType = $scopeInfo.Type
                RoleType = "Azure Resource"
            }
        }
        
        Write-Host "   Found $($azureRoles.Count) Azure resource eligible roles" -ForegroundColor Gray
        return $azureRoles
    }
    catch {
        Write-Host "Warning: Could not retrieve Azure resource roles: $($_.Exception.Message)" -ForegroundColor Yellow
        return @()
    }
}

#endregion

#region Role Activation Functions

function Request-PIMRoleActivation {
    <#
    .SYNOPSIS
        Interactive function to request PIM role activation
    #>
    # Get eligible roles
    $eligibleRoles = Get-EligiblePIMRoles
    
    if ($eligibleRoles.Count -eq 0) {
        return
    }
    
    # Prompt user for selection
    Write-Host "`nActivation Options:" -ForegroundColor Cyan
    Write-Host "  Enter role number(s) (e.g., 1,3,5 for multiple roles)" -ForegroundColor White
    Write-Host "  Enter 'ALL' to activate all roles" -ForegroundColor White
    Write-Host "  Enter 'Q' to quit" -ForegroundColor White
    
    $userChoice = Read-Host "`nPlease select your option"
    
    if ($userChoice.ToUpper() -eq 'Q') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        return
    }
    
    # Get justification from user
    $justification = Read-Host "Enter justification for role activation (press Enter for default)"
    if ([string]::IsNullOrWhiteSpace($justification)) {
        $justification = "Administrative work requirement"
    }
    
    # Get duration
    $duration = Read-Host "Enter activation duration in hours (1-8, default is 8)"
    if ([string]::IsNullOrWhiteSpace($duration) -or $duration -notmatch '^\d+$' -or [int]$duration -lt 1 -or [int]$duration -gt 8) {
        $duration = 8
    }
    
    $activatedCount = 0
    $failedCount = 0
    
    if ($userChoice.ToUpper() -eq 'ALL') {
        # Activate all roles
        Write-Host "`nActivating all eligible roles..." -ForegroundColor Cyan
        
        foreach ($role in $eligibleRoles) {
            if (Invoke-RoleActivation -Role $role -Justification $justification -Duration $duration) {
                $activatedCount++
            } else {
                $failedCount++
            }
            Start-Sleep -Seconds 1
        }
    }
    else {
        # Activate selected roles
        $selectedNumbers = $userChoice -split ',' | ForEach-Object { $_.Trim() }
        
        foreach ($number in $selectedNumbers) {
            if ($number -match '^\d+$' -and [int]$number -ge 1 -and [int]$number -le $eligibleRoles.Count) {
                $roleIndex = [int]$number - 1
                if (Invoke-RoleActivation -Role $eligibleRoles[$roleIndex] -Justification $justification -Duration $duration) {
                    $activatedCount++
                } else {
                    $failedCount++
                }
                Start-Sleep -Seconds 1
            }
            else {
                Write-Host "Invalid selection: $number" -ForegroundColor Red
                $failedCount++
            }
        }
    }
    
    # Summary
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "           ACTIVATION SUMMARY" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Successfully activated: $activatedCount roles" -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Host "Failed activations: $failedCount" -ForegroundColor Red
    }
    Write-Host "Roles will be active for $duration hours from activation time." -ForegroundColor Cyan
}

function Invoke-RoleActivation {
    <#
    .SYNOPSIS
        Activate a single PIM role
    #>
    param(
        [PSCustomObject]$Role,
        [string]$Justification = "Administrative work requirement",
        [int]$Duration = 8
    )
    
    try {
        Write-Host "Activating $($Role.RoleType) role: $($Role.DisplayName) at scope: $($Role.ScopeDisplayName)..." -ForegroundColor Yellow
        
        if ($Role.RoleType -eq "Entra ID") {
            # Entra ID role activation
            $params = @{
                Action = "selfActivate"
                PrincipalId = $Role.PrincipalId
                RoleDefinitionId = $Role.RoleDefinitionId
                DirectoryScopeId = $Role.DirectoryScopeId
                Justification = $Justification
                ScheduleInfo = @{
                    StartDateTime = Get-Date
                    Expiration = @{
                        Type = "AfterDuration"
                        Duration = "PT${Duration}H"
                    }
                }
            }
            
            New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params | Out-Null
        }
        else {
            # Azure resource role activation
            $guid = [guid]::NewGuid().ToString()
            $startTime = (Get-Date).ToString("o")
            
            try {
                $result = New-AzRoleAssignmentScheduleRequest `
                    -Name $guid `
                    -Scope $Role.Scope `
                    -ExpirationDuration "PT${Duration}H" `
                    -ExpirationType "AfterDuration" `
                    -PrincipalId $Global:CurrentUserObjectId `
                    -RequestType "SelfActivate" `
                    -RoleDefinitionId $Role.RoleDefinitionId `
                    -ScheduleInfoStartDateTime $startTime `
                    -Justification $Justification `
                    -ErrorAction Stop 2>$null
            }
            catch {
                $errorMessage = $_.Exception.Message
                if ($errorMessage -like "*already exists*" -or $errorMessage -like "*Role assignment already exists*") {
                    Write-Host "⚠ Role already active (detected during activation): $($Role.DisplayName) ($($Role.ScopeDisplayName))" -ForegroundColor Yellow
                    return $true
                }
                else {
                    throw
                }
            }
        }
        
        Write-Host "✓ Successfully activated: $($Role.DisplayName) at scope: $($Role.ScopeDisplayName) [Active for $Duration hours]" -ForegroundColor Green
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -like "*already exists*" -or $errorMessage -like "*Role assignment already exists*") {
            Write-Host "⚠ Role already active: $($Role.DisplayName) ($($Role.ScopeDisplayName))" -ForegroundColor Yellow
            return $true
        }
        else {
            Write-Host "✗ Failed to activate $($Role.DisplayName) at scope: $($Role.ScopeDisplayName): $errorMessage" -ForegroundColor Red
            return $false
        }
    }
}

#endregion

#region Helper Functions

function Get-AzureARMHeaders {
    <#
    .SYNOPSIS
        Get Azure ARM API headers
    #>
    try {
        # Ensure we have an active Azure context
        $azContext = Get-AzContext -ErrorAction Stop
        if (-not $azContext) {
            throw "No active Azure context. Please run Connect-AzAccount first."
        }
        
        # Get a fresh access token for Azure Resource Manager
        $tokenResult = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -ErrorAction Stop
        
        if (-not $tokenResult -or [string]::IsNullOrWhiteSpace($tokenResult.Token)) {
            throw "Failed to obtain a valid access token."
        }
        
        return @{
            Authorization = "Bearer $($tokenResult.Token)"
            'Content-Type' = 'application/json'
        }
    }
    catch {
        Write-Host "Error obtaining Azure ARM token: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Attempting to refresh Azure connection..." -ForegroundColor Yellow
        
        # Try to reconnect
        try {
            Connect-AzAccount -ErrorAction Stop | Out-Null
            $tokenResult = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -ErrorAction Stop
            return @{
                Authorization = "Bearer $($tokenResult.Token)"
                'Content-Type' = 'application/json'
            }
        }
        catch {
            throw "Failed to get Azure ARM access token after reconnection attempt: $($_.Exception.Message)"
        }
    }
}

function Get-ScopeDisplayInfo {
    <#
    .SYNOPSIS
        Parse scope information for display
    #>
    param([string]$Scope)
    
    $scopeDisplayName = $Scope
    $scopeType = "Resource"
    
    if ($Scope -match '/subscriptions/([^/]+)') {
        $subId = $matches[1]
        if ($Scope -match '/resourceGroups/([^/]+)') {
            $rgName = $matches[1]
            $scopeType = "Resource Group"
            $scopeDisplayName = "RG: $rgName"
        } elseif ($Scope -match '/providers/([^/]+)/([^/]+)/([^/]+)') {
            $resourceType = $matches[2]
            $resourceName = $matches[3]
            $scopeType = "Resource"
            $scopeDisplayName = "$resourceType`: $resourceName"
        } else {
            $scopeType = "Subscription"
            try {
                $sub = Get-AzSubscription -SubscriptionId $subId -ErrorAction SilentlyContinue
                $scopeDisplayName = "Sub: $($sub.Name)"
            } catch {
                $scopeDisplayName = "Sub: $subId"
            }
        }
    }
    
    return @{
        DisplayName = $scopeDisplayName
        Type = $scopeType
    }
}

function Show-AvailableRoles {
    <#
    .SYNOPSIS
        Display roles in a formatted table
    #>
    param([array]$Roles)
    
    Write-Host ""
    for ($i = 0; $i -lt $Roles.Count; $i++) {
        $role = $Roles[$i]
        Write-Host "$($i + 1). $($role.DisplayName)" -ForegroundColor Yellow
        Write-Host "   Type: $($role.RoleType)" -ForegroundColor Cyan
        Write-Host "   Scope: $($role.ScopeDisplayName) ($($role.ScopeType))" -ForegroundColor Gray
        Write-Host ""
    }
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Display the main menu
    #>
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "        Azure PIM Role Manager" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "1. Get Current Active PIM Roles" -ForegroundColor White
    Write-Host "2. Get Eligible PIM Roles" -ForegroundColor White
    Write-Host "3. Request PIM Role Activation" -ForegroundColor White
    Write-Host "4. Exit" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
}

#endregion

#region Main Script Execution

function Start-PIMManager {
    <#
    .SYNOPSIS
        Main interactive menu function
    #>
    try {
        # Initialize connections
        Initialize-Connections
        
        do {
            Show-MainMenu
            $choice = Read-Host "`nSelect an option (1-4)"
            
            switch ($choice) {
                "1" {
                    Get-CurrentPIMRoles | Out-Null
                    Read-Host "`nPress Enter to continue"
                }
                "2" {
                    Get-EligiblePIMRoles | Out-Null
                    Read-Host "`nPress Enter to continue"
                }
                "3" {
                    Request-PIMRoleActivation
                    Read-Host "`nPress Enter to continue"
                }
                "4" {
                    Write-Host "Goodbye!" -ForegroundColor Cyan
                    break
                }
                default {
                    Write-Host "Invalid option. Please select 1-4." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                }
            }
        } while ($choice -ne "4")
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please ensure you have the required permissions and modules are installed." -ForegroundColor Yellow
    }
    finally {
        Write-Host "`nScript execution completed." -ForegroundColor Gray
    }
}

#endregion

# If script is run directly (not dot-sourced), start the interactive menu
#if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Start-PIMManager
#}
#Write-Host "END"
