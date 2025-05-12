// /* spell-checker: disable */ 
package io.otstorage83;

import java.io.File;

import com.microsoft.azure.storage.AccessCondition;
import com.microsoft.azure.storage.CloudStorageAccount;
import com.microsoft.azure.storage.OperationContext;
import com.microsoft.azure.storage.blob.BlobRequestOptions;
import com.microsoft.azure.storage.blob.CloudBlobClient;
import com.microsoft.azure.storage.blob.CloudBlobContainer;
import com.microsoft.azure.storage.blob.CloudBlockBlob;

public class App 
{  
    public static void main( String[] args )
    {
        System.out.println( "Upload Storage SDK 8.3" );
        // Connection string to your Azure Storage account
        String accountKey = "";
        String accountName = "";
        String storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=" + accountName +
            ";AccountKey=" + accountKey +
            ";EndpointSuffix=core.windows.net";
        String localPath = "XXX.zip";
        String blobPath = "uploads/XXX.zip";
        String localFileName = "XXX_local.zip";
        try 
        {
            CloudStorageAccount storageAccount = CloudStorageAccount.parse(storageConnectionString);
            CloudBlobClient blobClient = storageAccount.createCloudBlobClient();
            CloudBlobContainer container = blobClient.getContainerReference("mycontainer");
            container.createIfNotExists();
            File file = new File(localPath);
            CloudBlockBlob blob = container.getBlockBlobReference(blobPath);
            BlobRequestOptions blobRequestOptions = new BlobRequestOptions();              
            blobRequestOptions.setUseTransactionalContentMD5(true);  
            blobRequestOptions.setStoreBlobContentMD5(true);                                
            blob.uploadFromFile(file.toString(), AccessCondition.generateEmptyCondition(), blobRequestOptions, null);
            System.out.println("File uploaded successfully.");
            OperationContext opContext = new OperationContext();
            blob.downloadToFile(localFileName, null, null, opContext);
            System.out.println("File downloaded successfully to: " + localFileName);
        }
        catch (Exception e) 
        {
            e.printStackTrace();
        }
    }
}
