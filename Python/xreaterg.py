from azure.identity import (
    DefaultAzureCredential,
    ClientSecretCredential
)
from azure.mgmt.resource import ResourceManagementClient
from azure.core import exceptions

import logging
import os
import json
import sys

handler = logging.StreamHandler(stream=sys.stdout)
logger = logging.getLogger('azure.mgmt')
logger.setLevel(logging.DEBUG)
logger.addHandler(handler)

rate_limit_header = None
def response_callback(response):
    #rate_limit_header = response.http_response.headers["x-ms-ratelimit-remaining-subscription-reads"]
    #print(rate_limit_header)
    print(response.http_response.headers)

def get_credentials():
    #subscription_id = os.environ.get(
    #    'AZURE_SUBSCRIPTION_ID',
    #    '11111111-1111-1111-1111-111111111111') # your Azure Subscription Id
    #credentials = ClientSecretCredential (
    #    tenant_id=os.environ['AZURE_TENANT_ID'],
    #    client_id=os.environ['AZURE_CLIENT_ID'],
    #    client_secret=os.environ['AZURE_CLIENT_SECRET']
    #) # type: ignore
    with open(os.environ['AZURE_AUTH_LOCATION2']) as json_file:
        data = json.load(json_file)
    credentials = ClientSecretCredential (
        tenant_id=data['tenantId'],
        client_id=data['clientId'],
        client_secret=data['clientSecret']
    ) # type: ignore
    subscription_id = data['subscriptionId']
    return credentials, subscription_id

def main():
    logging.warning('Watch out!')
    print(
        f"Logger enabled for ERROR={logger.isEnabledFor(logging.ERROR)}, "
        f"WARNING={logger.isEnabledFor(logging.WARNING)}, "
        f"INFO={logger.isEnabledFor(logging.INFO)}, "
        f"DEBUG={logger.isEnabledFor(logging.DEBUG)}"
    )
    credentials, subscription_id = get_credentials()
    client = ResourceManagementClient(
        #credential=credentials,
        credential=DefaultAzureCredential(),
        #subscription_id="00000000-0000-0000-0000-000000000000",
        subscription_id=subscription_id,
        logging_body=True,
        logging_enable=True,
    )
    group_list = client.resource_groups.list(raw_response_hook=response_callback, logging_enable=True)
    column_width = 40
    print("Resource Group".ljust(column_width) + "Location")
    print("-" * (column_width * 2))

    for group in list(group_list):
        print(f"{group.name:<{column_width}}{group.location}")
    print("Done")

if __name__ == "__main__":
    try:
        main()
    except (
        exceptions.ClientAuthenticationError,
        exceptions.HttpResponseError
    ) as e:
        print(e.message)