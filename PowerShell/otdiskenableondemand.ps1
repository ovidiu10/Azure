$rg = ""
$diskName = ""
$region = "eastus2"
$diskConfig = New-AzDiskConfig -Location $region -CreateOption Empty -DiskSizeGB 1024 -SkuName Premium_LRS -BurstingEnabled $true
$dataDisk = New-AzDisk -ResourceGroupName $rg -DiskName $diskName -Disk $diskConfig
