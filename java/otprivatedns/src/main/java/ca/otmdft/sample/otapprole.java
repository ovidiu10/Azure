package ca.otmdft.sample;

import com.microsoft.azure.Resource;
import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.azure.management.graphrbac.BuiltInRole;
import com.microsoft.azure.management.graphrbac.RoleAssignment;
import com.microsoft.azure.management.graphrbac.ServicePrincipal;
import com.microsoft.azure.management.resources.ResourceGroup;
import com.microsoft.azure.management.resources.fluentcore.utils.SdkContext;
import com.microsoft.rest.LogLevel;

import java.util.Arrays;
import java.util.List;
import java.io.File;

public class otapprole {
    public static void main(final String[] args) {
        final String rgName = "rg-java"; // Resource GroupName - should be exist
        final String vnetName = ""; // virtual network name - should be exist
        final String subnetName = "";
        final String raName2 = SdkContext.randomUuid();
        System.out.println("Welcome to Azure Test");
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION2"));
            final Azure azure = Azure.configure().withLogLevel(LogLevel.NONE).authenticate(credFile)
                    .withDefaultSubscription();
            final ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            final Azure.Authenticated authenticated = azure.authenticate(cred);
            ServicePrincipal sp = authenticated.servicePrincipals().getByName("OTAppR1");
            String scope = "subscriptions/6f7c0ea1-f6b8-465d-bfbe-642ddeef7b82/resourceGroups/rg-java"; //The scope is usually the ID of a subscription, a resource group, a resource, etc.
            //ResourceGroup g = azure.resourceGroups().getByName(rgName);
			RoleAssignment roleAssignment = authenticated.roleAssignments()
                                                .define(raName2).forServicePrincipal(sp)
                                                .withBuiltInRole(BuiltInRole.CONTRIBUTOR)
                                                .withScope(scope)
                                                .create();
            System.out.println(roleAssignment.name());
            //.withResourceGroupScope(g)
        } catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );        
    } 
}