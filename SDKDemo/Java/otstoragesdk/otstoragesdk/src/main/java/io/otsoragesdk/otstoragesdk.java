package io.otsoragesdk;

import java.util.Locale;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobContainerClientBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.models.BlobItem;

/**
 * Hello world!
 *
 */
public class otstoragesdk 
{
    public static void main( String[] args )
    {        
        final String saccount = "";
        final String stURL = "https://" + saccount + ".blob.core.windows.net/test1";
        final String sasToken = ""; 
        // Only one "?" is needed here. If the sastoken starts with "?", please removing one "?".
        BlobContainerClient blobContainerClient = new BlobContainerClientBuilder()
            .endpoint(stURL)
            .sasToken(sasToken)
            .buildClient();
        for (BlobItem blobItem : blobContainerClient.listBlobs()) {
            System.out.println("This is the blob name: " + blobItem.getName());
        }
        System.out.println( "Done" );
    }
}
