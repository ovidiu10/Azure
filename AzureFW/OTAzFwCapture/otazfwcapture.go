// /* spell-checker: disable */
package main

import (
	"context"
	"fmt"
	"log"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/network/armnetwork/v4"
)

func main() {
	fmt.Println("Azure Firewall Capture")
	var subid string = ""
	var sSASURL string = ""
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatalf("failed to obtain a credential: %v", err)
	}
	ctx := context.Background()
	clientFactory, err := armnetwork.NewClientFactory(subid, cred, nil)
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}
	poller, err := clientFactory.NewAzureFirewallsClient().BeginPacketCapture(ctx, "rg1", "azureFirewall1", armnetwork.FirewallPacketCaptureParameters{
		Properties: &armnetwork.FirewallPacketCaptureParametersFormat{
			DurationInSeconds: to.Ptr[int32](300),
			FileName:          to.Ptr("azureFirewallPacketCapture"),
			Filters: []*armnetwork.AzureFirewallPacketCaptureRule{
				{
					DestinationPorts: []*string{
						to.Ptr("4500")},
					Destinations: []*string{
						to.Ptr("20.1.2.0")},
					Sources: []*string{
						to.Ptr("20.1.1.0")},
				},
				{
					DestinationPorts: []*string{
						to.Ptr("123"),
						to.Ptr("80")},
					Destinations: []*string{
						to.Ptr("10.1.2.0")},
					Sources: []*string{
						to.Ptr("10.1.1.0"),
						to.Ptr("10.1.1.1")},
				}},
			Flags: []*armnetwork.AzureFirewallPacketCaptureFlags{
				{
					Type: to.Ptr(armnetwork.AzureFirewallPacketCaptureFlagsTypeSyn),
				},
				{
					Type: to.Ptr(armnetwork.AzureFirewallPacketCaptureFlagsTypeFin),
				}},
			NumberOfPacketsToCapture: to.Ptr[int32](5000),
			SasURL:                   to.Ptr(sSASURL),
			Protocol:                 to.Ptr(armnetwork.AzureFirewallNetworkRuleProtocolAny),
		},
	}, nil)
	if err != nil {
		log.Fatalf("failed to finish the request: %v", err)
	}
	_, err = poller.PollUntilDone(ctx, nil)
	if err != nil {
		log.Fatalf("failed to pull the result: %v", err)
	}
}
