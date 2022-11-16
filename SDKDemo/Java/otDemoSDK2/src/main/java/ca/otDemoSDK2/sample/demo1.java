package ca.otDemoSDK2.sample;

import com.microsoft.azure.Resource;
import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.resources.GenericResource;
import com.microsoft.azure.management.resources.ResourceGroup;
import com.microsoft.rest.LogLevel;

import java.io.File;
import java.util.Date;

public class demo1 
{
    public static void main(String[] args) {
        try {
            System.out.println( "Track 1 - SDK 1.41.1 " +  new Date()); 
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));
            final Azure azure = Azure.configure().withLogLevel(LogLevel.BODY_AND_HEADERS).authenticate(credFile)
                    .withDefaultSubscription();
            ResourceGroup rg = azure.resourceGroups().getByName("rg-java");
            System.out.println("Resource ID: " + rg.id()); 
        }
        catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done " +  new Date()); 
    }
}