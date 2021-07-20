package ca.otmdf2.samples;

import java.util.Date;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
import com.azure.resourcemanager.authorization.models.BuiltInRole;
import com.azure.resourcemanager.authorization.models.RoleAssignment;
import com.azure.resourcemanager.msi.models.Identity;

public class otroleaassign {
    public static void main(String[] args) {
        try {
            final String sId = "<subscription id>";
            final String rg = "rg-java";
            final String storageName = "storageName";
            final String userIdentityName = "uidt1"
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            final TokenCredential credential = new DefaultAzureCredentialBuilder()
                .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                .build();             
            AzureResourceManager azureResourceManager = AzureResourceManager
                .configure()
                .withLogLevel(HttpLogDetailLevel.BASIC)
                .authenticate(credential, profile)
                .withSubscription(sId);
            String scope = String.format("subscriptions/%s/resourceGroups/%s/providers/Microsoft.Storage/storageAccounts/%s/blobServices/default/containers/%s", 
                sId, rg, storageName, "test1" );
            Identity identity = azureResourceManager.identities()
                .getByResourceGroup(rg, userIdentityName);
            final String raName2 = azureResourceManager
                .resourceGroups()
                .manager()
                .internalContext().randomUuid();
            RoleAssignment roleAssignment = azureResourceManager.accessManagement().roleAssignments()
                .define(raName2)
                .forObjectId(identity.principalId())
                .withBuiltInRole(BuiltInRole.STORAGE_BLOB_DATA_READER)
                .withScope(scope)
                .create();
            System.out.println(roleAssignment.name());
        }
        catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done " +  new Date()); 
    }
}

