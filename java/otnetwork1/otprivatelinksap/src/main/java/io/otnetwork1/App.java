package io.otnetwork1;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.core.util.Context;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.network.fluent.models.PrivateEndpointConnectionInner;
import com.azure.resourcemanager.network.models.PrivateLinkServiceConnectionState;

/**
 * Hello world!
 *
 */
public class App 
{
    public static void main( String[] args )
    {
        System.out.println( "PLS Network Approve" );
        try {
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            final TokenCredential credential = new DefaultAzureCredentialBuilder()
                            .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                            .build();
            AzureResourceManager azureResourceManager = AzureResourceManager
                            .configure()
                            .withLogLevel(HttpLogDetailLevel.BASIC)
                            .authenticate(credential, profile)
                            .withDefaultSubscription();
            System.out.println("Selected subscription: " + azureResourceManager.subscriptionId());
            azureResourceManager
                            .networks()
                            .manager()
                            .serviceClient()
                            .getPrivateLinkServices()
                            .updatePrivateEndpointConnectionWithResponse(
                                "rg", 
                                "testPls", 
                                "testPlePeConnection", 
                                new PrivateEndpointConnectionInner()
                                    .withName("testPlePeConnection")
                                    .withPrivateLinkServiceConnectionState(
                                        new PrivateLinkServiceConnectionState()
                                            .withStatus("Approved")
                                            .withDescription("approved it for some reason.")),  
                                Context.NONE);
            System.out.println("Done");
        }
        catch (Exception err) {
            System.out.println(err.getMessage());
            err.printStackTrace();
        }
    }
}
