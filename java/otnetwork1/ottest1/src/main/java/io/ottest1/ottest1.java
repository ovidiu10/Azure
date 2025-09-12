// /* spell-checker: disable */
package io.ottest1;

import java.io.File;
import java.nio.file.Files;
//import java.time.Duration;
import java.util.List;

//import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.rest.PagedIterable;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
//import com.azure.identity.AzureCliCredential;
//import com.azure.identity.AzureCliCredentialBuilder;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
//import com.azure.identity.DefaultAzureCredentialBuilder;
//import com.azure.identity.ManagedIdentityCredential;
//import com.azure.identity.ManagedIdentityCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.network.models.NetworkSecurityGroup;
import com.azure.resourcemanager.resources.models.ResourceGroup;

import io.ottest1.model.AuthFile;

public class ottest1 
{
    public static void main( String[] args )
    {
        System.out.println( "OT Test identify MSI & others" );        
        final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION2"));
        try {
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            AuthFile f = AuthFile.parse(credFile);
            System.out.println(f.getSubscriptionId());
            //DefaultAzureCredentialBuilder
            /*
            final TokenCredential cred = new DefaultAzureCredentialBuilder()
                .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                .tenantId(f.getTenantId())
                .build();
            */
            //CLI 
            /*
            final AzureCliCredential cred = new AzureCliCredentialBuilder()
                                    .tenantId(f.getTenantId())
                                    .build();
            */
            //Secret
            final ClientSecretCredential cred = new ClientSecretCredentialBuilder()
                                    .clientId(f.getClientId())
                                    .clientSecret(f.getClientSecret())
                                    .tenantId(f.getTenantId())                                    
                                    .build();
            //MSAI - system 
            /*
            ManagedIdentityCredential cred = new ManagedIdentityCredentialBuilder()
                                    .maxRetry(10)
                                    .retryTimeout(duration -> Duration.ofSeconds(6))
                                    .build();
            */
            AzureResourceManager azureResourceManager = AzureResourceManager
                                    .configure()
                                    .withLogLevel(HttpLogDetailLevel.BODY_AND_HEADERS)
                                    .authenticate(cred, profile)
                                    .withSubscription(f.getSubscriptionId());
            System.out.println("Listing all resource groups");
            azureResourceManager.resourceGroups().list()
                .forEach(rg -> System.out.println(rg.name()));
            NetworkSecurityGroup nsg = azureResourceManager.networkSecurityGroups()
                .getByResourceGroup("rg-netcore4", "nsg-e1");
            System.out.println("NSG: " + nsg.id() + " " + nsg.listAssociatedSubnets().size());
            if (nsg.innerModel() != null && nsg.innerModel().subnets() != null) {
                nsg.innerModel().subnets().forEach(sn -> {
                    System.out.println("Subnet: " + sn.id());
                });
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

    }

    public static String readFileAsString(File credFile) throws Exception
    {
        return new String(Files.readAllBytes(credFile.toPath()));
    }
}
