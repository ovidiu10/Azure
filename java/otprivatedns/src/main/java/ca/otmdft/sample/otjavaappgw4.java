// /* spell-checker: disable */
package ca.otmdft.sample;

import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.network.ApplicationGateway;
//import com.microsoft.azure.management.network.ApplicationGatewayFirewallExclusion;
//import com.microsoft.azure.management.network.ApplicationGatewayFirewallMode;
//import com.microsoft.azure.management.network.ApplicationGatewaySkuName;
//import com.microsoft.azure.management.network.ApplicationGatewayTier;
//import com.microsoft.azure.management.network.ApplicationGatewayWebApplicationFirewallConfiguration;
//import com.microsoft.azure.management.resources.fluentcore.arm.Region;
import com.microsoft.rest.LogLevel;

import java.io.File;
//import java.lang.reflect.Array;
//import java.util.Arrays;


public class otjavaappgw4 {
    public static void main( String[] args )
    {
        String rgName = "rg-java"; // Resource GroupName - should be exist 
        //String vnetName = ""; // virtual network name - should be exist  
        //String subnetName = "";
        String appGwName = "otappgw1";
        System.out.println("Welcome to Azure Test");
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));
            final Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription(); 
            /*
            ApplicationGateway applicationGateway = azure.applicationGateways().define(appGwName)
                    .withRegion(Region.US_EAST2)
                    .withExistingResourceGroup(rgName)
                    .defineRequestRoutingRule("rule1")
                        .fromPublicFrontend()
                        .fromFrontendHttpPort(80)
                        .toBackendHttpPort(8080)
                        .toBackendIPAddress("192.168.229.10")
                        .attach()
                    .defineBackend("BE")
                        .withIPAddress("192.168.229.11")
                        .attach()
                    .withTier(ApplicationGatewayTier.WAF_V2)
                    .withSize(ApplicationGatewaySkuName.WAF_V2)
                    .withExistingPublicIPAddress("/subscriptions/../resourceGroups/rg-java/providers/Microsoft.Network/publicIPAddresses/IP3S")
                    .withWebApplicationFirewall(new ApplicationGatewayWebApplicationFirewallConfiguration()
                        .withFirewallMode(ApplicationGatewayFirewallMode.PREVENTION)
                        .withRuleSetType("OWASP")
                        .withEnabled(true)
                        .withRuleSetVersion("3.0")
                        .withExclusions(Arrays.asList(new ApplicationGatewayFirewallExclusion().withSelector("Referer")
                            .withMatchVariable("Equals").withMatchVariable("RequestHeaderNames"))))
                    .create();
            */                             
            //final String applicationGatewayBackend = "BE";   
            //System.out.println("Updating AppGateway Backend for Attach to: BE" );
            System.out.println("Refreshing the application gateway");
            ApplicationGateway appGateway = azure.applicationGateways().getByResourceGroup(rgName, appGwName);                     
            final ApplicationGateway refreshedAppGateway = appGateway.refresh();            
            refreshedAppGateway.update()
                    .updateBackend("BE")
                    .withIPAddress("192.168.229.11")
                    .parent()
                    .apply();
            System.out.println("Attaching dispatcher to LB/AppGateway: " + appGateway.name() + " is successfully finished.");
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }

}
