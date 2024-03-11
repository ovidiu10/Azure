// /* spell-checker: disable */
package io.otmigrationpip;

import java.io.File;

import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.rest.PagedIterable;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.network.fluent.models.PublicIpAddressInner;
import com.azure.resourcemanager.network.models.IpAllocationMethod;
import com.azure.resourcemanager.network.models.PublicIpAddress;
import com.azure.resourcemanager.network.models.PublicIpAddressSku;
import com.azure.resourcemanager.network.models.PublicIpAddressSkuName;

import io.otmigrationpip.model.AuthFile;

public class Main {
    public static void main(String[] args) {
        System.out.println("Migration Basic Public IP Address to Standard Public IP Address.");
        final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION2"));
        try {
            if (!credFile.exists()) {
                throw new Exception(
                        "Please provide the path to the file containing the service principal credentials by setting the environment variable.");
            }
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            AuthFile f = AuthFile.parse(credFile);
            System.out.println(f.getSubscriptionId());
            final ClientSecretCredential cred = new ClientSecretCredentialBuilder()
                    .clientId(f.getClientId())
                    .clientSecret(f.getClientSecret())
                    .tenantId(f.getTenantId())
                    .build();
            AzureResourceManager azureResourceManager = AzureResourceManager
                    .configure()
                    .withLogLevel(HttpLogDetailLevel.BODY_AND_HEADERS)
                    .authenticate(cred, profile)
                    .withSubscription(f.getSubscriptionId());
            
            PagedIterable<PublicIpAddressInner> pIpAddresses = azureResourceManager.networks()
                                            .manager().serviceClient().getPublicIpAddresses()
                                            .list();
            for (PublicIpAddressInner pIp : pIpAddresses) {
                if (pIp.sku().name().toString() == "Basic") {
                    PublicIpAddress p1 = azureResourceManager.publicIpAddresses().getById(pIp.id());                    
                    if (p1.hasAssignedNetworkInterface()) {
                        System.out.println(pIp.name() + " | Attached: true | to " + pIp.ipConfiguration().id());                        
                    } else {
                        azureResourceManager.networks().manager().serviceClient().getPublicIpAddresses()
                            .createOrUpdate(p1.resourceGroupName(), p1.name(), new PublicIpAddressInner().withLocation(p1.regionName())
                            .withSku(new PublicIpAddressSku().withName(PublicIpAddressSkuName.STANDARD))
                            .withPublicIpAllocationMethod(IpAllocationMethod.STATIC),                        
                            com.azure.core.util.Context.NONE);    
                        System.out.println(pIp.name() + " has been updated to Standard Public IP Address.");
                    }
                }
            }
        } catch (Exception e) {
            System.out.println("Error: " + e.getMessage());
        }
        System.out.println("Done!");
    }
}