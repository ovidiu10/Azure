# Ovidiu Timpanariu
# v0.0.1 10.27.2018

#-------------------------------------------------------------------------
#Proof of concent VNET with StorgageEndpoints 
#-------------------------------------------------------------------------

import os

from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.network.models import Subnet
from azure.mgmt.network.models import ServiceEndpointPropertiesFormat
from azure.mgmt.storage.models import (
    StorageAccountCreateParameters,
    StorageAccountUpdateParameters,
    Sku,
    SkuName,
    Kind         
)
from azure.mgmt.storage.models import NetworkRuleSet
from azure.mgmt.storage.models import VirtualNetworkRule

LOCATION = 'eastus2'
GROUP_NAME = 'rg-python1'
STORAGE_ACCOUNT_NAME = 'otstpy1'
VNET_NAME = 'vnet1'
SB_NAME = "SB1"
VNET_AP = '192.168.61.0/24'
SB_AP = '192.168.61.0/26'

def get_credentials():
    subscription_id = os.environ.get(
        'AZURE_SUBSCRIPTION_ID',
        '11111111-1111-1111-1111-111111111111') # your Azure Subscription Id
    credentials = ServicePrincipalCredentials(
        client_id=os.environ['AZURE_CLIENT_ID'],
        secret=os.environ['AZURE_CLIENT_SECRET'],
        tenant=os.environ['AZURE_TENANT_ID']
    )
    return credentials, subscription_id

# This script expects that the following environment vars are set:
#
# AZURE_TENANT_ID: with your Azure Active Directory tenant id or domain
# AZURE_CLIENT_ID: with your Azure Active Directory Application Client ID
# AZURE_CLIENT_SECRET: with your Azure Active Directory Application Secret
# AZURE_SUBSCRIPTION_ID: with your Azure Subscription Id
#

credentials, subscription_id = get_credentials()

network_client = NetworkManagementClient(credentials, subscription_id) # type: ignore
resource_client = ResourceManagementClient(credentials, subscription_id) # type: ignore
storage_client = StorageManagementClient(credentials, subscription_id) # type: ignore

resource_group_params = {'location':LOCATION}
resource_client.resource_groups.create_or_update(GROUP_NAME, resource_group_params) # type: ignore

vnet_params = { 'location': LOCATION, 'address_space' : { 'address_prefixes': [VNET_AP] } }
async_vnet_creation = network_client.virtual_networks.create_or_update(GROUP_NAME, VNET_NAME, vnet_params) # type: ignore
async_vnet_creation.wait()
ep = ServiceEndpointPropertiesFormat(service='Microsoft.Storage')
ep_list = [ep]
subnet = Subnet(address_prefix = SB_AP, service_endpoints = ep_list)
async_vnet_subnet_creation = network_client.subnets.create_or_update(GROUP_NAME, VNET_NAME, SB_NAME, subnet) # type: ignore
async_vnet_subnet_creation.wait()
if async_vnet_subnet_creation.status() == 'Succeeded':
    sb_result = async_vnet_subnet_creation.result()
    virtual_network_resource_id = sb_result.id
    vr = VirtualNetworkRule(virtual_network_resource_id=virtual_network_resource_id)
    vnets = [vr]
    ns = NetworkRuleSet(bypass='AzureServices', virtual_network_rules=vnets, default_action='Deny')
    storage_client = StorageManagementClient(credentials, subscription_id) # type: ignore
    sku = Sku(name=SkuName.STANDARD_LRS)
    st1 = StorageAccountCreateParameters(sku=sku, kind=Kind.STORAGE_V2, location=LOCATION, network_rule_set=ns)
    storage_async_operation = storage_client.storage_accounts.begin_create(GROUP_NAME, STORAGE_ACCOUNT_NAME, st1, location=LOCATION) # type: ignore
    #stlist = storage_client.storage_accounts.list()

print("Done")

