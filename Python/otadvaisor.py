import os
import azure.mgmt.resourcegraph as arg

from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import SubscriptionClient

credential = DefaultAzureCredential()
subscription_client = SubscriptionClient(credential)
subscription = next(subscription_client.subscriptions.list())
subId = subscription.subscription_id
subsList = []
subsList.append(subId)
#strQuery = "Resources | project name, type | limit 5" ### Sample 
strQuery = "advisorresources | where type == \"microsoft.advisor/recommendations\""

argClient = arg.ResourceGraphClient(credential)
argQueryOptions = arg.models.QueryRequestOptions(result_format="objectArray")
argQuery = arg.models.QueryRequest(subscriptions=subsList, query=strQuery, options=argQueryOptions)
argResults = argClient.resources(argQuery)

print(argResults.count)
print(argResults)