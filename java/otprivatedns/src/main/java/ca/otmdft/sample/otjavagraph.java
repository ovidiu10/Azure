package ca.otmdft.sample;

import java.util.Arrays;
import java.util.List;

import javax.sql.rowset.serial.SerialRef;

import com.google.gson.JsonObject;
//import com.microsoft.azure.management.batch.Application;
import com.microsoft.graph.auth.confidentialClient.*;
import com.microsoft.graph.auth.enums.NationalCloud;
import com.microsoft.graph.models.extensions.IGraphServiceClient;
import com.microsoft.graph.requests.extensions.GraphServiceClient;
import com.microsoft.graph.requests.extensions.IApplicationCollectionPage;
import com.microsoft.graph.requests.extensions.IServicePrincipalCollectionPage;
import com.microsoft.graph.models.extensions.Application;

public class otjavagraph {
    public static void main(String[] args) {
        String client = "";
        List<String> scopes = Arrays.asList("https://graph.microsoft.com/.default");
        String key = "";
        String tenant = "";
        try {
            ClientCredentialProvider  authProvider =
                new ClientCredentialProvider(client, scopes, key, tenant, NationalCloud.Global);
            IGraphServiceClient graphClient = GraphServiceClient.builder()
                    .authenticationProvider(authProvider)
                    .buildClient();
            //System.out.println(graphClient.me().buildRequest().get());
            /*
            IServicePrincipalCollectionPage servicePrincipals = graphClient.servicePrincipals()
                     .buildRequest()
                     .filter("startsWith(displayName, 'SPAppSDK2')")
                     .get();
            JsonObject serviceJson = servicePrincipals.getRawObject();
            System.out.println(serviceJson.toString());                     
            */            
            IApplicationCollectionPage app1 = graphClient.applications()
                                .buildRequest()
                                .filter("appId eq '383b370e-8c50-409b-a384-765fdfc51a00'")
                                .get();
            
                        //.filter("endDateTime/dateTime lt '2020-12-31T00:00:48.17Z'")
                        //filter("startsWith(appId, 'SPAppSDK2')")
            /*
            IApplicationCollectionPage applications = graphClient.applications()
                        .buildRequest()
                        .filter("appId eq '383b370e-8c50-409b-a384-765fdfc51a00'")
                        .get();
            */
            JsonObject serviceJson2 = app1.getRawObject();
            System.out.println("=========");
            System.out.println(serviceJson2.toString());
        } catch (Exception e) {
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}
