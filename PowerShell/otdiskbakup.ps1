$subId = ""
$bckName = ""
$storageSetting = New-AzDataProtectionBackupVaultStorageSettingObject -Type LocallyRedundant -DataStoreType VaultStore
New-AzDataProtectionBackupVault -ResourceGroupName rg-bkpat -VaultName TestBkpVault -Location EastUS -StorageSetting $storageSetting
$TestBkpVault = Get-AzDataProtectionBackupVault -VaultName TestBkpVault -ResourceGroupName rg-bkpat

$policyDefn = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureDisk

New-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name diskBkpPolicy -Policy $policyDefn

$diskBkpPol = Get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "diskBkpPolicy"

$DiskId = ""
$snapshotrg = ""

$instance = Initialize-AzDataProtectionBackupInstance -DatasourceType AzureDisk -DatasourceLocation $TestBkpvault.Location -PolicyId $diskBkpPol[0].Id -DatasourceId $DiskId

New-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupInstance $instance

$instance = Get-AzDataProtectionBackupInstance -SubscriptionId "" -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name $instance.Name


$AllInstances = Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $AllInstances[0].Name -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "Default"

Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroup rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup

Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $instance.Name -ResourceGroupName rg-bkpat -SubscriptionId $subId -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "BackupWeekly" -TriggerOptionRetentionTagOverride "Default"



###############################

Connect-AzAccount
Get-AzResourceGroup 
Get-AzRecoveryServicesVault -ResourceGroupName rg-bkpat
Get-AzRecoveryServicesVault -ResourceGroupName rg-bkpat -Name vault1bkp
$vault = Get-AzRecoveryServicesVault -ResourceGroupName rg-bkpat -Name vault1bkp
Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -BackupManagementType AzureVM -WorkloadType AzureVM
$BackupItemList = Get-AzRecoveryServicesBackupItem -VaultId $vault.ID -BackupManagementType AzureVM -WorkloadType AzureVM
$BackupItemList
$BackupItemList | Where-Object {$_.Name -match $bckName}
$bckItm = $BackupItemList | Where-Object {$_.Name -match $bckName}
$bckItm
Get-AzRecoveryServicesBackupRecoveryPoint -VaultId $vault.ID -Item $bckItm -IsReadyForMove $true -TargetTier VaultArchive
Get-Module -ListAvailable 
Get-Module -ListAvailable -Name Az.DataProtection
Install-Module az -Scope AllUsers -AllowClobber
Get-Module -ListAvailable -Name Az.DataProtection
Install-Module az -Scope AllUsers -AllowClobber -Force
Get-Module -ListAvailable -Name Az.DataProtection
Get-Module -ListAvailable 
Install-Module Az.DataProtection -Scope AllUsers -AllowClobber
Get-Module -ListAvailable 
Connect-AzAccount
$storageSetting = New-AzDataProtectionBackupVaultStorageSettingObject -Type LocallyRedundant -DataStoreType VaultStore
New-AzDataProtectionBackupVault -ResourceGroupName rg-bkpat -VaultName TestBkpVault -Location EastUS -StorageSetting $storageSetting
Register-AzResourceProvider -ProviderNamespace Microsoft.DataProtection
Get-AzResourceProvider -ProviderNamespace Microsoft.DataProtection
New-AzDataProtectionBackupVault -ResourceGroupName rg-bkpat -VaultName TestBkpVault -Location EastUS -StorageSetting $storageSetting
$TestBkpVault = Get-AzDataProtectionBackupVault -VaultName TestBkpVault
$TestBkpVault = Get-AzDataProtectionBackupVault -VaultName TestBkpVault -ResourceGroupName rg-bkpat
$TestBkpVault
$TestBkpVault | fl
Get-AzDataProtectionPolicyTemplate -DatasourceType AzureDisk
$policyDefn = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureDisk
$policyDefn | fn
$policyDefn
$policyDefn | fl
$policyDefn.PolicyRule | fl
$policyDefn.PolicyRule[0].Trigger | fl
$policyDefn.PolicyRule[1].Lifecycle | fl
New-AzDataProtectionBackupPolicy 
New-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name diskBkpPolicy -Policy $policyDefn
Get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "diskBkpPolicy"
$diskBkpPol = Get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "diskBkpPolicy"
$diskBkpPol
$diskBkpPol | fl
$DiskId = ""
$snapshotrg = ""
$DiskId
$snapshotrg
$instance = Initialize-AzDataProtectionBackupInstance -DatasourceType AzureDisk -DatasourceLocation $TestBkpvault.Location -PolicyId $diskBkpPol[0].Id -DatasourceId $DiskId
$instance.Property.PolicyInfo.PolicyParameter.DataStoreParametersList[0].ResourceGroupId
$instance.Property.PolicyInfo.PolicyParameter.DataStoreParametersList[0].ResourceGroupId = $snapshotrg
New-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupInstance $instance
Connect-AzAccount
$TestBkpVault = Get-AzDataProtectionBackupVault -VaultName TestBkpVault -ResourceGroupName rg-bkpat
$TestBkpVault 
$policyDefn = Get-AzDataProtectionPolicyTemplate -DatasourceType AzureDisk
$policyDefn 
get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name diskBkpPolicy -Policy $policyDefn
get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name diskBkpPolicy 
$diskBkpPol = Get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "diskBkpPolicy"
$diskBkpPol
$DiskId = ""
$snapshotrg = ""
$instance = Initialize-AzDataProtectionBackupInstance -DatasourceType AzureDisk -DatasourceLocation $TestBkpvault.Location -PolicyId $diskBkpPol[0].Id -DatasourceId $DiskId
New-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupInstance $instance
get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupInstance $instance
get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name 
$instance = Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "BackupInstanceName"
$instance = Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name 
$instance | fl
$policyDefn.PolicyRule | fl
$AllInstances = Get-AzDataProtectionBackupInstance -ResourceGroupName "testBkpVaultRG" -VaultName $TestBkpVault.Name
$instance
$instance.Name
Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "BackupInstanceName"
Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name $instance.Name
$AllInstances = Get-AzDataProtectionBackupInstance -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $AllInstances[0].Name -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "Default"
Get-AzDataProtectionJob 
Get-AzDataProtectionJob -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $AllInstances[0].Name -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "Default"
Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroupName rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup
Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroup rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup
Install-Module -Name Az.ResourceGraph -AllowClobber -Scope AllUsers
Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroup rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup
Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroupName rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup
Search-AzDataProtectionJobInAzGraph -Subscription $subId -ResourceGroup rg-bkpat -Vault $TestBkpVault.Name -DatasourceType AzureDisk -Operation OnDemandBackup
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $AllInstances[0].Name -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "Default"
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $instance.Name -ResourceGroupName rg-bkpat -SubscriptionId $subId -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "b1" -TriggerOptionRetentionTagOverride "Default"
Backup-AzDataProtectionBackupInstanceAdhoc -BackupInstanceName $AllInstances[0].Name -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -BackupRuleOptionRuleName "Default"
Get-AzDataProtectionBackupPolicy -ResourceGroupName rg-bkpat -VaultName $TestBkpVault.Name -Name "diskBkpPolicy"