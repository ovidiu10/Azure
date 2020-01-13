package ca.otmdft.sample;

import com.microsoft.azure.arm.resources.Region;
import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;

import com.microsoft.azure.management.network.v2019_09_01.PublicIPPrefixSku;
import com.microsoft.azure.management.network.v2019_09_01.PublicIPPrefixSkuName;
import com.microsoft.azure.management.network.v2019_09_01.PublicIPPrefix;
import com.microsoft.azure.management.network.v2019_09_01.implementation.NetworkManager;


import java.io.File;

public class otpublicprefix {
    public static void main(String[] args) {
        System.out.println("Public Prefix IP");
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));
            Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            NetworkManager nm = NetworkManager.authenticate(cred, azure.subscriptionId());
            PublicIPPrefixSku pippSKU = new PublicIPPrefixSku();
            pippSKU.withName(PublicIPPrefixSkuName.STANDARD);
            PublicIPPrefix ipp = nm.publicIPPrefixes().define("publicIpPrefix1")
                .withRegion(Region.US_EAST2)
                .withExistingResourceGroup("rg-an")
                .withPrefixLength(28)
                .withSku(pippSKU)
                .create();
            System.out.println(ipp.name());
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}