import os
import azure.mgmt.resourcegraph as arg

from azure.identity import AzureCliCredential, DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient


def main():
    client = arg.ResourceGraphClient(
        credential=AzureCliCredential(), subscription_id="11111111-1111-1111-1111-45d9209f3a9c"
    )
    response = client.resources(
        query={
            "query": "Resources | where type =~ 'Microsoft.Compute/virtualMachines' | summarize count() by tostring(properties.storageProfile.osDisk.osType)",
            "subscriptions": ["11111111-1111-1111-1111-11111111111"],
        }, # type: ignore
    )
    print(response)

if __name__ == "__main__":
    main()

# "query": "Resources | where type =~ 'Microsoft.Compute/virtualMachines' | summarize count() by tostring(properties.storageProfile.osDisk.osType)",