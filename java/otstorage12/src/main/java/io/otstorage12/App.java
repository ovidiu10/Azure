// /* spell-checker: disable */ 
package io.otstorage12;

import com.azure.storage.blob.BlobClient;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.blob.models.BlobDownloadResponse;
import com.azure.storage.blob.models.BlobHttpHeaders;
import com.azure.storage.blob.models.BlobProperties;
import com.azure.storage.blob.options.BlobDownloadToFileOptions;
import com.azure.storage.blob.options.BlobParallelUploadOptions;
import com.azure.storage.blob.options.BlockBlobSimpleUploadOptions;
import com.azure.storage.blob.specialized.BlockBlobClient;
import com.azure.storage.blob.models.ParallelTransferOptions;
import com.azure.core.http.HttpHeaderName;
import com.azure.core.http.rest.Response;
import com.azure.core.util.BinaryData;
import com.azure.core.util.Context;
import java.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.MessageDigest;
import org.json.JSONObject;

public class App 
{
    public static void main( String[] args )
    {
        System.out.println( "Upload Storage SDK 12" );
        String accountKey = "";
        String accountName = "";
        String localPath = "";
        String blobPath = "";
        boolean MD5enabledinHeader = false;
        boolean realValue = true; // Set to false to test with a garbage value
        boolean downloadOnly = true; // Set to true if you want to download the file after upload
        try {
            // Your code to upload and download files using Azure Storage SDK 12
            final File credStFile = new File(System.getenv("AZURE_STORAGE1"));
            if (credStFile.exists()) {
                System.out.println("Using Azure Storage credentials from environment variable AZURE_STORAGE1");
                String content = new String(Files.readAllBytes(credStFile.toPath()));
                JSONObject config = new JSONObject(content);
                accountKey = config.getString("accountKey");
                accountName = config.getString("accountName");
                localPath = config.getString("localPath");
                blobPath = config.getString("blobPath");
            } else {
                System.out.println("Credentials file not found. Please set the AZURE_STORAGE1 environment variable.");
                return;
            }
            String storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=" + accountName +
                ";AccountKey=" + accountKey +
                ";EndpointSuffix=core.windows.net";
            BlobServiceClient blobServiceClient = new BlobServiceClientBuilder()
                .connectionString(storageConnectionString)
                .buildClient();                
            BlobContainerClient containerClient = blobServiceClient.getBlobContainerClient("mycontainer");                
            if (downloadOnly) {
                if (MD5enabledinHeader) {
                    BlockBlobClient blockBlobClient = containerClient.getBlobClient(blobPath).getBlockBlobClient();
                    OutputStream stream = new ByteArrayOutputStream();
                    BlobDownloadResponse response = blockBlobClient.downloadStreamWithResponse(stream, null,
                        null, null, false, null, Context.NONE);
                    byte[] contentMD5 = response.getDeserializedHeaders().getContentMd5();
                    if (contentMD5 != null) {
                        System.out.println("MD5 Hash from headers: " + bytesToHex(contentMD5));
                        System.out.println("Base64 MD5 Hash: " + Base64.getEncoder().encodeToString(contentMD5));
                    } else {
                        System.out.println("MD5 Hash not available in headers.");
                    }
                    try (FileOutputStream fileOutputStream = new FileOutputStream(localPath)) {
                        ((ByteArrayOutputStream) stream).writeTo(fileOutputStream);
                    } catch (IOException e) {
                        System.err.println("Error writing to file: " + e.getMessage());
                    }
                } else {
                    BlobClient blobClient = containerClient.getBlobClient(blobPath);
                    Response<BlobProperties> response = blobClient.getPropertiesWithResponse(null, null, null);
                    BlobProperties properties = response.getValue();
                    byte[] md5 = properties.getContentMd5();
                    if (md5 != null) {
                        System.out.println("MD5 Hash from properties: " + bytesToHex(md5));
                        System.out.println("Base64 MD5 Hash: " + Base64.getEncoder().encodeToString(md5));
                    } else {
                        System.out.println("MD5 Hash not available in properties.");
                    }
                    if (Files.exists(Paths.get(localPath))) {
                        Files.delete(Paths.get(localPath));
                    }
                    BlobDownloadToFileOptions options = new BlobDownloadToFileOptions(localPath).setRetrieveContentRangeMd5(true);
                    //BlobDownloadToFileOptions options = new BlobDownloadToFileOptions(localPath);
                    Response<BlobProperties> response2 = blobClient.downloadToFileWithResponse(options, null, null);
                    com.azure.core.http.HttpHeaders headers = response2.getHeaders();                    
                    BlobProperties properties2 = response2.getValue();
                    byte[] md51 = properties2.getContentMd5();
                    if (md51 != null) {
                        System.out.println("MD5 Hash from properties: " + bytesToHex(md51));
                        System.out.println("Base64 MD5 Hash: " + Base64.getEncoder().encodeToString(md51));                        
                        System.out.println("CONTENT_MD5 Hash from headers : " + headers.getValue(HttpHeaderName.fromString("x-ms-blob-content-md5")));
                    } else {
                        System.out.println("MD5 Hash not available in properties. <- BlobDownloadToFileOptions");
                        System.out.println("CONTENT_MD5 Hash from headers  : " + headers.getValue(HttpHeaderName.CONTENT_MD5));
                        System.out.println("x-ms-blob-content-md5 Hash from headers  : " + headers.getValue(HttpHeaderName.fromString("x-ms-blob-content-md5")));
                    }
                }
            } else {
                MessageDigest md = MessageDigest.getInstance("MD5");
                byte[] data = Files.readAllBytes(Paths.get(localPath));
                byte[] md5Hash = md.digest(data);
                System.out.println("MD5 Hash: " + bytesToHex(md5Hash));
                System.out.println("Base64 MD5 Hash: " + Base64.getEncoder().encodeToString(md5Hash));                                
                containerClient.createIfNotExists();
                if (MD5enabledinHeader) {
                    System.out.println("MD5 enabled in header");
                    BlobHttpHeaders headers = null;
                    if (realValue) {
                        headers = new BlobHttpHeaders().setContentMd5(md5Hash);
                    } else {
                        headers = new BlobHttpHeaders().setContentMd5(
                            MessageDigest.getInstance("MD5").digest("garbage".getBytes(StandardCharsets.UTF_8)))
                            .setContentType("text/plain");
                    }
                    BlockBlobSimpleUploadOptions options = new BlockBlobSimpleUploadOptions(BinaryData.fromBytes(data))
                        .setHeaders(headers);
                    BlockBlobClient blockBlobClient = containerClient.getBlobClient(blobPath).getBlockBlobClient();
                    blockBlobClient.uploadWithResponse(options, null, Context.NONE);
                    BlobDownloadResponse response = blockBlobClient.downloadStreamWithResponse(new ByteArrayOutputStream(), null,
                        null, null, false, null, Context.NONE);
                    byte[] contentMD5 = response.getDeserializedHeaders().getContentMd5();
                    if (contentMD5 != null) {
                        System.out.println("MD5 Hash from headers: " + bytesToHex(contentMD5));
                    } else {
                        System.out.println("MD5 Hash not available in headers.");
                    }
                } else {
                    System.out.println("MD5 not enabled in header just Compute MD5");
                    BlobParallelUploadOptions options = new BlobParallelUploadOptions(BinaryData.fromBytes(data)).setComputeMd5(true);
                    options.setParallelTransferOptions(new ParallelTransferOptions().setMaxSingleUploadSizeLong(1250000000L));                                 
                    BlobClient blobClient = containerClient.getBlobClient(blobPath);
                    blobClient.uploadWithResponse(options, null, Context.NONE);
                    Response<BlobProperties> response = blobClient.getPropertiesWithResponse(null, null, null);
                    BlobProperties properties = response.getValue();
                    byte[] md5 = properties.getContentMd5();
                    if (md5 != null) {
                        System.out.println("MD5 Hash from properties: " + bytesToHex(md5));
                    } else {
                        System.out.println("MD5 Hash not available in properties.");
                    }
                }
                System.out.println(blobPath + " File uploaded successfully.");
            }
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
