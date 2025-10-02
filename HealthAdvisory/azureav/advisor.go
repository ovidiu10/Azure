// cspell:disable
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"text/tabwriter"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
)

type Metadata struct {
	Value []struct {
		ID         string `json:"id"`
		Properties struct {
			SupportedValues []string `json:"supportedValues"`
		} `json:"properties"`
	} `json:"value"`
}

func main() {
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()
	scope := "https://management.azure.com/.default"
	token, err := cred.GetToken(ctx, policy.TokenRequestOptions{
		Scopes: []string{scope},
	})
	if err != nil {
		log.Fatalf("failed to get token: %v", err)
	}

	baseURL := "https://management.azure.com/providers/Microsoft.Advisor/metadata?api-version=2025-01-01"
	queryParams := url.Values{}
	queryParams.Add("$filter", "recommendationCategory eq 'HighAvailability' and recommendationControl eq 'ServiceUpgradeAndRetirement'")
	queryParams.Add("$expand", "ibiza")
	fmt.Println("Query Parameters:", queryParams.Encode())
	fullURL := fmt.Sprintf("%s&%s", baseURL, queryParams.Encode())
	fmt.Println("Parsed URL:", fullURL)
	req, err := http.NewRequest("GET", fullURL, nil)
	if err != nil {
		log.Fatalf("failed to create HTTP request: %v", err)
	}

	// Set the Authorization header
	req.Header.Set("Authorization", "Bearer "+token.Token)
	req.Header.Set("Content-Type", "application/json")

	// Execute the HTTP request
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatalf("HTTP request failed: %v", err)
	}
	defer resp.Body.Close()

	// Print the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Fatalf("failed to read response body: %v", err)
	}

	fmt.Printf("Status Code: %d\n", resp.StatusCode)

	// Save the raw response body to a file
	err = os.WriteFile("advisor_response2.json", body, 0644)
	if err != nil {
		log.Fatalf("failed to save response body to file: %v", err)
	}
	fmt.Println("Response body saved to advisor_response2.json")

	// Parse JSON and extract supportedValues for recommendationType
	var root struct {
		Value []struct {
			ID         string `json:"id"`
			Properties struct {
				SupportedValues []interface{} `json:"supportedValues"`
			} `json:"properties"`
		} `json:"value"`
	}

	if err := json.Unmarshal(body, &root); err != nil {
		log.Fatal(err)
	}

	var supportedValues []interface{}
	for _, item := range root.Value {
		if item.ID == "/providers/Microsoft.Advisor/metadata/recommendationType" {
			fmt.Println("Found recommendationType metadata")
			supportedValues = item.Properties.SupportedValues
			break
		}
	}

	if supportedValues == nil {
		log.Fatal("recommendationType metadata not found")
	}

	// Save the filtered supportedValues to JSON file
	supportedValuesJSON, err := json.MarshalIndent(supportedValues, "", "  ")
	if err != nil {
		log.Fatal(err)
	}

	if err := os.WriteFile("recommendation_types.json", supportedValuesJSON, 0644); err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Extracted %d recommendation types and saved to recommendation_types.json\n", len(supportedValues))

	// Convert to map slice for table generation
	var supportedValuesSlice []map[string]interface{}
	if err := json.Unmarshal(supportedValuesJSON, &supportedValuesSlice); err != nil {
		log.Fatal(err)
	}

	// Save as table
	err = saveSupportedValuesTableToFile(supportedValuesSlice, "recommendation_types_table.txt")
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("Recommendation types table saved to recommendation_types_table.txt")
}

func displaySupportedValuesTable(supportedValues []map[string]interface{}) {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "displayName\tdetailedDescription\tcaption\tdescription\tdocumentLink\tid\tlabel\tlearnMoreLink\trecommendationImpact\tretirementDate\tretirementFeatureName\tsupportedResourceType")

	for _, v := range supportedValues {
		displayName := fmt.Sprintf("%v", v["displayName"])
		detailedDescription := fmt.Sprintf("%v", v["detailedDescription"])
		id := fmt.Sprintf("%v", v["id"])
		label := fmt.Sprintf("%v", v["label"])
		learnMoreLink := fmt.Sprintf("%v", v["learnMoreLink"])
		recommendationImpact := fmt.Sprintf("%v", v["recommendationImpact"])
		retirementDate := fmt.Sprintf("%v", v["retirementDate"])
		retirementFeatureName := fmt.Sprintf("%v", v["retirementFeatureName"])
		supportedResourceType := fmt.Sprintf("%v", v["supportedResourceType"])

		// Extract from actions array if present
		caption, description, documentLink := "", "", ""
		if actions, ok := v["actions"].([]interface{}); ok && len(actions) > 0 {
			if action, ok := actions[0].(map[string]interface{}); ok {
				caption = fmt.Sprintf("%v", action["caption"])
				description = fmt.Sprintf("%v", action["description"])
				documentLink = fmt.Sprintf("%v", action["documentLink"])
			}
		}

		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			displayName, detailedDescription, caption, description, documentLink, id, label, learnMoreLink, recommendationImpact, retirementDate, retirementFeatureName, supportedResourceType)
	}
	w.Flush()
}

func saveSupportedValuesTableToFile(supportedValues []map[string]interface{}, filename string) error {
	file, err := os.Create(filename)
	if err != nil {
		return err
	}
	defer file.Close()

	w := tabwriter.NewWriter(file, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "displayName\tdetailedDescription\tcaption\tdescription\tdocumentLink\tid\tlabel\tlearnMoreLink\trecommendationImpact\tretirementDate\tretirementFeatureName\tsupportedResourceType")

	for _, v := range supportedValues {
		displayName := fmt.Sprintf("%v", v["displayName"])
		detailedDescription := fmt.Sprintf("%v", v["detailedDescription"])
		id := fmt.Sprintf("%v", v["id"])
		label := fmt.Sprintf("%v", v["label"])
		learnMoreLink := fmt.Sprintf("%v", v["learnMoreLink"])
		recommendationImpact := fmt.Sprintf("%v", v["recommendationImpact"])
		retirementDate := fmt.Sprintf("%v", v["retirementDate"])
		retirementFeatureName := fmt.Sprintf("%v", v["retirementFeatureName"])
		supportedResourceType := fmt.Sprintf("%v", v["supportedResourceType"])

		caption, description, documentLink := "", "", ""
		if actions, ok := v["actions"].([]interface{}); ok && len(actions) > 0 {
			if action, ok := actions[0].(map[string]interface{}); ok {
				caption = fmt.Sprintf("%v", action["caption"])
				description = fmt.Sprintf("%v", action["description"])
				documentLink = fmt.Sprintf("%v", action["documentLink"])
			}
		}

		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
			displayName, detailedDescription, caption, description, documentLink, id, label, learnMoreLink, recommendationImpact, retirementDate, retirementFeatureName, supportedResourceType)
	}
	w.Flush()
	return nil
}
