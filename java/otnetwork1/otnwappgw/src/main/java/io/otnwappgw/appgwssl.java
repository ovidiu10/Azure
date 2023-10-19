package io.otnwappgw;

import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.http.rest.PagedIterable;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.Region;
import com.azure.core.management.SubResource;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.network.fluent.models.ApplicationGatewayInner;
import com.azure.resourcemanager.network.fluent.models.ApplicationGatewayIpConfigurationInner;
import com.azure.resourcemanager.network.models.ApplicationGatewayBackendAddressPool;
import com.azure.resourcemanager.network.models.ApplicationGatewayBackendHttpSettings;
import com.azure.resourcemanager.network.models.ApplicationGatewayFrontendIpConfiguration;
import com.azure.resourcemanager.network.models.ApplicationGatewayFrontendPort;
import com.azure.resourcemanager.network.models.ApplicationGatewayGlobalConfiguration;
import com.azure.resourcemanager.network.models.ApplicationGatewayProtocol;
import com.azure.resourcemanager.network.models.ApplicationGatewaySku;
import com.azure.resourcemanager.network.models.ApplicationGatewaySkuName;
import com.azure.resourcemanager.network.models.ApplicationGatewaySslCipherSuite;
import com.azure.resourcemanager.network.models.ApplicationGatewaySslPolicy;
import com.azure.resourcemanager.network.models.ApplicationGatewaySslPolicyType;
import com.azure.resourcemanager.network.models.ApplicationGatewaySslProfile;
import com.azure.resourcemanager.network.models.ApplicationGatewaySslProtocol;
import com.azure.resourcemanager.network.models.ApplicationGatewayTier;
import com.azure.resourcemanager.resources.models.ResourceGroup;

import java.io.File;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

import io.otnwappgw.model.AuthFile;

public class appgwssl 
{
    public static void main( String[] args )
    {
        System.out.println( "OT AppGW v2 custom policy SSL" );
        final String rgName = "rg-work-netcore11";
        final String appgwName = "otappgwa1";
        final String vnetName = "vnet1";
        final String subnetName = "SB-APPGW";
        final String publicIPName = "pip-appgw";
        final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION2"));
        try {
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            AuthFile f = AuthFile.parse(credFile);
            System.out.println(f.getSubscriptionId());
            final String subnetId = "/subscriptions/" + f.getSubscriptionId() + "/resourceGroups/"
                            + rgName + "/providers/Microsoft.Network/virtualNetworks/" + vnetName + "/subnets/" + subnetName;
            final String publicIPId = "/subscriptions/" + f.getSubscriptionId() + "/resourceGroups/"
                            + rgName + "/providers/Microsoft.Network/publicIPAddresses/" + publicIPName;
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
            azureResourceManager.networks().manager().serviceClient().getApplicationGateways().createOrUpdate(
                rgName,
                appgwName,
                new ApplicationGatewayInner()
                    .withLocation(Region.US_EAST.toString())   
                    .withSku(new ApplicationGatewaySku()
                        .withName(ApplicationGatewaySkuName.STANDARD_V2)
                        .withTier(ApplicationGatewayTier.STANDARD_V2)
                        .withCapacity(2)
                    )
                    .withGatewayIpConfigurations(Arrays.asList(
                        new ApplicationGatewayIpConfigurationInner()
                            .withName("appgwipc")
                            .withSubnet(new SubResource()
                                .withId(subnetId)
                    )))
                    .withFrontendIpConfigurations(Arrays.asList(
                        new ApplicationGatewayFrontendIpConfiguration()
                            .withName("appgwfip")
                            .withPublicIpAddress(new SubResource()
                                .withId(publicIPId)
                    )))
                    .withFrontendPorts(Arrays.asList(
                        new ApplicationGatewayFrontendPort().withName("appgwfp443").withPort(443),
                        new ApplicationGatewayFrontendPort().withName("appgwfp80").withPort(80)
                    ))
                    .withBackendAddressPools(
                        Arrays.asList(
                            new ApplicationGatewayBackendAddressPool()
                                .withName("BE1")
                        )
                    )
                    .withBackendHttpSettingsCollection(
                        Arrays.asList(
                            new ApplicationGatewayBackendHttpSettings()
                                .withName("p80")
                                .withPort(80),
                            new ApplicationGatewayBackendHttpSettings()
                                .withName("p443")
                                .withProtocol(ApplicationGatewayProtocol.HTTPS)
                                .withPort(443)
                        )
                    )
                    .withSslProfiles(Arrays.asList(
                        new ApplicationGatewaySslProfile()
                            .withName("appgwssl1")
                            .withSslPolicy(
                                new ApplicationGatewaySslPolicy()
                                    .withPolicyType(ApplicationGatewaySslPolicyType.CUSTOM)
                                    .withCipherSuites(Arrays.asList(
                                        ApplicationGatewaySslCipherSuite.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256))
                                    .withMinProtocolVersion(ApplicationGatewaySslProtocol.TLSV1_2)
                        )                                    
                    ))
                    .withGlobalConfiguration(
                        new ApplicationGatewayGlobalConfiguration()
                            .withEnableRequestBuffering(true)
                            .withEnableResponseBuffering(true)),
            com.azure.core.util.Context.NONE);
            System.out.println("Done!");
        } catch (Exception e) {
            e.printStackTrace();
        }            
    }

    @SuppressWarnings("unchecked")
    private static <T> Map<String, T> mapOf(Object... inputs) {
        Map<String, T> map = new HashMap<>();
        for (int i = 0; i < inputs.length; i += 2) {
            String key = (String) inputs[i];
            T value = (T) inputs[i + 1];
            map.put(key, value);
        }
        return map;
    }
}
