package com.azure.resourcemanager.compute.samples;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.Region;
import com.azure.core.management.exception.ManagementException;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.compute.ComputeManager;
import com.azure.resourcemanager.compute.fluent.models.SnapshotInner;
import com.azure.resourcemanager.compute.models.CachingTypes;
import com.azure.resourcemanager.compute.models.CreationData;
import com.azure.resourcemanager.compute.models.Disk;
import com.azure.resourcemanager.compute.models.DiskCreateOption;
import com.azure.resourcemanager.compute.models.KnownLinuxVirtualMachineImage;
import com.azure.resourcemanager.compute.models.OperatingSystemTypes;
import com.azure.resourcemanager.compute.models.VirtualMachine;
import com.azure.resourcemanager.compute.models.VirtualMachineDataDisk;
import com.azure.resourcemanager.compute.models.VirtualMachineSizeTypes;
import com.azure.resourcemanager.resources.fluentcore.utils.ResourceManagerUtils;
import com.azure.resourcemanager.samples.Utils;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;


public final class CloneVMrun {
    
    public static boolean runSample1(AzureResourceManager azureResourceManager, ComputeManager computeManager) {
        final String linuxVMName1 = Utils.randomResourceName(azureResourceManager, "VM1", 15);
        final String managedOSSnapshotName = Utils.randomResourceName(azureResourceManager, "ss-os-", 15);
        final String rgName = Utils.randomResourceName(azureResourceManager, "rgCOMV", 15);
        final String publicIpDnsLabel = Utils.randomResourceName(azureResourceManager, "pip", 15);
        final String userName = "azureadmin";
        final String sshPublicKey = Utils.sshPublicKey();
        final Region region = Region.US_EAST;

        try {
            System.out.println("Creating a un-managed Linux VM");
            VirtualMachine linuxVM = azureResourceManager.virtualMachines().define(linuxVMName1)
                    .withRegion(region)
                    .withNewResourceGroup(rgName)
                    .withNewPrimaryNetwork("10.0.0.0/28")
                    .withPrimaryPrivateIPAddressDynamic()
                    .withNewPrimaryPublicIPAddress(publicIpDnsLabel)
                    .withPopularLinuxImage(KnownLinuxVirtualMachineImage.UBUNTU_SERVER_16_04_LTS)
                    .withRootUsername(userName)
                    .withSsh(sshPublicKey)
                    .withSize(VirtualMachineSizeTypes.fromString("Standard_D2a_v4"))
                    .create();

            System.out.println("Created a Linux VM with managed OS and data disks: " + linuxVM.id());
            Utils.print(linuxVM);

            return true;
        } finally {
            try {
                //System.out.println("Deleting Resource Group: " + rgName);
                //azureResourceManager.resourceGroups().beginDeleteByName(rgName);            
            } catch (NullPointerException npe) {
                System.out.println("Did not create any resources in Azure. No clean up is necessary");
            } catch (Exception g) {
                g.printStackTrace();
            }
        }

    }
    
