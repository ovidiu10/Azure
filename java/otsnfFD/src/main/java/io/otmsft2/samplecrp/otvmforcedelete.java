package io.otmsft2.samplecrp;

import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.compute.KnownLinuxVirtualMachineImage;
import com.microsoft.azure.management.compute.VirtualMachine;
import com.microsoft.azure.management.network.NetworkInterface;
import com.microsoft.azure.management.resources.GenericResource;
import com.microsoft.rest.LogLevel;

import org.joda.time.DateTime;
import org.joda.time.Seconds;

import java.io.File;
import java.time.LocalDateTime;
import java.util.Date;

import javax.swing.text.StyledEditorKit;

import static java.time.temporal.ChronoUnit.SECONDS;

public class otvmforcedelete
{
    public static void main( String[] args )
    {
        //!!!Assumption already exit 3 Network Interface "nicvmNameX" where X = 1:3 
        //!!!Interface 1 - VIP Basic; Interface 2 - VIP Standard; Interface 3 - No VIP
        //!!!nicNvmName - all no VIP 
        String rgName = "rg-java3"; // Resource GroupName - should be exist 
        String region = "eastus2euap"; // Region in Azure;
        final String reg = "east"; 
        final String nicName = "nicvmName";
        try
        {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));
            final Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription();                     
            if (reg == "east")
            {
                rgName = "rg-java3";
                region = "eastus2euap";
            } else {            
                rgName = "rg-java2";
                region = "centraluseuap";
            }                  
            System.out.println("Start Testing " + region + " " + new Date());
            for (int i = 1; i < 4; i++) {
                String vmName = "vmName" + i;
                System.out.println("VM Name: " + vmName);                
                NetworkInterface nic = azure.networkInterfaces().getByResourceGroup(rgName, nicName + i);                                         
                VirtualMachine vmLinux = azure.virtualMachines().define(vmName)
                                            .withRegion(region).withExistingResourceGroup(rgName)
                                            .withExistingPrimaryNetworkInterface(nic)
                                            .withPopularLinuxImage(KnownLinuxVirtualMachineImage.UBUNTU_SERVER_16_04_LTS)
                                            .withRootUsername("AzureAdmin")
                                            .withRootPassword("12NewPA$$w0rd!")
                                            .withTag("tag1", "value1")
                                            .withSize("STANDARD_B1s").create(); 
                System.out.println(vmLinux.id());                         
                String osDiskid = vmLinux.osDiskId();
                VirtualMachine vmLinux_d = azure.virtualMachines().getByResourceGroup(rgName, vmName);
                LocalDateTime dataStart = LocalDateTime.now();
                System.out.println("Timer task started at: "+new Date());
                GenericResource genericResource = azure.genericResources().getById(vmLinux_d.id());
                azure.genericResources().delete(
                    genericResource.resourceGroupName(),
                    genericResource.resourceProviderNamespace(),
                    genericResource.parentResourcePath(),
                    genericResource.resourceType(),
                    genericResource.name(),
                    "2020-06-01",
                    true
                );
                LocalDateTime dataEnd = LocalDateTime.now();
                long diff = SECONDS.between(dataStart, dataEnd);
                System.out.println("Timer task finished at: "+new Date());
                System.out.println(diff + "s");                            
                System.out.println("\n");
                System.out.println("Timer task started Delete OS at: "+new Date());
                GenericResource genericResource_os = azure.genericResources().getById(osDiskid);
                azure.genericResources().delete(
                    genericResource_os.resourceGroupName(),
                    genericResource_os.resourceProviderNamespace(), 
                    genericResource_os.parentResourcePath(),
                    genericResource_os.resourceType(),
                    genericResource_os.name(),
                    "2020-06-30",
                    true
                );
                System.out.println("Timer task finished Delete OS at: "+new Date()); 
                System.out.println("\n");
            }
        }
        catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done " +  new Date()); 
    }
    

}
