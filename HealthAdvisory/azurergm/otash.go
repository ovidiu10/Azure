package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strconv"
	"unicode/utf8"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/resourcegraph/armresourcegraph"
)

func main() {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()
	client, err := armresourcegraph.NewClient(cred, nil)
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}
	var s string = "ServiceHealthResources " +
		"| where type =~ 'Microsoft.ResourceHealth/events' " +
		"| extend eventType = properties.EventType, status = properties.Status, description = properties.Title, trackingId = tostring(properties.TrackingId), summary = properties.Summary, priority = properties.Priority, impactStartTime = properties.ImpactStartTime, impactMitigationTime = todatetime(tolong(properties.ImpactMitigationTime)) " +
		"| where eventType == 'HealthAdvisory'"
	res, err := client.Resources(ctx,
		armresourcegraph.QueryRequest{
			Query:         to.Ptr(s),
			Subscriptions: []*string{},
		},
		nil)
	if err != nil {
		log.Fatalf("failed to finish the request: %v", err)
	}
	var k int64 = *res.TotalRecords
	var rt bool
	rt, err = strconv.ParseBool(string(*res.ResultTruncated))
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Total records: %d and all records: %t \n", k, !rt)
	data, _ := json.Marshal(res.Data)
	var p []map[string]any
	json.Unmarshal(data, &p)
	var trackingId = make(map[string]map[string]interface{})
	for _, item := range p {
		_, ok := trackingId[item["trackingId"].(string)]
		if !ok {
			trackingId[item["trackingId"].(string)] = item
		} else {
			var subIds = item["subscriptionId"]
			if subIds != nil || subIds != "" {
				var s1 map[string]interface{} = trackingId[item["trackingId"].(string)]
				s1["subscriptionId"] = s1["subscriptionId"].(string) + ";" + subIds.(string)
			}
		}
	}
	for _, item := range trackingId {
		fmt.Printf("%v | %v | %v\n", item["trackingId"], item["description"], item["subscriptionId"])
	}
}

func ShortText(s string, i int) string {
	if len(s) < i {
		return s
	}
	if utf8.ValidString(s[:i]) {
		return s[:i]
	}
	return s[:i+1]
}
