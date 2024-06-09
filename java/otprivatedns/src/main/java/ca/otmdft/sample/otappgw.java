// /* spell-checker: disable */
package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
//import com.microsoft.azure.keyvault.models.CertificateBundle;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.ApplicationGateway;
import com.microsoft.azure.management.network.ApplicationGatewaySkuName;
import com.microsoft.azure.management.network.ApplicationGatewayTier;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.network.Subnet;
import com.microsoft.azure.management.network.PublicIPAddress;
import com.microsoft.azure.management.network.ManagedServiceIdentityUserAssignedIdentitiesValue;
import com.microsoft.azure.management.network.ResourceIdentityType;
import com.microsoft.azure.management.network.ManagedServiceIdentity;
import com.microsoft.azure.management.keyvault.Vault;
import com.microsoft.azure.management.keyvault.Secret;
import com.microsoft.azure.management.keyvault.implementation.KeyVaultManager;
import com.microsoft.azure.management.msi.Identity;
import com.microsoft.azure.management.msi.implementation.MSIManager;
//import com.microsoft.azure.management.resources.ResourceGroup;
//import com.microsoft.azure.SubResource;
import com.microsoft.azure.arm.resources.Region;
import com.microsoft.azure.management.resources.fluentcore.utils.SdkContext;
import com.microsoft.rest.serializer.JacksonAdapter;

//import java.util.ArrayList;
//import java.util.List;
import java.util.Map;
//import java.io.IOException;
import java.io.File;
//import java.util.Arrays;
import java.util.HashMap;
import com.google.gson.JsonObject;
import com.google.common.io.Files;
import java.nio.charset.Charset;

public class otappgw 
{
    String certificateName = "www.ods-sitex.io2020.cer";
    public static void main( String[] args )
    {
        String rgName = "rg-gap"; // Resource GroupName - should be exist 
        String vnetName = "vnet-gapt1"; // virtual network name - should be exist  
        String subnetName = "SB_APPGW";
        String pipgw = "pip_appgw"; 
        String appGwName = "appgw1";
        //String kvName = "otkvusw2";
        System.out.println( "Welcome to Azure Application Gateway v2" );
        try {
            otappgw oaw = new otappgw();
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.NONE)
                .authenticate(credFile)
                .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            Network vnet = azure.networks().getByResourceGroup(rgName, vnetName); // get virtual network 
            Subnet subnetVnet = vnet.subnets().get(subnetName);
            PublicIPAddress pipAppGw = azure.publicIPAddresses().getByResourceGroup(rgName, pipgw);
            String identityName = SdkContext.randomResourceName("id", 10);
            MSIManager msiManager = MSIManager
                .authenticate(cred, cred.defaultSubscriptionId());
            Identity identity = msiManager.identities()
               .define(identityName)
               .withRegion(Region.US_WEST2.name())
               .withExistingResourceGroup(rgName)
               .create();
            ManagedServiceIdentity serviceIdentity = createManagedServiceIdentityFromIdentity(identity);
            KeyVaultManager keyVaultManager = KeyVaultManager.authenticate(cred, cred.defaultSubscriptionId());
            Secret secret1 = oaw.createKeyVaultSecret(cred.clientId(), identity.principalId(), keyVaultManager, rgName);;
            
            ApplicationGateway gw1 = azure.applicationGateways().define(appGwName)
                        .withRegion(Region.US_WEST2.name())
                        .withExistingResourceGroup(rgName)
                        .defineRequestRoutingRule("rule1")
                            .fromPublicFrontend()
                            .fromFrontendHttpsPort(443)
                            .withSslCertificate("ssl1")
                            .toBackendHttpPort(80)
                            .toBackendIPAddress("192.168.22.4")
                            .toBackendIPAddress("192.168.22.5")
                            .attach()
                        .withIdentity(serviceIdentity)
                        .defineSslCertificate("ssl1")
                            .withKeyVaultSecretId(secret1.id())
                            .attach()
                        .withExistingSubnet(subnetVnet)
                        .withSize(ApplicationGatewaySkuName.STANDARD_V2)
                        .withTier(ApplicationGatewayTier.STANDARD_V2)                 
                        .withExistingPublicIPAddress(pipAppGw)
                        .create();
                    
            //for (Map.Entry<String, Subnet> entry : vnet.subnets().entrySet()) {
            //    String subnetName = entry.getKey();
            //    Subnet subnet = entry.getValue();
            //}
            System.out.println(gw1.id());
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }

    private static ManagedServiceIdentity createManagedServiceIdentityFromIdentity(Identity identity) throws Exception{
        JsonObject userAssignedIdentitiesValueObject = new JsonObject();
        userAssignedIdentitiesValueObject.addProperty("principalId", identity.principalId());
        userAssignedIdentitiesValueObject.addProperty("clientId", identity.clientId());
        ManagedServiceIdentityUserAssignedIdentitiesValue userAssignedIdentitiesValue =
            new JacksonAdapter().deserialize(userAssignedIdentitiesValueObject.toString(), 
                ManagedServiceIdentityUserAssignedIdentitiesValue.class);
        Map<String, ManagedServiceIdentityUserAssignedIdentitiesValue> userAssignedIdentities = 
            new HashMap<String,ManagedServiceIdentityUserAssignedIdentitiesValue>();
        userAssignedIdentities.put(identity.id(), userAssignedIdentitiesValue);
        ManagedServiceIdentity serviceIdentity = new ManagedServiceIdentity();
        serviceIdentity.withType(ResourceIdentityType.USER_ASSIGNED);
        serviceIdentity.withUserAssignedIdentities(userAssignedIdentities);
        return serviceIdentity;
    }

    private Secret createKeyVaultSecret(String servicePrincipal, String identityPrincipal, KeyVaultManager keyVaultManager, String rgName) throws Exception {
        String vaultName = SdkContext.randomResourceName("vlt", 10);
        String secretName = SdkContext.randomResourceName("srt", 10);
        String secretValue = Files.readFirstLine(new File(getClass().getClassLoader()
            .getResource(certificateName).getFile()), 
            Charset.defaultCharset());
        Vault vault = keyVaultManager.vaults()
                .define(vaultName)
                .withRegion(Region.US_WEST2.name())
                .withExistingResourceGroup(rgName)
                .defineAccessPolicy()
                    .forServicePrincipal(servicePrincipal)
                    .allowSecretAllPermissions()
                    .attach()
                .defineAccessPolicy()
                    .forObjectId(identityPrincipal)
                    .allowSecretAllPermissions()
                    .attach()
                .withAccessFromAzureServices()
                .withDeploymentEnabled()
                // Important!! Only soft delete enabled key vault can be assigned to application gateway
                // See also: https://github.com/MicrosoftDocs/azure-docs/issues/34382
                .withSoftDeleteEnabled()
                .create();
        return vault.secrets()
                .define(secretName)
                .withValue(secretValue)
                .create();
    }

}