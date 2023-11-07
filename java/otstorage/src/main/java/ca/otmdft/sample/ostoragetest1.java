package ca.otmdft.sample;

import java.io.UncheckedIOException;
import java.util.Locale;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.policy.UserAgentPolicy;
import com.azure.core.http.rest.Response;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.Region;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.identity.DefaultAzureCredential;
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
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceAsyncClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.options.BlobBeginCopyOptions;

public class ostoragetest1 {
    public static void main(final String[] args) {
        System.out.println("Azure SDK Storage");        
        String accountName = "";
        String rgName = "rg-java";
        String sContainerName = "container5";
        String sblobName = ""; 
        String filePathName = "";
        String endpoint = String.format(Locale.ROOT, "https://%s.blob.core.windows.net", accountName);
        DefaultAzureCredential credential = new DefaultAzureCredentialBuilder()
                    .tenantId("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")
                    .build();                     
        UserAgentPolicy userAgentPolicy = new UserAgentPolicy("ostoragetest1/0.0.1 azsdk-java-storage-blob/12.15.0 (Java 11; Windows_NT 10.0.22631.2506");
        BlobServiceClient blobServiceClient = new BlobServiceClientBuilder()
                .endpoint(endpoint)
                .credential(credential)
                .addPolicy(userAgentPolicy)
                .buildClient();
        BlobContainerClient blobContainerClient = blobServiceClient.getBlobContainerClient(sContainerName);        
        uploadBlobFromFile(blobContainerClient, filePathName, sblobName);
        System.out.println("Done");
    }

    public static void uploadBlobFromFile(BlobContainerClient blobContainerClient, String filePathName, String sblobName) 
    {
        BlobClient blobClient = blobContainerClient.getBlobClient(sblobName);
        try {
            blobClient.uploadFromFile(filePathName);
        } catch (UncheckedIOException ex) {
            System.err.printf("Failed to upload from file: %s%n", ex.getMessage());
        }
}
}