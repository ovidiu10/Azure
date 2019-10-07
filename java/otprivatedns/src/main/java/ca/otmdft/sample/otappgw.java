package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.keyvault.KeyVaultClient;
import com.microsoft.azure.keyvault.models.CertificateBundle;
import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.appservice.ManagedServiceIdentity;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.ApplicationGateway;
import com.microsoft.azure.management.network.ApplicationGatewaySkuName;
import com.microsoft.azure.management.network.ApplicationGatewayTier;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.network.Subnet;
import com.microsoft.azure.management.network.PublicIPAddress;
import com.microsoft.azure.management.keyvault.Vault;
import com.microsoft.azure.management.msi.Identity;
import com.microsoft.azure.management.resources.ResourceGroup;
import com.microsoft.azure.SubResource;
import com.microsoft.azure.arm.resources.Region;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.io.IOException;
import java.io.File;

public class otappgw 
{
    public static void main( String[] args )
    {
        String rgName = "rg-gap"; // Resource GroupName - should be exist 
        String vnetName = "vnet-gapt1"; // virtual network name - should be exist  
        String subnetName = "SB_APPGW";
        String pipgw = "pip_appgw"; 
        String appGwName = "appgw1";
        String kvName = "otkvusw2";
        String certificateName = "cert1";
        System.out.println( "Welcome to Azure Application Gateway v2" );
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.NONE)
                .authenticate(credFile)
                .withDefaultSubscription();
            //ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            Network vnet = azure.networks().getByResourceGroup(rgName, vnetName); // get virtual network 
            Subnet subnetVnet = vnet.subnets().get(subnetName);
            PublicIPAddress pipAppGw = azure.publicIPAddresses().getById(pipgw);
            Vault kv = azure.vaults().getByResourceGroup(rgName, kvName);
            CertificateBundle certB = kv.client().getCertificate(kv.vaultUri(), certificateName);
            certB.certificateIdentifier();
            Identity identity = azure.identities().getById("");
            //Region.US_WEST2
            //ManagedServiceIdentity identity = azure.identities().;
            ApplicationGateway gw1 = azure.applicationGateways().define(appGwName)
                        .withRegion(Region.US_WEST2.name())
                        .withExistingResourceGroup(rgName)
                        .defineRequestRoutingRule("HTTP1")
                            .fromPublicFrontend()
                            .fromFrontendHttpsPort(443)
                            .withSslCertificateFromKeyVaultSecretId(certB.id())
                            .toBackendHttpPort(80)
                            .toBackendIPAddress("192.168.22.4")
                            .toBackendIPAddress("192.168.22.5")
                            .attach()
                        .withIdentity(identity)
                        .withExistingSubnet(subnetVnet)
                        .withSize(ApplicationGatewaySkuName.STANDARD_V2)
                        .withTier(ApplicationGatewayTier.STANDARD_V2)                 
                        .withExistingPublicIPAddress(pipAppGw)
                        .create();
                    
            //for (Map.Entry<String, Subnet> entry : vnet.subnets().entrySet()) {
            //    String subnetName = entry.getKey();
            //    Subnet subnet = entry.getValue();
            //}
            //System.out.println(subnetVnet.addressPrefix());
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}