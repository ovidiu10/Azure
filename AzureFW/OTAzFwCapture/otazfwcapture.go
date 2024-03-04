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
	var rg string = "rg-netcore2"
	var azfw string = "otcore2-azfw"
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatalf("failed to obtain a credential: %v", err)
	}
	ctx := context.Background()
	clientFactory, err := armnetwork.NewClientFactory(subid, cred, nil)
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}
	poller, err := clientFactory.NewAzureFirewallsClient().BeginPacketCapture(ctx, rg, azfw,
		armnetwork.FirewallPacketCaptureParameters{
			Properties: &armnetwork.FirewallPacketCaptureParametersFormat{
				DurationInSeconds: to.Ptr[int32](300),
				FileName:          to.Ptr("azureFirewallPacketCapture"),
				Filters: []*armnetwork.AzureFirewallPacketCaptureRule{
					{
						DestinationPorts: []*string{
							to.Ptr("443")},
						Destinations: []*string{
							to.Ptr("172.253.115.147")},
						Sources: []*string{
							to.Ptr("192.168.252.4")},
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
