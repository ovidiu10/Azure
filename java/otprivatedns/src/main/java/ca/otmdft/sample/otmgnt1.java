package ca.otmdft.sample;

import java.io.File;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.compute.KnownLinuxVirtualMachineImage;
import com.microsoft.azure.management.compute.PowerState;
import com.microsoft.azure.management.compute.VirtualMachine;
import com.microsoft.azure.management.compute.VirtualMachineSizeTypes;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.network.v2019_09_01.NetworkInterface;
import com.microsoft.azure.management.storage.SkuName;
import com.microsoft.azure.management.storage.StorageAccount;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.arm.resources.Region;

public class otmgnt1 {

    public static void main( String[] args )
    {
        String rgName = "rg-bkparchive1"; // Resource GroupName - should be exist 
        String vnetName = "vnet-wcus";
        String subnetName = "SB_192.168.229.0_25";
        System.out.println( "Azure SDK Track1 Management" );
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.BODY_AND_HEADERS)
                .authenticate(credFile)
                .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            Network virtualNetwork1 = azure.networks().getByResourceGroup(rgName, vnetName);            
            NetworkInterface networkInterface = null;
            VirtualMachine vm1 = azure.virtualMachines().getByResourceGroup(rgName, "otvm6wcus");
            //PowerState pw = vm1.powerState();  
            /*                   
            StorageAccount storageAccount = azure.storageAccounts().define("")
                .withRegion(Region.US_WEST_CENTRAL.name())
                .withExistingResourceGroup(rgName)
                .create();
            VirtualMachine vm2 = azure.virtualMachines().define("otvm62wcus")
                .withRegion(Region.US_WEST_CENTRAL.name())
                .withExistingResourceGroup(rgName)
                .withExistingPrimaryNetwork(virtualNetwork1)
                .withSubnet(subnetName)
                .withPrimaryPrivateIPAddressDynamic()
                .withoutPrimaryPublicIPAddress()
                .withPopularLinuxImage(KnownLinuxVirtualMachineImage.UBUNTU_SERVER_18_04_LTS)
                .withRootUsername("admin22")
                .withRootPassword("test#123469")
                .withBootDiagnostics(storageAccount)
                //.withBootDiagnosticsOnManagedStorageAccount()
                .withSize(VirtualMachineSizeTypes.STANDARD_B1S)
                .create();                
            */
             

            //vm1.update().withTag("adobe:ms:manage-elb-links:detached-from:", "attach").apply();
            //vm1.update().withoutTag("adobe:ms:manage-elb-links:detached-from:").apply();
            /*StorageAccount st = azure.storageAccounts().define("otst11")
                .withRegion(Region.US_WEST_CENTRAL.name())
                .withExistingResourceGroup(rgName)
                .withGeneralPurposeAccountKindV2()
                .create();
            */
            //System.out.println(pw.toString());
        }
        catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();    
        }
        System.out.println( "Done" );
    }
}
