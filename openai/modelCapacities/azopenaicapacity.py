#/* spell-checker: disable */
import string
from azure.identity import DefaultAzureCredential
import requests
import argparse
import pandas as pd
import json

def main():
    print("Open AI Model Capacities")
    parser = argparse.ArgumentParser(description="Display values for -s, -a, -mf, and -mn arguments")
    parser.add_argument("-s", type=str, help="Subscription_ID")
    parser.add_argument("-mf", type=str, help="Model_Format")
    parser.add_argument("-mn", type=str, help="Model_Name")
    parser.add_argument("-a", type=str, help="API")
    
    args = parser.parse_args()

    print("Subscription ID:", args.s)
    print("Model Format:", args.mf)
    print("Model Name:", args.mn)
    print("API:", args.a)

    # Acquire a credential object using CLI-based authentication.
    credential = DefaultAzureCredential()
    subscription_id = args.s
    model_format = args.mf
    model_name = args.mn
    api = args.a
    print(list_modelCapacities(subscription_id, model_format, model_name, api, credential=credential))

def list_modelCapacities(subscription_id, model_format, model_name, model_version, credential):
    url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.CognitiveServices/modelCapacities?api-version=2024-04-01-preview&modelFormat={model_format}&modelName={model_name}&modelVersion={model_version}"
    access_token = credential.get_token("https://management.azure.com/.default").token
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    params = {
        "modelFormat": model_format,
        "modelName": model_name,
        "modelVersion": model_version
    }
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        data = json.loads(response.text)
        extracted_data = [
            {
                'location': item['location'],
                'skuName': item['properties']['skuName'],
                'availableCapacity': item['properties']['availableCapacity']
            }
            for item in data['value']
        ]
        df = pd.DataFrame(extracted_data)
        return print(df)
        #return response.json()
    else:
        return {"error": response.status_code, "message": response.text}


if __name__ == "__main__":
    main()