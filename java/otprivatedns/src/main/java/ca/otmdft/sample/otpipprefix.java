// /* spell-checker: disable */
package ca.otmdft.sample;

//import com.microsoft.azure.arm.resources.Region;
//import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;

import com.microsoft.azure.management.network.*;
//import com.microsoft.azure.management.resources.implementation.ResourceManager;
//import com.microsoft.azure.management.resources.Provider;
//import com.microsoft.azure.management.resources.fluentcore.arm.ResourceUtils;

import java.io.File;

public class otpipprefix {
    public static void main(String[] args) {
        System.out.println("Public Prefix IP");
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));
            Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription();
            //String id1 = "/subscriptions/../resourceGroups/rg-lb1/providers/Microsoft.Network/publicIPAddresses/ips1";     
            //ResourceUtils.defaultApiVersion(id1, provider);
            //ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            PublicIPPrefix p1 = azure.publicIPPrefixes()
                                    .define("ippool1")
                                    .withRegion("eastus2")
                                    .withExistingResourceGroup("group")
                                    .withPrefixLength(8)
                                    .withPublicIPAddressVersion(IPVersion.IPV4)
                                    .create();
            System.out.println(p1.id());
            PublicIPAddress ip2 = azure.publicIPAddresses()
                                    .define("ip2")
                                    .withRegion("eastus2")
                                    .withExistingResourceGroup("group")
                                    .withStaticIP()
                                    .withSku(PublicIPSkuType.STANDARD)
                                    .create();
            System.out.println(ip2.id());
            PublicIPAddress.DefinitionStages.WithCreate ip1 = azure.publicIPAddresses()
                .define("ip1")
                .withRegion("eastus2")
                .withExistingResourceGroup("group")
                .withStaticIP()
                .withIdleTimeoutInMinutes(4);
            ip1.withSku(PublicIPSkuType.STANDARD);
            
            ip1.create();
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}
