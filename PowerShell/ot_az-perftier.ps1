$rg = ""
$diskName = "disk1p60"
$diskSize = 8192
$pTier = "P60"
$sku = "Premium_LRS"
$region = "eastus2"

##create disk
$diskConfig = New-AzDiskConfig -SkuName $sku -Location $region -CreateOption Empty -DiskSizeGB $diskSize -Tier $pTier
New-AzDisk -DiskName $diskName -Disk $diskConfig -ResourceGroupName $rg

#review
Get-AzDisk -ResourceGroupName $rg -DiskName $diskName

#update disk 
$p2Tier = "P70"
$diskConfigUpdate = New-AzDiskUpdateConfig -Tier $p2Tier
Update-AzDisk -ResourceGroupName $rg -DiskName $diskName -DiskUpdate $diskConfigUpdate


