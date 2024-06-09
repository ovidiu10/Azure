// /* spell-checker: disable */
package io.otnwappgw;

import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.rest.PagedIterable;
import com.azure.core.management.AzureEnvironment;
//import com.azure.core.management.Region;
//import com.azure.core.management.SubResource;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.compute.models.Snapshot;

import java.io.File;
//import java.util.Arrays;
//import java.util.HashMap;
//import java.util.Map;

import io.otnwappgw.model.AuthFile;

public class spnapshots {
    public static void main( String[] args )
    {
        System.out.println( "OT Disk Snapshots" );
        final String rgName = "rg-work-netcore11";
        //final String appgwName = "otappgwa1";
        //final String vnetName = "vnet1";
        //final String subnetName = "SB-APPGW";
        //final String publicIPName = "pip-appgw";
        final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION2"));
        try {
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            AuthFile f = AuthFile.parse(credFile);
            final ClientSecretCredential cred = new ClientSecretCredentialBuilder()
                                    .clientId(f.getClientId())
                                    .clientSecret(f.getClientSecret())
                                    .tenantId(f.getTenantId())                                    
                                    .build();
            AzureResourceManager azureResourceManager = AzureResourceManager
                                    .configure()
                                    .withLogLevel(HttpLogDetailLevel.HEADERS)
                                    .authenticate(cred, profile)
                                    .withSubscription(f.getSubscriptionId()); 
            /*
            for (String s : azureResourceManager.resourceGroups().list().stream().map(rg -> rg.name()).toArray(String[]::new)) {
                System.out.println(s);
            }
            */
            
            System.out.println("Listing snapshots...");
            PagedIterable<Snapshot> snapshots = azureResourceManager.snapshots()
                .listByResourceGroup(rgName);
            for (Snapshot s : snapshots) {
                System.out.println(s.name());
            }
            
            /*
            System.out.println("Creating snapshot...");
            for (int i = 50; i < 498; i++) {
                Snapshot snapshot = azureResourceManager.snapshots()
                    .define("otdisk1-snapshot-" + i)
                    .withRegion(Region.EUROPE_WEST)
                    .withExistingResourceGroup(rgName)
                    .withDataFromSnapshot("/subscriptions/6f7c0ea1-f6b8-465d-bfbe-642ddeef7b82/resourceGroups/rg-work-netcore11/providers/Microsoft.Compute/snapshots/otdisk1-snapshot-0")
                    .create();
            }
            */
            /*
            for (int i = 1; i < 498; i++) {
                azureResourceManager.snapshots()
                    .deleteByResourceGroup(rgName, "otdisk1-snapshot-" + i);
            }
            */   
            System.out.println(f.getSubscriptionId());
            System.out.println("Done!");
        } catch (Exception e) {
            e.printStackTrace();
        }            
    }
}
