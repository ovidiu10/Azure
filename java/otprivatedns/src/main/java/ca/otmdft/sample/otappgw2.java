// /* spell-checker: disable */
package ca.otmdft.sample;

//import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.ApplicationGateway;
//import com.microsoft.azure.management.network.Network;
//import com.microsoft.azure.management.network.Subnet;
import com.microsoft.azure.management.network.ApplicationGateway.DefinitionStages.WithRequestRoutingRuleOrCreate;
//import com.microsoft.azure.management.network.ManagedServiceIdentityUserAssignedIdentitiesValue;
//import com.microsoft.azure.management.network.ResourceIdentityType;
//import com.microsoft.azure.management.network.ManagedServiceIdentity;
//import com.microsoft.azure.management.msi.Identity;
//import com.microsoft.azure.management.resources.ResourceGroup;
//import com.microsoft.azure.SubResource;
import com.microsoft.azure.arm.resources.Region;
//import com.microsoft.azure.management.resources.fluentcore.utils.SdkContext;
//import com.microsoft.rest.serializer.JacksonAdapter;

//import java.util.ArrayList;
//import java.util.List;
//import java.util.Map;
//import java.io.IOException;
import java.io.File;
//import java.util.Arrays;
//import java.util.HashMap;
//import com.google.gson.JsonObject;

import java.nio.file.*;

public class otappgw2 
{
    //String certificateName = "www.ods-sitex.io2020.cer";
    String certificateName = "www.ods-sitex.io2020.pfx";
    public static void main( String[] args )
    {
        String rgName = "rg-gap"; // Resource GroupName - should be exist 
        //String vnetName = "vnet-gapt1"; // virtual network name - should be exist  
        //String subnetName = "SB_APPGW";
        String appGwName2 = "appgw4";
        System.out.println( "Welcome to Azure Application Gateway v2 / V1" );
        try {
            otappgw2 oaw = new otappgw2();
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.NONE)
                .authenticate(credFile)
                .withDefaultSubscription();
            //ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            //Network vnet = azure.networks().getByResourceGroup(rgName, vnetName); // get virtual network 
            //Subnet subnetVnet = vnet.subnets().get(subnetName);
            //get file
            File pfxFile = oaw.file1();
            byte[] content = Files.readAllBytes(pfxFile.toPath()); 
            String password = "*****"; 
            ApplicationGateway.DefinitionStages.WithRequestRoutingRuleOrCreate builder = (WithRequestRoutingRuleOrCreate)azure.applicationGateways()
                .define(appGwName2)
                .withRegion(Region.US_WEST2.name())
                .withExistingResourceGroup(rgName);
            builder = builder.defineRequestRoutingRule("rule1")
                .fromPublicFrontend()
                .fromFrontendHttpPort(80)
                .toBackendHttpPort(8080)
                .toBackendIPAddress("192.168.22.4")
                .attach();
            builder = builder.defineRequestRoutingRule("rule2")
                .fromPublicFrontend()
                .fromFrontendHttpsPort(443)
                .withSslCertificate("ssl1")
                .toBackendHttpPort(8080)
                .toBackendIPAddress("192.168.22.4")
                .attach();
            builder.defineSslCertificate("ssl1")
                .withPfxFromBytes(content)
                //.withPfxFromFile(pfxFile)
                .withPfxPassword(password)
                .attach();
            builder.withNewPublicIPAddress();
            ApplicationGateway gw2 = builder.create();
            
            System.out.println(gw2.id());
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }

    private File file1()
    {
        File f1 = new File(getClass().getClassLoader().getResource(certificateName).getFile());
        return f1;
    }

 
}