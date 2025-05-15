// /* spell-checker: disable */ 
package io.otstorage12;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import com.azure.storage.blob.options.BlockBlobSimpleUploadOptions;
import com.azure.storage.blob.specialized.BlockBlobClient;
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import java.util.Base64;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;

public class App 
{
    public static void main( String[] args )
    {
        System.out.println( "Upload Storage SDK 12" );
        String accountKey = "";
        String accountName = "";
        String storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=" + accountName +
            ";AccountKey=" + accountKey +
            ";EndpointSuffix=core.windows.net";
        String localPath = "xxx.zip";
        String blobPath = "uploads/xxx.zip";
        boolean MD5enabledinHeader = true;
        try {            
            // Your code to upload and download files using Azure Storage SDK 12
            // This is a placeholder for the actual implementation
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] data = Files.readAllBytes(Paths.get(localPath));
            byte[] md5Hash = md.digest(data);
            System.out.println("MD5 Hash: " + bytesToHex(md5Hash));
            System.out.println("Base64 MD5 Hash: " + Base64.getEncoder().encodeToString(md5Hash));
            BlobServiceClient blobServiceClient = new BlobServiceClientBuilder()
                .connectionString(storageConnectionString)
                .buildClient();
            BlobContainerClient containerClient = blobServiceClient.getBlobContainerClient("mycontainer");
            containerClient.createIfNotExists();
            if (MD5enabledinHeader) {
                System.out.println("MD5 enabled in header");
                BlobHttpHeaders headers = new BlobHttpHeaders().setContentMd5(md5Hash);
                BlockBlobSimpleUploadOptions options = new BlockBlobSimpleUploadOptions(BinaryData.fromBytes(data)).setHeaders(headers);
                BlockBlobClient blockBlobClient = containerClient.getBlobClient(blobPath).getBlockBlobClient();
                blockBlobClient.uploadWithResponse(options, null, Context.NONE);
            } else {
                System.out.println("MD5 not enabled in header");
                BlobParallelUploadOptions options = new BlobParallelUploadOptions(BinaryData.fromBytes(data)).setComputeMd5(true);
                BlobClient blobClient = containerClient.getBlobClient(blobPath);
                blobClient.uploadWithResponse(options, null, Context.NONE);
            }
            System.out.println("File uploaded successfully.");
            //System.out.println("File downloaded successfully to: " + localFileName);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // Converts a byte array to a hexadecimal string
    private static String bytesToHex(byte[] bytes) {
        StringBuilder hexString = new StringBuilder();
        for (byte b : bytes) {
            String hex = Integer.toHexString(0xFF & b);
            if (hex.length() == 1) {
                hexString.append('0');
            }
            hexString.append(hex);
        }
        return hexString.toString();
    }
}
