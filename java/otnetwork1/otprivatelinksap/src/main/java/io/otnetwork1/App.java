// /* spell-checker: disable */
package io.otnetwork1;

import java.util.List;
//import java.util.stream.Collector;
//import java.util.stream.Collectors;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
//import com.azure.core.http.rest.PagedIterable;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
//import com.azure.core.util.Context;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
//import com.azure.resourcemanager.network.fluent.models.PrivateEndpointConnectionInner;
import com.azure.resourcemanager.network.fluent.models.PrivateEndpointInner;
//import com.azure.resourcemanager.network.fluent.models.PrivateLinkServiceInner;
//import com.azure.resourcemanager.network.models.PrivateLinkServiceConnectionState;
//import com.azure.resourcemanager.network.models.PrivateEndpoint.PrivateLinkServiceConnection;
//import com.azure.resourcemanager.resources.models.ResourceGroup;

public class App 
{
    public static void main( String[] args )
    {
        final String sId = "42581afb-e04b-43d7-91a7-8faca6703fe7";
        System.out.println( "PLS Network Approve" );
        try {
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            final TokenCredential credential = new DefaultAzureCredentialBuilder()
                            .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                            .build();
            AzureResourceManager azureResourceManager = AzureResourceManager
                            .configure()
                            .withLogLevel(HttpLogDetailLevel.NONE)
                            .authenticate(credential, profile)
                            .withSubscription(sId);
            System.out.println("Selected subscription: " + azureResourceManager.subscriptionId());
            /*
            List<Object> privateLinkResources  = azureResourceManager
                .networks()
                .manager()
                .serviceClient()
                .getPrivateLinkServices()
                .list().stream().collect(Collectors.toList());
            */
            for (PrivateEndpointInner pE : azureResourceManager
                .networks()
                .manager()
                .serviceClient()
                .getPrivateEndpoints()
                .listByResourceGroup("rg-netcore2")) {
                    List<com.azure.resourcemanager.network.models.PrivateLinkServiceConnection> p1 = pE.privateLinkServiceConnections();
                    for (com.azure.resourcemanager.network.models.PrivateLinkServiceConnection p : p1 ) {
                        System.out.println(p.name());
                    }
                }
            /*
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
            */
            System.out.println("Done");
        }
        catch (Exception err) {
            System.out.println(err.getMessage());
            err.printStackTrace();
        }
    }
}
