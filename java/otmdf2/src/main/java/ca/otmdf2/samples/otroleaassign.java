// /* spell-checker: disable */
package ca.otmdf2.samples;

import java.util.*;

import com.azure.core.credential.TokenCredential;
import com.azure.core.http.policy.HttpLogDetailLevel;
import com.azure.core.management.AzureEnvironment;
//import com.azure.core.management.Region;
import com.azure.core.management.profile.AzureProfile;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.resourcemanager.AzureResourceManager;
//import com.azure.resourcemanager.authorization.models.BuiltInRole;
//import com.azure.resourcemanager.authorization.models.RoleAssignment;
//import com.azure.resourcemanager.compute.models.InstanceViewStatus;
//import com.azure.resourcemanager.compute.models.OSDisk;
import com.azure.resourcemanager.compute.models.PowerState;
import com.azure.resourcemanager.compute.models.VirtualMachine;
import com.azure.resourcemanager.compute.models.VirtualMachineExtension;
import com.azure.resourcemanager.compute.models.VirtualMachineExtensionInstanceView;
//import com.azure.resourcemanager.msi.models.Identity;

public class otroleaassign {
    public static void main(String[] args) {
        try {
            final String sId = "";
            //final String rg = "rg-java";
            //final String storageName = "storageName";
            //final String userIdentityName = "uidt1";
            final AzureProfile profile = new AzureProfile(AzureEnvironment.AZURE);
            final TokenCredential credential = new DefaultAzureCredentialBuilder()
                .authorityHost(profile.getEnvironment().getActiveDirectoryEndpoint())
                .build();             
            AzureResourceManager azureResourceManager = AzureResourceManager
                .configure()
                .withLogLevel(HttpLogDetailLevel.BASIC)
                .authenticate(credential, profile)
                .withSubscription(sId);
            VirtualMachine vm2 = azureResourceManager.virtualMachines().getById("/subscriptions/.../resourceGroups/rg-ppg1/providers/Microsoft.Compute/virtualMachines/otvm1ppg1");
            if (vm2.powerState() != PowerState.DEALLOCATED) {                 
                Map<String, VirtualMachineExtension> extensions = vm2.listExtensions();                        
                extensions.forEach((extK, extV) -> {
                    System.out.println(extK);
                    VirtualMachineExtensionInstanceView e1 = extV.getInstanceView();
                    System.out.println(e1.name());
                });           
            }
            //VirtualMachine vm1 = azureResourceManager.virtualMachines().getByResourceGroup("rg-pps1", "otvm1" );
            //OSDisk osdisk1 = vm1.storageProfile().osDisk();
            //vm1.update().withOSDisk("disk").apply();
            /*
                azureResourceManager.snapshots().define("testdisk1")
                            .withRegion(Region.US_EAST)
                            .withExistingResourceGroup(rg)
                            .withLinuxFromSnapshot("snapshotResourceID")
                            .create();
            */
            /*
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
            */
        }
        catch (final Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done " +  new Date()); 
    }
}

