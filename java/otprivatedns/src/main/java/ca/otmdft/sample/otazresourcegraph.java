// /* spell-checker: disable */
package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
//import com.microsoft.azure.management.Azure;
//import com.microsoft.rest.LogLevel;
//import com.microsoft.azure.arm.resources.Region;
import com.microsoft.azure.management.resourcegraph.v2019_04_01.implementation.*;
import com.microsoft.azure.management.resourcegraph.v2019_04_01.*;

//import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.io.File;

public class otazresourcegraph 
{
     public static void main( String[] args )
     {
        //String rgName = "rg-java"; // Resource GroupName - should be exist 
        //String vnetName = ""; // virtual network name - should be exist  
        //String subnetName = "";
        System.out.println( "Welcome to Azure Resource Graph" );
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            //Azure azure = Azure.configure()
            //    .withLogLevel(LogLevel.NONE)
            //   .authenticate(credFile)
            //    .withDefaultSubscription();            
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);             
            ResourceGraphManager graphManager = ResourceGraphManager.authenticate(cred);
            ResourceGraphClientImpl graphClientImpl = graphManager.inner();
            List<String> subscriptions = Arrays.asList(cred.defaultSubscriptionId());
            QueryRequestOptions options = new QueryRequestOptions().withResultFormat(ResultFormat.TABLE);
            //final String sQuery = "Resources | where type =~ 'microsoft.keyvault/vaults'";
            final String sQuery = "Resources | where tags['MSFT'] == 'Logs'";
            QueryRequest query = new QueryRequest().withQuery(sQuery).withSubscriptions(subscriptions).withOptions(options);
            QueryResponseInner queryResponseInner = graphClientImpl.resources(query);
            System.out.println(queryResponseInner.data());                 
        } catch (Exception e) {;
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );        
    }
}