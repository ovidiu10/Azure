package ca.otmdft.sample;

import java.util.Locale;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.rest.Response;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.Region;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.compute.models.KnownLinuxVirtualMachineImage;
import com.azure.resourcemanager.compute.models.VirtualMachine;
import com.azure.resourcemanager.compute.models.VirtualMachineSizeTypes;
import com.azure.resourcemanager.network.models.Network;
import com.azure.resourcemanager.storage.models.CheckNameAvailabilityResult;
import com.azure.resourcemanager.storage.models.StorageAccount;
import com.azure.storage.blob.BlobAsyncClient;
import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobClientBuilder;
import com.azure.storage.blob.BlobContainerAsyncClient;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.options.BlobBeginCopyOptions;

public class ostoragetest1 {
    public static void main(final String[] args) {
        System.out.println("Azure SDK Storage");
        //System.out.println("ostoragetest1");
        String accountName = "ostoragetest11";
        String rgName = "rg-java";
        String sContainerName = "container5";
        String sblobName = "AzureIaaSWS.zip"; 
        //String rgName = "rg-bkparchive1"; // Resource GroupName - should be exist 
        //String vnetName = "vnet-wcus";
        //String subnetName = "SB_192.168.229.0_25";
        String endpoint = String.format(Locale.ROOT, "https://%s.blob.core.windows.net", accountName);
        final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
        final TokenCredential credential = new DefaultAzureCredentialBuilder()
            .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
            .build();             
        AzureResourceManager azureResourceManager = AzureResourceManager
            .configure()
            .withLogLevel(HttpLogDetailLevel.BODY_AND_HEADERS)
            .authenticate(credential, profile)
            .withSubscription("");
        String encryptionScope = "OTMS1";
        /*
        if (azureResourceManager.storageAccounts().checkNameAvailability(accountName).isAvailable()) {                               
            StorageAccount storageAccount = azureResourceManager.storageAccounts().define(accountName)
                .withRegion(Region.US_WEST)
                .withExistingResourceGroup(rgName)
                .withGeneralPurposeAccountKindV2()
                .create();
        }
        */
        /*
        BlobServiceAsyncClient blobServiceClient = new BlobServiceClientBuilder()
            .endpoint(endpoint)
            .credential(new DefaultAzureCredentialBuilder().build())            
            .encryptionScope(encryptionScope)
            .buildAsyncClient();
        //System.out.println(storagClient);
        BlobContainerAsyncClient blobContainerAsyncClient = blobServiceClient.getBlobContainerAsyncClient(sContainerName);
        BlobAsyncClient blobAsyncClient = blobContainerAsyncClient.getBlobAsyncClient(sblobName);
        BlobBeginCopyOptions beginCopyOptions = new BlobBeginCopyOptions(sourceUrl);
        blobAsyncClient.beginCopy(beginCopyOptions);
        */
        /*
        Network virtualNetwork1 = azureResourceManager.networks().getByResourceGroup(rgName, vnetName);
        VirtualMachine vm2 = azureResourceManager.virtualMachines().define("otvm61wcus")
                .withRegion(Region.US_WEST_CENTRAL.name())
                .withExistingResourceGroup(rgName)
                .withExistingPrimaryNetwork(virtualNetwork1)
                .withSubnet(subnetName)
                .withPrimaryPrivateIPAddressDynamic()
                .withoutPrimaryPublicIPAddress()
                .withPopularLinuxImage(KnownLinuxVirtualMachineImage.UBUNTU_SERVER_18_04_LTS)
                .withRootUsername("admin22")
                .withRootPassword("test#123469")
                //.withBootDiagnostics()                
                .withBootDiagnosticsOnManagedStorageAccount()
                .withSize(VirtualMachineSizeTypes.STANDARD_B1S)
                .create();
        */
        /*
        VirtualMachine vm1 = azureResourceManager.virtualMachines().getByResourceGroup(rgName, "otvm6wcus");
        vm1.update().withTag("adobe:ms:manage-elb-links:detached-from:", "attach").apply();
        */
        System.out.println("Done");
    }
}