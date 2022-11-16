package ca.otDemoSDK3;

import java.util.Arrays;
import java.util.Date;
import java.util.List;

import com.azure.identity.ClientSecretCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.microsoft.graph.authentication.TokenCredentialAuthProvider;
import com.microsoft.graph.models.Application;
import com.microsoft.graph.models.User;
import com.microsoft.graph.requests.ApplicationCollectionPage;
import com.microsoft.graph.requests.GraphServiceClient;

public class otgraph0 {
    public static void main(String[] args) {      
        try {
            String clientId = "";
            String clientSecret = "";
            String tenant = "";
            final ClientSecretCredential clientSecretCredential = new ClientSecretCredentialBuilder()
                .clientId(clientId)
                .clientSecret(clientSecret)
                .tenantId(tenant)
                .build();

            List<String> scopes = Arrays.asList("https://graph.microsoft.com/.default");
            final TokenCredentialAuthProvider tokenCredentialAuthProvider = new 
                TokenCredentialAuthProvider(scopes, clientSecretCredential);

            final GraphServiceClient graphClient =
                GraphServiceClient
                    .builder()
                    .authenticationProvider(tokenCredentialAuthProvider)
                    .buildClient();
            final ApplicationCollectionPage app1 = graphClient.applications()
                    .buildRequest().filter("appId eq '383b370e-8c50-409b-a384-765fdfc51a00'").get();
            List<Application> apps = app1.getCurrentPage();
            for (Application application : apps) {
                System.out.println(application.displayName);   
            }            
            
            //final User me = graphClient.me().buildRequest().get();
        }
        catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done " +  new Date());
    }    
}
