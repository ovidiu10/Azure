package io.otsoragesdk;

import java.util.Locale;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobContainerClientBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;

/**
 * Hello world!
 *
 */
public class otstoragesdk 
{
    public static void main( String[] args )
    {
        System.out.println( "Hello World!" );
        final String stURL = "https://otstoragesdk.blob.core.windows.net/test1";
        final String sasToken = "sp=racwdl&st=2021-07-20T13:52:48Z&se=2021-07-23T21:52:48Z&spr=https&sv=2020-08-04&sr=c&sig=Xk3HxU2zlDt0V4Q4PrZ98mi48brAN%2BTs0fP8IcmhDOs%3D"; 
        // Only one "?" is needed here. If the sastoken starts with "?", please removing one "?".
        BlobContainerClient blobContainerClient = new BlobContainerClientBuilder()
            .endpoint(stURL)
            .sasToken(sasToken)
            .buildClient();
        BlobClient blobClient = blobContainerClient.getBlobClient("hp2.png");
        blobClient.uploadFromFile("C:\\Users\\OvidiuTimpanariu\\Pictures\\hp2.png");
        System.out.println( "Done" );
    }
}