    public static boolean runSample2(AzureResourceManager azureResourceManager, ComputeManager computeManager) {
        final String linuxVMName1 = "vm198945384f8";
        final String managedOSSnapshotName = Utils.randomResourceName(azureResourceManager, "ss-os-", 15);
        final String rgName = "rgcomv3d377214";
        final String linuxVMName2 = Utils.randomResourceName(azureResourceManager, "VM2", 15);
        final String managedNewOSDiskName = Utils.randomResourceName(azureResourceManager, "ds-os-nw-", 15);
        final Region region = Region.US_EAST;
        final String rgNameNew = Utils.randomResourceName(azureResourceManager, "rgCOMV", 15);             
        final Region regionNew = Region.US_WEST;

        try {
            VirtualMachine linuxVM = azureResourceManager.virtualMachines().getByResourceGroup(rgName, linuxVMName1);
            Disk osDisk = azureResourceManager.disks().getById(linuxVM.osDiskId());
    
            System.out.printf("Creating managed snapshot from the managed disk (holding specialized OS): %s %n", osDisk.id());
    
            SnapshotInner osSnapshot = computeManager.snapshots()
                .define(managedOSSnapshotName)
                .withRegion(region)
                .withExistingResourceGroup(rgName)
                .withLinuxFromDisk(osDisk)
                .withIncremental(true) // incremental is mandatory for snapshot to be copied across region
                .create()
                .innerModel();
    
            azureResourceManager.resourceGroups().define(rgNameNew).withRegion(regionNew).create();
    
            System.out.printf("Copying managed snapshot %s to a new region.%n", osDisk.id());
            
            SnapshotInner snapshotRequestNewRegion = new SnapshotInner()
                .withLocation(regionNew.toString())
                .withIncremental(true) // incremental is mandatory for snapshot to be copied across region
                .withCreationData(new CreationData());
            
            snapshotRequestNewRegion
                .creationData()
                .withCreateOption(DiskCreateOption.COPY_START)
                .withSourceResourceId(osSnapshot.id());
    
            SnapshotInner osSnapshotNewRegion = computeManager.serviceClient().getSnapshots().createOrUpdate(rgNameNew, managedOSSnapshotName + "new", snapshotRequestNewRegion);
            osSnapshotNewRegion = waitForCrossRegionCompletion(computeManager, rgNameNew, osSnapshotNewRegion);
            System.out.println("Created managed snapshot holding OS: " + osSnapshotNewRegion.id());
    
            System.out.println(String.format("Creating managed disk from the snapshot holding OS: %s ", osSnapshotNewRegion.id()));
    
            Disk newOSDisk = azureResourceManager.disks().define(managedNewOSDiskName)
                    .withRegion(regionNew)
                    .withExistingResourceGroup(rgNameNew)
                    .withLinuxFromSnapshot(osSnapshotNewRegion.id())
                    .withSizeInGB(100)
                    .create();
    
            System.out.println("Created managed disk holding OS: " + osDisk.id());
            System.out.println("Created managed disk new OS: " + newOSDisk.id());
    
            VirtualMachine linuxVM2 = azureResourceManager.virtualMachines().define(linuxVMName2)
                    .withRegion(regionNew)
                    .withExistingResourceGroup(rgNameNew)
                    .withNewPrimaryNetwork("10.0.0.0/28")
                    .withPrimaryPrivateIPAddressDynamic()
                    .withoutPrimaryPublicIPAddress()
                    .withSpecializedOSDisk(newOSDisk, OperatingSystemTypes.LINUX)
                    .withSize(VirtualMachineSizeTypes.fromString("Standard_D2a_v4"))
                    .create();

            Utils.print(linuxVM2);

            return true;
        } finally {
            try {
                //System.out.println("Deleting Resource Group: " + rgName);
                //azureResourceManager.resourceGroups().beginDeleteByName(rgName);            
            } catch (NullPointerException npe) {
                System.out.println("Did not create any resources in Azure. No clean up is necessary");
            } catch (Exception g) {
                g.printStackTrace();
            }
        }        
    }

    public static boolean deleteAll(AzureResourceManager azureResourceManager)
    {        
        final String rgName = "rgcomv3d377214";
        final String rgNameNew = "rgcomvb3455153";
        try {            
            System.out.println("Deleting Resource Group: " + rgName);
            azureResourceManager.resourceGroups().beginDeleteByName(rgName);
            System.out.println("Deleted Resource Group: " + rgName);
            System.out.println("Deleting Resource Group: " + rgNameNew);
            azureResourceManager.resourceGroups().beginDeleteByName(rgNameNew);
            System.out.println("Deleted Resource Group: " + rgNameNew);
            return true;
        } finally { 
            try {
                //empty
            } catch (NullPointerException npe) {
                System.out.println("Did not create any resources in Azure. No clean up is necessary");
            } catch (Exception g) {
                g.printStackTrace();
            }
        }
    }

    private static SnapshotInner waitForCrossRegionCompletion(ComputeManager computeManager, String rgName, SnapshotInner osSnapshot) {
        return computeManager.serviceClient().getSnapshots().getByResourceGroupAsync(rgName, osSnapshot.name())
            .flatMap(snapshotInner -> {
                if (snapshotInner.copyCompletionError() != null) {
                    return Mono.error(new ManagementException(snapshotInner.copyCompletionError().errorMessage(), null));
                }
                if (snapshotInner.completionPercent() == null || snapshotInner.completionPercent() != 100) {
                   System.out.printf("Wait for cross-region snapshot copy complete. Complete percent: %s.%n", snapshotInner.completionPercent());
                    return Mono.empty();
                }
                return Mono.just(snapshotInner);
            }).repeatWhenEmpty(longFlux ->
                longFlux
                    .flatMap(
                        index -> Mono.delay(ResourceManagerUtils.InternalRuntimeContext.getDelayDuration(Duration.ofSeconds(30)))))
            .block();
    }

    public static void main(String[] args) {
        try {

            //=============================================================
            // Authenticate

            final AzureProfile profile = new AzureProfile("", "", AzureEnvironment.AZURE);
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

            //runSample2(azureResourceManager, computeManager);
            deleteAll(azureResourceManager);
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
    }

    private CloneVMrun() {
    }

}