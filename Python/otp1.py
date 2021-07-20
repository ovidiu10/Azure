import os

from azure.identity import DefaultAzureCredential
from azure.common.client_factory import get_client_from_auth_file
from azure.mgmt.resource import SubscriptionClient
from azure.common.credentials import ServicePrincipalCredentials

#subscription_client = SubscriptionClient(credential=DefaultAzureCredential())
#subscription_client = get_client_from_auth_file(SubscriptionClient(credential=DefaultAzureCredential()), auth_path="cred.json", )

#subscription = next(subscription_client.subscriptions.list())
#print(subscription.subscription_id)

credential=DefaultAzureCredential()
subscription_client = SubscriptionClient(credential)
subscription = next(subscription_client.subscriptions.list())
print(subscription.subscription_id)


#credential=DefaultAzureCredential()

#print(os.environ['AZURE_CLIENT_ID'])

#credential = get_client_from_auth_file(ServicePrincipalCredentials, auth_path="/OT/.azauth/cred.json")
#subscription_client = get_client_from_auth_file(SubscriptionClient, auth_path="/OT/.azauth/cred.json")
#subscription_client = get_client_from_auth_file(SubscriptionClient)
#print(subscription_client)


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

#SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", None)
#print(SUBSCRIPTION_ID)

#print(os.environ['azureclientid'])
#print(os.environ['azureclientsecret'])
#print(os.environ['AZURE_CLIENT_SECRET'])
#print(os.environ['AZURE_TENANT_ID'])