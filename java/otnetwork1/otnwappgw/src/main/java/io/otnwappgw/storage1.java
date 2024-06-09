// /* spell-checker: disable */
package io.otnwappgw;

import java.io.File;

import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.Region;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
//import com.azure.resourcemanager.storage.models.Sku;
//import com.azure.resourcemanager.storage.models.SkuName;

import io.otnwappgw.model.AuthFile;

public class storage1 {
    public static void main( String[] args )
    {    
        final String rgName = "rg-java";
        final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION4"));
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
                System.out.println(f.getSubscriptionId());
                azureResourceManager.storageAccounts().define("otstorage12299")
                    .withRegion(Region.CANADA_EAST)
                    .withExistingResourceGroup(rgName)                    
                    .create();                                        
                System.out.println("Done!");
        } catch (Exception e) {
                e.printStackTrace();
        }
    }     
}
