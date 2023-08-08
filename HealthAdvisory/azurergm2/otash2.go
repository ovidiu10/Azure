package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

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
		"| extend eventType = properties.EventType, status = properties.Status, description = properties.Title, " +
		"trackingId = tostring(properties.TrackingId), summary = properties.Summary, priority = properties.Priority, " +
		"impactStartTime = properties.ImpactStartTime, impactMitigationTime = todatetime(tolong(properties.ImpactMitigationTime)), " +
		"impact = properties.Impact"
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
	headers := []string{"trackingId", "subscriptionId", "status", "description", "impact region(s)", "impact service(s)"}
	var data2 [][]string
	data2 = append(data2, headers)
	for _, item := range trackingId {
		var impactRegions string = ""
		var impactServices string = ""
		var impact interface{} = item["impact"]
		for _, item1 := range impact.([]interface{}) {
			mapping := item1.(map[string]interface{})
			for _, item2 := range mapping["ImpactedRegions"].([]interface{}) {
				mapping1 := item2.(map[string]interface{})
				impactRegions = impactRegions + mapping1["ImpactedRegion"].(string) + " "
			}
			impactServices = impactServices + mapping["ImpactedService"].(string) + " "
		}
		impactRegions = strings.TrimSpace(impactRegions)
		impactServices = strings.TrimSpace(impactServices)
		var subIds string = item["subscriptionId"].(string)
		//fmt.Printf("trackingId: %s, subscriptionId: %s, status: %s, description: %s, impactregions: %s, impactservices %s \n",
		//	item["trackingId"].(string), subIds, item["status"].(string), item["description"].(string),
		//	impactRegions, impactServices)
		row := []string{item["trackingId"].(string), subIds, item["status"].(string), item["description"].(string),
			impactRegions, impactServices}
		data2 = append(data2, row)
		//fmt.Println(impact)
	}
	//fmt.Println(data2)
	clientsFile, err := os.OpenFile("clients1.csv", os.O_RDWR|os.O_CREATE|os.O_TRUNC, os.ModePerm)
	if err != nil {
		log.Fatalf("failed to open file: %v", err)
	}
	defer clientsFile.Close()
	w := csv.NewWriter(clientsFile)
	defer w.Flush()
	w.WriteAll(data2)
	if err := w.Error(); err != nil {
		log.Fatal(err)
	}
	fmt.Println("done")
}
