# Ovidiu Timpanariu
# v0.0.1 2/18/2021

#-------------------------------------------------------------------------
#Test 
#-------------------------------------------------------------------------
#https://github.com/Azure-Samples/azure-samples-python-management/blob/master/samples/advisor/manage_recommendation.py


import os 
import re
import azure.mgmt.resourcegraph as arg

#from azure.identity import DefaultAzureCredential
from azure.identity import ClientSecretCredential
#from azure.common.client_factory import get_client_from_auth_file
from azure.mgmt.resource import SubscriptionClient
from azure.mgmt.advisor import AdvisorManagementClient



#cred = DefaultAzureCredential()
cred = ClientSecretCredential(
    tenant_id = "",
    client_id = "",
    client_secret = "")
#sub_client = get_client_from_auth_file(SubscriptionClient)
sub_client = SubscriptionClient(cred)
subid = next(sub_client.subscriptions.list())
print(subid.subscription_id)

adv = AdvisorManagementClient(cred, subid.subscription_id)
def call(response, *args, **kwargs):
    return response.http_response

response = adv.recommendations.generate(cls = call)
location = response.headers['Location']
operation_id = re.findall("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", location)
recommendation = adv.recommendations.get_generate_status(
    cls = call, 
    operation_id = operation_id[1]
    )
print("Get recommendation status:\n{}".format(recommendation.status_code))

#
"""
subsList = []
subsList.append(subid.subscription_id)
#strQuery = "Resources | project name, type | limit 5"
strQuery = "advisorresources | where type == \"microsoft.advisor/recommendations\""

argClient = arg.ResourceGraphClient(cred)
argQueryOptions = arg.models.QueryRequestOptions(result_format="objectArray")
argQuery = arg.models.QueryRequest(subscriptions=subsList, query=strQuery, options=argQueryOptions)
argResults = argClient.resources(argQuery)

print(argResults)
"""
#

print(os.environ["COMPUTERNAME"])