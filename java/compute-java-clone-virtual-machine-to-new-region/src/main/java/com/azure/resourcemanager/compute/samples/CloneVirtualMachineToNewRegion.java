// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

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

/**
 * Azure Compute sample for managing virtual machines -
 *  - Create an managed virtual machine from PIR image with data disks
 *  - Create incremental snapshot from the virtual machine's OS and data disks
 *  - Copy incremental snapshots to the new region
 *  - Create managed disks from the snapshots of the new region
 *  - Create virtual machine by attaching the managed disks
 */
public final class CloneVirtualMachineToNewRegion {
    /**
     * Main function which runs the actual sample.
     * @param azureResourceManager instance of the azure client
     * @param computeManager
     * @return true if sample runs successfully
     */
    public static boolean runSample(AzureResourceManager azureResourceManager, ComputeManager computeManager) {
        final String linuxVMName1 = Utils.randomResourceName(azureResourceManager, "VM1", 15);
        final String linuxVMName2 = Utils.randomResourceName(azureResourceManager, "VM2", 15);
        final String managedOSSnapshotName = Utils.randomResourceName(azureResourceManager, "ss-os-", 15);
        final String managedDataDiskSnapshotPrefix = Utils.randomResourceName(azureResourceManager, "ss-data-", 15);
        final String managedNewOSDiskName = Utils.randomResourceName(azureResourceManager, "ds-os-nw-", 15);
        final String managedNewDataDiskNamePrefix = Utils.randomResourceName(azureResourceManager, "ds-data-nw-", 15);

        final String rgName = Utils.randomResourceName(azureResourceManager, "rgCOMV", 15);
        final String rgNameNew = Utils.randomResourceName(azureResourceManager, "rgCOMV", 15);
        final String publicIpDnsLabel = Utils.randomResourceName(azureResourceManager, "pip", 15);
        final String userName = "azureadmin";
        final String sshPublicKey = Utils.sshPublicKey();
        final Region region = Region.US_WEST;
        final Region regionNew = Region.US_EAST;

        final String apacheInstallScript = "https://raw.githubusercontent.com/Azure/azure-sdk-for-java/main/sdk/resourcemanager/azure-resourcemanager-samples/src/main/resources/install_apache.sh";
        final String apacheInstallCommand = "bash install_apache.sh";
        List<String> apacheInstallScriptUris = new ArrayList<>();
        apacheInstallScriptUris.add(apacheInstallScript);

        try {
            //=============================================================
            // Create a Linux VM using a PIR image with managed OS and data disks and customize virtual
            // machine using custom script extension

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
                    .withNewDataDisk(100)
                    .withNewDataDisk(100, 1, CachingTypes.READ_WRITE)
                    .defineNewExtension("CustomScriptForLinux")
                        .withPublisher("Microsoft.OSTCExtensions")
                        .withType("CustomScriptForLinux")
                        .withVersion("1.4")
                        .withMinorVersionAutoUpgrade()
                        .withPublicSetting("fileUris", apacheInstallScriptUris)
                        .withPublicSetting("commandToExecute", apacheInstallCommand)
                        .attach()
                    .withSize(VirtualMachineSizeTypes.fromString("Standard_D2a_v4"))
                    .create();

            System.out.println("Created a Linux VM with managed OS and data disks: " + linuxVM.id());
            Utils.print(linuxVM);

            // Gets the specialized managed OS and Data disks of the virtual machine
            //
            Disk osDisk = azureResourceManager.disks().getById(linuxVM.osDiskId());
            List<Disk> dataDisks = new ArrayList<>();
            for (VirtualMachineDataDisk disk : linuxVM.dataDisks().values()) {
                Disk dataDisk = azureResourceManager.disks().getById(disk.id());
                dataDisks.add(dataDisk);
            }

            //=============================================================
            // Delete the virtual machine
            System.out.println("Deallocating VM: " + linuxVM.id());

            linuxVM.deallocate();

            System.out.println("Deallocated the VM");

            //=============================================================
            // Create incremental Snapshot from the OS managed disk

            System.out.printf("Creating managed snapshot from the managed disk (holding specialized OS): %s %n", osDisk.id());

            SnapshotInner osSnapshot = computeManager.snapshots()
                .define(managedOSSnapshotName)
                .withRegion(region)
                .withExistingResourceGroup(rgName)
                .withLinuxFromDisk(osDisk)
                .withIncremental(true) // incremental is mandatory for snapshot to be copied across region
                .create()
                .innerModel();

            //=============================================================
            // Copy snapshots to the new region (current handwritten code doesn't support COPY_START, so use serviceClient() instead)

            // Create resource group in the new region
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
            // Delete snapshot from old region
            azureResourceManager.snapshots().deleteById(osSnapshot.id());

            System.out.println("Created managed snapshot holding OS: " + osSnapshotNewRegion.id());
            // ResourceManagerUtils.print(osSnapshot); TODO

            //=============================================================
            // Create Managed snapshot from the Data managed disks

            List<SnapshotInner> dataSnapshots = new ArrayList<>();
            int i = 0;
            for (Disk dataDisk : dataDisks) {
                System.out.printf("Creating managed snapshot from the managed disk (holding data): %s %n", dataDisk.id());

                SnapshotInner dataSnapshot = computeManager.snapshots()
                    .define(managedDataDiskSnapshotPrefix + "-" + i)
                    .withRegion(region)
                    .withExistingResourceGroup(rgName)
                    .withDataFromDisk(dataDisk)
                    .withIncremental(true) // incremental is mandatory for snapshot to be copied across region
                    .create()
                    .innerModel();

                //=============================================================
                // Copy snapshots to the new region (current handwritten code doesn't support COPY_START, so use serviceClient() instead)

                System.out.printf("Copying managed snapshot %s to a new region %n", dataSnapshot.id());

                SnapshotInner dataSnapshotRequestNewRegion = new SnapshotInner()
                    .withLocation(regionNew.toString())
                    .withIncremental(true) // incremental is mandatory for snapshot to be copied across region
                    .withCreationData(new CreationData());
                dataSnapshotRequestNewRegion
                    .creationData()
                    .withCreateOption(DiskCreateOption.COPY_START)
                    .withSourceResourceId(dataSnapshot.id());

                SnapshotInner dataSnapshotNewRegion = computeManager.serviceClient().getSnapshots().createOrUpdate(rgNameNew, managedDataDiskSnapshotPrefix + "new" + "-" + i, dataSnapshotRequestNewRegion);
                dataSnapshotNewRegion = waitForCrossRegionCompletion(computeManager, rgNameNew, dataSnapshotNewRegion);
                // Delete snapshot from old region
                azureResourceManager.snapshots().deleteById(dataSnapshot.id());

                dataSnapshots.add(dataSnapshotNewRegion);

                System.out.println("Created managed snapshot holding data: " + dataSnapshotNewRegion.id());
                // ResourceManagerUtils.print(dataDisk); TODO
                i++;
            }

            //=============================================================
            // Create Managed disk from the specialized OS snapshot

            System.out.println(String.format("Creating managed disk from the snapshot holding OS: %s ", osSnapshotNewRegion.id()));

            Disk newOSDisk = azureResourceManager.disks().define(managedNewOSDiskName)
                    .withRegion(regionNew)
                    .withExistingResourceGroup(rgNameNew)
                    .withLinuxFromSnapshot(osSnapshotNewRegion.id())
                    .withSizeInGB(100)
                    .create();

            System.out.println("Created managed disk holding OS: " + osDisk.id());
            // ResourceManagerUtils.print(osDisk); TODO

            //=============================================================
            // Create Managed disks from the data snapshots

            List<Disk> newDataDisks = new ArrayList<>();
            i = 0;
            for (SnapshotInner dataSnapshot : dataSnapshots) {
                System.out.println(String.format("Creating managed disk from the Data snapshot: %s ", dataSnapshot.id()));

                Disk dataDisk = azureResourceManager.disks().define(managedNewDataDiskNamePrefix + "-" + i)
                        .withRegion(regionNew)
                        .withExistingResourceGroup(rgNameNew)
                        .withData()
                        .fromSnapshot(dataSnapshot.id())
                        .create();
                newDataDisks.add(dataDisk);

                System.out.println("Created managed disk holding data: " + dataDisk.id());
                // ResourceManagerUtils.print(dataDisk); TODO
                i++;
            }

            //
            //=============================================================
            // Create a Linux VM by attaching the managed disks

            System.out.println("Creating a Linux VM using specialized OS and data disks");

            VirtualMachine linuxVM2 = azureResourceManager.virtualMachines().define(linuxVMName2)
                    .withRegion(regionNew)
                    .withExistingResourceGroup(rgNameNew)
                    .withNewPrimaryNetwork("10.0.0.0/28")
                    .withPrimaryPrivateIPAddressDynamic()
                    .withoutPrimaryPublicIPAddress()
                    .withSpecializedOSDisk(newOSDisk, OperatingSystemTypes.LINUX)
                    .withExistingDataDisk(newDataDisks.get(0))
                    .withExistingDataDisk(newDataDisks.get(1), 1, CachingTypes.READ_WRITE)
                    .withSize(VirtualMachineSizeTypes.fromString("Standard_D2a_v4"))
                    .create();

            Utils.print(linuxVM2);

            //=============================================================
            //
            System.out.println("Deleting OS snapshot - " + osSnapshotNewRegion.id());

            azureResourceManager.snapshots().deleteById(osSnapshotNewRegion.id());

            System.out.println("Deleted OS snapshot");

            for (SnapshotInner dataSnapshot : dataSnapshots) {
                System.out.println("Deleting data snapshot - " + dataSnapshot.id());

                azureResourceManager.snapshots().deleteById(dataSnapshot.id());

                System.out.println("Deleted data snapshot");
            }

            System.out.println("De-allocating the virtual machine - " + linuxVM2.id());

            linuxVM2.deallocate();
            return true;
        } finally {
            try {
                System.out.println("Deleting Resource Group: " + rgName);
                azureResourceManager.resourceGroups().beginDeleteByName(rgName);
                System.out.println("Deleted Resource Group: " + rgName);
                System.out.println("Deleting Resource Group: " + rgNameNew);
                azureResourceManager.resourceGroups().beginDeleteByName(rgNameNew);
                System.out.println("Deleted Resource Group: " + rgNameNew);
            } catch (NullPointerException npe) {
                System.out.println("Did not create any resources in Azure. No clean up is necessary");
            } catch (Exception g) {
                g.printStackTrace();
            }
        }
    }

    /*
    This could take significantly long, since it's doing a complete copy of the snapshot content.
     */
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

    /**
     * Main entry point.
     * @param args the parameters
     */
    public static void main(String[] args) {
        try {

            //=============================================================
            // Authenticate

            final AzureProfile profile = new AzureProfile("72f988bf-86f1-41af-91ab-2d7cd011db47", "42581afb-e04b-43d7-91a7-8faca6703fe7", AzureEnvironment.AZURE);
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

            runSample(azureResourceManager, computeManager);
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
    }

    private CloneVirtualMachineToNewRegion() {
    }
}
