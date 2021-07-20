package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.ApplicationGateway;
import com.microsoft.azure.management.network.ApplicationGatewayBackend;
import com.microsoft.azure.management.network.ApplicationGatewayBackendAddress;
import com.microsoft.azure.management.network.ApplicationGatewayHttpListener;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.network.Subnet;
import com.microsoft.azure.management.network.ApplicationGateway.UpdateStages.WithBackend;

import java.io.File;
import java.nio.file.*;

public class otappgw3 {
    public static void main(final String[] args) {
        String rgName = "rg-gap"; // Resource GroupName - should be exist 
        String vnetName = "vnet-gapt1"; // virtual network name - should be exist  
        String subnetName = "SB_APPGW";
        String appGwName3 = "otappgw3";    
        System.out.println( "Welcome to Azure Application Gateway" );
        try {        
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.NONE)
                .authenticate(credFile)
                .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            ApplicationGateway appgw3 = azure.applicationGateways().getByResourceGroup(rgName, appGwName3);
            ApplicationGatewayBackend be = appgw3.backends().get("BE");
            for (ApplicationGatewayBackendAddress i1 : be.addresses()) {
                System.out.println(i1.ipAddress());
            }  
            appgw3.update().updateBackend("BE").withoutIPAddress("192.168.22.71").parent().apply();
            appgw3.refresh();
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}