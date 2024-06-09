// /* spell-checker: disable */
package io.otmsai1;

import java.time.Duration;

import com.azure.identity.ManagedIdentityCredential;
import com.azure.identity.ManagedIdentityCredentialBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;

public class otmsai1 
{
    public static void main( String[] args )
    {
        System.out.println( "Connection using managed identity to storage endpoint" );
        final String endpoint = args[0].toString();
        ManagedIdentityCredential managedIdentityCredential = new ManagedIdentityCredentialBuilder()
                                                                      .maxRetry(10)
                                                                      .retryTimeout(duration -> Duration.ofSeconds(6))
                                                                      .build();
        BlobServiceClient newServiceClient = new BlobServiceClientBuilder()
                                                    .credential(managedIdentityCredential).endpoint(endpoint).buildClient();
        newServiceClient.listBlobContainers().forEach(t -> { System.out.println(t.getName()); });
        System.out.println("Done");
    }
}
