import os
import sys
import logging

from haikunator import Haikunator
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.storage.models import (
    StorageAccountCreateParameters,
    StorageAccountUpdateParameters,
    Sku,
    SkuName,
    Kind
)

WEST_US = 'westus'
GROUP_NAME = 'azure-sample-group'
STORAGE_ACCOUNT_NAME = Haikunator().haikunate(delimiter='')


def get_credentials():
    subscription_id = os.environ["AZURE_SUBSCRIPTION_ID"]
    credentials = DefaultAzureCredential()
    return credentials, subscription_id

# This script expects that the following environment vars are set:
#
# AZURE_TENANT_ID: with your Azure Active Directory tenant id or domain
# AZURE_CLIENT_ID: with your Azure Active Directory Application Client ID
# AZURE_CLIENT_SECRET: with your Azure Active Directory Application Secret
# AZURE_SUBSCRIPTION_ID: with your Azure Subscription Id
#


def run_example():
    """Storage management example."""
    #
    # Create the Resource Manager Client with an Application (service principal) token provider
    #
    credentials, subscription_id = get_credentials()

    resource_client = ResourceManagementClient(credentials, subscription_id)
    storage_client = StorageManagementClient(credentials, subscription_id)

    # You MIGHT need to add Storage as a valid provider for these credentials
    # If so, this operation has to be done only once for each credentials
    #resource_client.providers.register('Microsoft.Storage')

    # Create Resource group
    print('Create Resource Group')
    resource_group_params = {'location': 'westus'}
    print_item(resource_client.resource_groups.create_or_update(
        GROUP_NAME, resource_group_params))

    # Check availability
    
    # Create a storage account
    print('Create a storage account')
    storage_async_operation = storage_client.storage_accounts.create(
        GROUP_NAME,
        STORAGE_ACCOUNT_NAME,
        StorageAccountCreateParameters(
            sku=Sku(name=SkuName.standard_ragrs),
            kind=Kind.storage,
            location='westus',
            enable_https_traffic_only=True
        )
    )
    storage_account = storage_async_operation.result()
    print_item(storage_account)
    print('\n\n')

    # Get storage account properties
    print('Get storage account properties')
    storage_account = storage_client.storage_accounts.get_properties(
        GROUP_NAME, STORAGE_ACCOUNT_NAME)
    print_item(storage_account)
    print("\n\n")

    # List Storage accounts
    print('List storage accounts')
    for item in storage_client.storage_accounts.list():
        print_item(item)
    print("\n\n")

    # List Storage accounts by resource group
    print('List storage accounts by resource group')
    for item in storage_client.storage_accounts.list_by_resource_group(GROUP_NAME):
        print_item(item)
    print("\n\n")

    # Get the account keys
    print('Get the account keys')
    storage_keys = storage_client.storage_accounts.list_keys(
        GROUP_NAME, STORAGE_ACCOUNT_NAME)
    storage_keys = {v.key_name: v.value for v in storage_keys.keys}
    print('\tKey 1: {}'.format(storage_keys['key1']))
    print('\tKey 2: {}'.format(storage_keys['key2']))
    print("\n\n")

    # Regenerate the account key 1
    print('Regenerate the account key 1')
    storage_keys = storage_client.storage_accounts.regenerate_key(
        GROUP_NAME,
        STORAGE_ACCOUNT_NAME,
        'key1')
    storage_keys = {v.key_name: v.value for v in storage_keys.keys}
    print('\tNew key 1: {}'.format(storage_keys['key1']))
    print("\n\n")

    # Update storage account
    print('Update storage account')
    storage_account = storage_client.storage_accounts.update(
        GROUP_NAME, STORAGE_ACCOUNT_NAME,
        StorageAccountUpdateParameters(
            sku=Sku(name=SkuName.standard_grs)
        )
    )
    print_item(storage_account)
    print("\n\n")

    # Delete the storage account
    print('Delete the storage account')
    storage_client.storage_accounts.delete(GROUP_NAME, STORAGE_ACCOUNT_NAME)
    print("\n\n")

    # Delete Resource group and everything in it
    print('Delete Resource Group')
    delete_async_operation = resource_client.resource_groups.delete(GROUP_NAME)
    delete_async_operation.wait()
    print("Deleted: {}".format(GROUP_NAME))
    print("\n\n")

    # List usage
    print('List usage')
    for usage in storage_client.usages.list_by_location("westus"):
        print('\t{}'.format(usage.name.value))


def print_item(group):
    """Print an Azure object instance."""
    print("\tName: {}".format(group.name))
    print("\tId: {}".format(group.id))
    print("\tLocation: {}".format(group.location))
    print("\tTags: {}".format(group.tags))
    if hasattr(group, 'properties'):
        print_properties(group.properties)


def print_properties(props):
    """Print a ResourceGroup properties instance."""
    if props and props.provisioning_state:
        print("\tProperties:")
        print("\t\tProvisioning State: {}".format(props.provisioning_state))
    print("\n\n")


if __name__ == "__main__":
    run_example()
