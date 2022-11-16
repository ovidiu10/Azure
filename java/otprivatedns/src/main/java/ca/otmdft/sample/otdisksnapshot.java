package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.keyvault.models.CertificateBundle;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.ApplicationGateway;
import com.microsoft.azure.management.network.ApplicationGatewaySkuName;
import com.microsoft.azure.management.network.ApplicationGatewayTier;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.network.Subnet;
import com.microsoft.azure.management.network.NetworkInterface;
import com.microsoft.azure.management.network.v2019_09_01.NetworkInterfaceNetworkInterfaceIPConfiguration;
import com.microsoft.azure.management.network.PublicIPAddress;
import com.microsoft.azure.management.network.ManagedServiceIdentityUserAssignedIdentitiesValue;
import com.microsoft.azure.management.network.ResourceIdentityType;
import com.microsoft.azure.management.network.ManagedServiceIdentity;
import com.microsoft.azure.management.keyvault.Vault;
import com.microsoft.azure.management.keyvault.Secret;
import com.microsoft.azure.management.keyvault.implementation.KeyVaultManager;
import com.microsoft.azure.management.msi.Identity;
import com.microsoft.azure.management.msi.implementation.MSIManager;
import com.microsoft.azure.management.resources.ResourceGroup;
import com.microsoft.azure.management.compute.Disk;
import com.microsoft.azure.management.compute.DiskSkuTypes;
import com.microsoft.azure.management.compute.KnownLinuxVirtualMachineImage;
import com.microsoft.azure.management.compute.VirtualMachine;
import com.microsoft.azure.management.compute.Snapshot.DefinitionStages.WithCreate;
import com.microsoft.azure.management.compute.Snapshot;
import com.microsoft.azure.SubResource;
import com.microsoft.azure.arm.model.Creatable;
import com.microsoft.azure.arm.resources.Region;
import com.microsoft.azure.management.resources.fluentcore.arm.AvailabilityZoneId;
import com.microsoft.azure.management.resources.fluentcore.utils.SdkContext;
import com.microsoft.rest.serializer.JacksonAdapter;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.io.IOException;
import java.io.File;
import java.util.Arrays;
import java.util.HashMap;
import com.google.gson.JsonObject;
import com.google.common.io.Files;
import java.nio.charset.Charset;

public class otdisksnapshot {
    public static void main(String[] args) {
        String rgName = "rg-java"; // Resource GroupName - should be exist
        String vnetName = "vnet-gapt1"; // virtual network name - should be exist
        String subnetName = "SB_APPGW";
        String pipgw = "pip_appgw";
        String appGwName = "appgw1";
        String kvName = "otkvusw2";
        System.out.println("Welcome Java V2");
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION3"));
            Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            ResourceGroup rg = azure.resourceGroups().getByName(rgName);
            System.out.println(rg.id());
            // NetworkInterface nic = azure.networkInterfaces().getByResourceGroup(rgName,
            // "vm1testeth0");
            /*
             * VirtualMachine vmLinux = azure.virtualMachines().define("vmLinux1")
             * .withRegion(Region.US_EAST2.name()) .withExistingResourceGroup(rgName)
             * .withExistingPrimaryNetworkInterface(nic)
             * .withPopularLinuxImage(KnownLinuxVirtualMachineImage.UBUNTU_SERVER_16_04_LTS)
             * .withRootUsername("admin22") .withRootPassword("notes#123456")
             * .withSize("STANDARD_B1s") .create(); System.out.println(vmLinux.id());
             */
            /*
             * Disk sourceDisk = azure.disks().getByResourceGroup(rgName,
             * "vmLinuxWestUs2Az2_OsDisk_1_da92b29ee36d4a088f9012be42db8515");
             * 
             * 
             * Snapshot oSnapshot = azure.snapshots().define("disk-clone-test2")
             * .withRegion(Region.US_WEST2.name()) .withExistingResourceGroup(rgName)
             * .withLinuxFromDisk(sourceDisk.id()) .create();
             * 
             * Snapshot oSnapshot = azure.snapshots().getByResourceGroup(rgName,
             * "disk-clone-test2"); System.out.println(oSnapshot.id());
             * Disk.DefinitionStages.WithCreate newOSDisk = azure.disks()
             * .define("clone-disk-os3") .withRegion(Region.US_WEST2.name())
             * .withExistingResourceGroup(rgName) .withLinuxFromSnapshot(oSnapshot.id())
             * .withSizeInGB(30) .withSku(DiskSkuTypes.); if
             * (!sourceDisk.availabilityZones().isEmpty()) {
             * newOSDisk.withAvailabilityZone(AvailabilityZoneId.ZONE_1); }
             * //System.out.println(newOSDisk); newOSDisk.create();
             */            
            Disk sourceDisk1 = azure.disks().getByResourceGroup(rgName, "ottest1_OsDisk_1_3b215a2a10114a419bc681e7691d8b37");
            Snapshot oSnapshot1 = azure.snapshots().define("disk1-clone-test3")
             .withRegion(Region.US_WEST_CENTRAL.name())
             .withExistingResourceGroup(rgName)
             .withLinuxFromDisk(sourceDisk1.id())
             .create();
            /*
            final WithCreate sp2 = azure.snapshots().define("aaa")
                                        .withRegion(Region.US_EAST2.name())
                                        .withExistingResourceGroup(rgName)
                                        .withDataFromDisk(sourceDisk1.id()); 
            sp2.create();                                            
            Disk.DefinitionStages.WithCreate mikeDisk = azure.disks()
                                    .define("clone-disk12")
                                    .withRegion(Region.US_WEST2.name())
                                    .withExistingResourceGroup(rgName)
                                    .withLinuxFromDisk(sourceDisk1.id())
                                    .withSizeInGB(30)
                                    .withSku(DiskSkuTypes.STANDARD_LRS);
            if (!sourceDisk1.availabilityZones().isEmpty()) {     
                mikeDisk.withAvailabilityZone(AvailabilityZoneId.ZONE_2);
            }            
            mikeDisk.create();  
            */
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );        
    }
}