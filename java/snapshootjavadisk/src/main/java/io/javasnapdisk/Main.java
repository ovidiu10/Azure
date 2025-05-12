package io.javasnapdisk;

import java.util.HashMap;
import java.util.Map;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.compute.ComputeManager;
import com.azure.resourcemanager.compute.models.CachingTypes;
import com.azure.resourcemanager.compute.models.Disk;
import com.azure.resourcemanager.compute.models.OperatingSystemTypes;
import com.azure.resourcemanager.compute.models.Snapshot;
import com.azure.resourcemanager.compute.models.VirtualMachine;
import com.azure.resourcemanager.compute.models.VirtualMachineDataDisk;
import com.azure.resourcemanager.network.models.Network;
import com.azure.resourcemanager.network.models.Subnet;

public class Main {

    public static boolean runsample2(AzureResourceManager azureResourceManager) {
        VirtualMachine linuxVM = azureResourceManager.virtualMachines().getByResourceGroup("rg-java", "otvmubuntu1");
        Disk osDisk = azureResourceManager.disks().getById(linuxVM.osDiskId());
        //List<Disk> dataDisks = new ArrayList<>();
        Map<String, Disk> l1 = new HashMap<>();
        for (VirtualMachineDataDisk disk : linuxVM.dataDisks().values()) {
            Disk dataDisk = azureResourceManager.disks().getById(disk.id());
            CachingTypes cachingType = disk.cachingType();
            //dataDisks.add(dataDisk);
            l1.put(cachingType.toString(), dataDisk);
        }
        System.out.println("OS Disk: " + osDisk.name() + " cache type: " + linuxVM.osDiskCachingType());
        System.out.println("Data Disks: ");
        for (Map.Entry<String, Disk> entry : l1.entrySet()) {
            System.out.println(" - " + entry.getValue().name() + " cache type: " + entry.getKey());
        }
        Disk sourceDisk1 = azureResourceManager.disks().getByResourceGroup("rg-java", l1.entrySet().iterator().next().getValue().name());
        System.out.println("Source Disk: " + sourceDisk1.id());
        Snapshot oSnapshot = azureResourceManager.snapshots()
            .define("disk1-clone1-test")
            .withRegion("eastus")
            .withExistingResourceGroup("rg-java")
            .withDataFromDisk(sourceDisk1.id())
            .create();
        System.out.println("Snapshot: " + oSnapshot.id());
        return true;
    }

    public static boolean runSample3(AzureResourceManager azureResourceManager) {
        Network network = azureResourceManager.networks().listByResourceGroup("rg-java").iterator().next();
        Subnet subnet = network.subnets().values().iterator().next();
        System.out.println("Network: " + network.id());
        System.out.println("Subnet: " + subnet.id());
        Snapshot ossnDisk = azureResourceManager.snapshots().getByResourceGroup("rg-java", "osdisk-clone1");
        Snapshot datasnDisk1 = azureResourceManager.snapshots().getByResourceGroup("rg-java", "disk1-clone1-test");
        Disk newOSDisk = azureResourceManager.disks()
            .define("otvmubuntu2-osdisk")
            .withRegion("eastus")
            .withExistingResourceGroup("rg-java")
            .withLinuxFromSnapshot(ossnDisk.id())
            .withSizeInGB(256)
            .create();
        Disk newDataDisk = azureResourceManager.disks()
            .define("otvmubuntu2-data-disk1")
            .withRegion("eastus")
            .withExistingResourceGroup("rg-java")
            .withLinuxFromSnapshot(datasnDisk1.id())
            .withSizeInGB(8192)
            .create();
        
        VirtualMachine linuxVMd1 = azureResourceManager.virtualMachines().define("otvmubuntu1_clone1")
            .withRegion("eastus")
            .withExistingResourceGroup("rg-java")
            .withExistingPrimaryNetwork(network)
            .withSubnet(subnet.name())
            .withPrimaryPrivateIPAddressDynamic()
            .withoutPrimaryPublicIPAddress()
            .withSpecializedOSDisk(newOSDisk, OperatingSystemTypes.LINUX)
            .withExistingDataDisk(newDataDisk, 2, (newDataDisk.sizeInGB() > 4095) ? CachingTypes.NONE : CachingTypes.READ_WRITE) // <-- because is over 4TB CachingType is NONE
            .withOSDiskCaching(CachingTypes.READ_WRITE)
            .withSize("Standard_D4s_v3")
            .create();
        System.out.println("VM: " + linuxVMd1.id());
        return true;
    }
    
    public static void main(String[] args) {
        try {
            final AzureProfile profile = new AzureProfile("3daa70ca-2390-4c3a-8d40-86f93d5d5b10", "8451578e-4ec2-47cb-aa28-45d9209f3a9c", AzureEnvironment.AZURE);
            final TokenCredential credential = new DefaultAzureCredentialBuilder()
                .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                .build();

            AzureResourceManager azureResourceManager = AzureResourceManager
                .configure()
                .withLogLevel(HttpLogDetailLevel.BASIC)
                .authenticate(credential, profile)
                .withDefaultSubscription();
            
            System.out.println("Selected subscription: " + azureResourceManager.subscriptionId());

            ComputeManager computeManager = ComputeManager
                .configure()
                .withLogLevel(HttpLogDetailLevel.BASIC)
                .authenticate(credential, profile);                

            System.out.println(computeManager.subscriptionId());
            // Print selected subscription
            System.out.println("Selected subscription: " + azureResourceManager.subscriptionId());
            //azureResourceManager.resourceGroups().list().forEach(resourceGroup -> {
            //    System.out.println("Resource Group: " + resourceGroup.name());
            //});
            
            // Run the sample
            //runsample2(azureResourceManager);
            runSample3(azureResourceManager);
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
}