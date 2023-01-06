from azure.identity import ClientSecretCredential
from azure.mgmt.resource import ResourceManagementClient
import os
import json

with open(os.environ["AZURE_AUTH_LOCATION4"]) as json_file:
    json_dict = json.load(json_file)

credential = ClientSecretCredential(
    tenant_id=json_dict["tenantId"],
    client_id=json_dict["clientId"],
    client_secret=json_dict["clientSecret"],
    authority=json_dict["activeDirectoryEndpointUrl"]
)
subscription_Id = json_dict["subscriptionId"]
resource_client = ResourceManagementClient(credential,subscription_Id)
group_list = resource_client.resource_groups.list()
column_width = 70
print("Resource Group".ljust(column_width) + "Location")
print("-" * (column_width * 2))
for group in list(group_list):
    print(f"{group.name:<{column_width}}{group.location}")
