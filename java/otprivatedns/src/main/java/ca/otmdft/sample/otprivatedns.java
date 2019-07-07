package ca.otmdft.sample;

import com.microsoft.azure.credentials.ApplicationTokenCredentials;
import com.microsoft.azure.management.Azure;
import com.microsoft.rest.LogLevel;
import com.microsoft.azure.management.network.Network;
import com.microsoft.azure.management.privatedns.v2018_09_01.implementation.PrivateDnsManagementClientImpl;
import com.microsoft.azure.management.privatedns.v2018_09_01.implementation.VirtualNetworkLinkInner;
import com.microsoft.azure.management.privatedns.v2018_09_01.implementation.*;
import com.microsoft.azure.management.privatedns.v2018_09_01.*;
import com.microsoft.azure.SubResource;

import java.util.ArrayList;
import java.util.List;
import java.io.IOException;
import java.io.File;

/**
 * Sample Azure Private DNS
 * 7/1/2019 - version 0.0.3
 *
 */
public class otprivatedns 
{
    public static void main( String[] args )
    {
        String rgName = "rg-privatedns"; // Resource GroupName
        String privateDNSName = "private.contoso.com"; // private DNS name 
        String privateDNSLinkName = "linkToVnet";
        String vnetName = "vnetTest"; // virtual network name - should be exsit  
        String location = "global"; // location always 'global' for privateDNS 
        System.out.println( "Welcome to Azure Private DNS sample" );
        try {
            final File credFile = new File(System.getenv("AZURE_AUTH_LOCATION"));        
            Azure azure = Azure.configure()
                .withLogLevel(LogLevel.NONE)
                .authenticate(credFile)
                .withDefaultSubscription();
            ApplicationTokenCredentials cred = ApplicationTokenCredentials.fromFile(credFile);
            Network vnet = azure.networks().getByResourceGroup(rgName, vnetName); // get virtual network 
            privatednsManager prDnsManager = privatednsManager.authenticate(cred, cred.defaultSubscriptionId());
            prDnsManager.privateZones().define(privateDNSName)
                .withRegion(location)
                .withExistingResourceGroup(rgName)
                .withIfMatch(null)
                .withIfNoneMatch(null)
                .create();
            if (vnet != null) {
                prDnsManager.virtualNetworkLinks().define(privateDNSLinkName)
                    .withExistingPrivateDnsZone(rgName, privateDNSName)
                    .withIfMatch(null)
                    .withIfNoneMatch(null)
                    .withLocation(location)
                    .withRegistrationEnabled(true)
                    .withVirtualNetwork(new SubResource().withId(vnet.id()))
                    .create();
            }
            //add a record manual in DNS
            RecordSetInner recordSetInner = new RecordSetInner();
            ARecord arecord = new ARecord();
            arecord.withIpv4Address("192.168.0.5"); // IP Address for record 
            List<ARecord> list = new ArrayList<ARecord>();
            list.add(arecord);
            recordSetInner.withARecords(list);
            recordSetInner.withTtl(1L);
            String alias = "db"; //alias for IP 
            prDnsManager.recordSets().inner().createOrUpdate(
                rgName, 
                privateDNSName, 
                RecordType.A, 
                alias, 
                recordSetInner);
        } catch (Exception e) {
            System.out.println(e.getMessage());
            e.printStackTrace();
        }
        System.out.println( "Done" );
    }
}
