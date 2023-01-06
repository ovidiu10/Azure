from azure.identity import AzureCliCredential
from azure.mgmt.resource import ResourceManagementClient
import os
import json

credential = AzureCliCredential()

subscription_id = ""
resource_group = ""

resource_client = ResourceManagementClient(credential, subscription_id)

resource_list = resource_client.resources.list_by_resource_group(resource_group, expand = "createdTime, changeTime")

column_width = 30
print("Resource".ljust(column_width) + "Type".ljust(column_width)
    + "Create date".ljust(column_width) + "Change date".ljust(column_width))
print("-" * (column_width * 4))

for resource in list(resource_list):
    print(f"{resource.name:<{column_width}}{resource.type:<{column_width}}"
       f"{str(resource.created_time):<{column_width}}{str(resource.changed_time):<{column_width}}")