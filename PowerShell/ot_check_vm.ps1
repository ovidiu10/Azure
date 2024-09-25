$vmName = "<name of the VM>"
$rg = "<name of the resource group>"
$subscription = "<subscription id>"
$vmId = "/subscriptions/$subscription/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$vmName"
$MACHINE_PERFORMANCE_THRESHOLD = 1.3 # 30% more than the VM's performance because of burst and other factors like caching
$vmoProperties = [PSCustomObject]@{
    UncachedDiskIOPS = 'UncachedDiskIOPS'
    UncachedDiskBytesPerSecond = 'UncachedDiskBytesPerSecond'
}
$machinePerformance = [PSCustomObject]@{
    iops = 0
    throughputMBps = 0
}
$vm = Get-AzVM -ResourceId $vmId
$skuName = $vm.HardwareProfile.VmSize
$sku = Get-AzComputeResourceSku -Location $vm.Location | Where-Object {($_.Name -eq $skuName)}
$vmiops = ($sku.Capabilities | Where-Object { $_.Name -eq $vmoProperties.UncachedDiskIOPS }).Value 
$vmthroughputMBps = ($sku.Capabilities | Where-Object { $_.Name -eq $vmoProperties.UncachedDiskBytesPerSecond }).Value 
$vmthroughputMBps = [Math]::Round([convert]::ToInt32($vmthroughputMBps) / 1000000)
$totaldiskiops = 0
$totaldiskthroughputMBps = 0
foreach ($disk in $vm.StorageProfile.DataDisks) {
    $disksku = (Get-AzResource -ResourceId $disk.ManagedDisk.Id).Properties
    $diskiops = $disksku.diskIOPSReadWrite 
    $diskthroughputMBps = $disksku.diskMBpsReadWrite
    $totaldiskiops += $diskiops
    $totaldiskthroughputMBps += [convert]::ToInt32($diskthroughputMBps)
}
$diskos = $vm.StorageProfile.OsDisk
$diskossku = (Get-AzResource -ResourceId $diskos.ManagedDisk.Id).Properties  
$totaldiskiops += $diskossku.diskIOPSReadWrite
$totaldiskthroughputMBps += [convert]::ToInt32($diskossku.diskMBpsReadWrite)
$machinePerformance.iops = [Math]::Round([convert]::ToInt32($vmiops) * $MACHINE_PERFORMANCE_THRESHOLD)
$machinePerformance.throughputMBps = [Math]::Round([convert]::ToInt32($vmthroughputMBps) * $MACHINE_PERFORMANCE_THRESHOLD)
if ($totaldiskiops -gt $machinePerformance.iops -or $totaldiskthroughputMBps -gt $machinePerformance.throughputMBps) {
    Write-Host "VM $vmName is not performing well. " -ForegroundColor Red
    Write-Host "VM IOPS: $vmiops VM Throughput: $vmthroughputMBps All disks IOPS: $totaldiskiops All disks throughput: $totaldiskthroughputMBps" -ForegroundColor Red
}
else {
    Write-Host "VM $vmName is performing well"
    Write-Host "VM IOPS: $vmiops VM Throughput: $vmthroughputMBps All disks IOPS: $totaldiskiops All disks throughput: $totaldiskthroughputMBps"
}
