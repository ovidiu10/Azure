import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.resource import ResourceManagementClient

def main():
    SUBSCRIPTION_ID = ""
    GROUP_NAME = ""
    DISK = ""

    resource_client = ResourceManagementClient(
        credential=DefaultAzureCredential(),
        subscription_id=SUBSCRIPTION_ID
    )
    compute_client = ComputeManagementClient(
        credential=DefaultAzureCredential(),
        subscription_id=SUBSCRIPTION_ID
    )

    disk = compute_client.disks.get(
        GROUP_NAME,
        DISK
    )
    print("Get disk:\n{}".format(disk.sku))

if __name__ == "__main__":
    main()