import os
import time
from azure.identity import ClientSecretCredential
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient
from azure.mgmt.cognitiveservices.models import Account, Sku

# Be sure to use the service pricipal application ID, not simply the ID. 
service_principal_application_id = os.environ['azureclientid']
service_principal_secret = os.environ['azureclientsecret']

# The ID of your Azure subscription. You can find this in the Azure Dashboard under Home > Subscriptions.
subscription_id = ""

# The Active Directory tenant ID. You can find this in the Azure Dashboard under Home > Azure Active Directory.
tenant_id = ""

# The name of the Azure resource group in which you want to create the resource.
# You can find resource groups in the Azure Dashboard under Home > Resource groups.
resource_group_name = "rg-java"

# The name of the custom subdomain to use when you create the resource. This is optional.
# For example, if you create a Bing Search v7 resource with the custom subdomain name 'my-search-resource',
# your resource would have the endpoint https://my-search-resource.cognitiveservices.azure.com/.
# Note not all Cognitive Services allow custom subdomain names.
subdomain_name = ""

# How many seconds to wait between checking the status of an async operation.
wait_time = 10

resource_name = "Face1"
resource_kind = "FormRecognizer"
resource_sku = "F0"
resource_location = "EastUS"

credential = ClientSecretCredential(tenant_id, service_principal_application_id, service_principal_secret)
client = CognitiveServicesManagementClient(credential, subscription_id)

def create_resource (resource_name, kind, sku_name, location) :
    print("Creating resource: " + resource_name + "...")

# NOTE If you do not want to use a custom subdomain name, remove the customSubDomainName
# property from the properties object.
    parameters = Account(sku=Sku(name=sku_name), kind=kind, location=location, properties={ 'custom_sub_domain_name' : subdomain_name })

    poller = client.accounts.begin_create(resource_group_name, resource_name, parameters)
    while (False == poller.done ()) :
        print ("Waiting {wait_time} seconds for operation to finish.".format (wait_time = wait_time))
        time.sleep (wait_time)
# This will raise an exception if the server responded with an error.
    result = poller.result ()

    print("Resource created.")
    print()
    print("ID: " + result.id)       # type: ignore
    print("Name: " + result.name)   # type: ignore
    print("Type: " + result.type)   # type: ignore
    print()

def list_resources():
    print("Resources in resource group: " + resource_group_name)
    result = client.accounts.list_by_resource_group(resource_group_name)
    for x in result:
        print(x.name)  # type: ignore
        print(x)
        print()

def delete_resource(resource_name) :
    print("Deleting resource: " + resource_name + "...")

    poller = client.accounts.begin_delete(resource_group_name, resource_name)
    while (False == poller.done ()) :
        print ("Waiting {wait_time} seconds for operation to finish.".format (wait_time = wait_time))
        time.sleep (wait_time)
# This will raise an exception if the server responded with an error.
    result = poller.result ()

    print("Resource deleted.")

create_resource(resource_name, resource_kind, resource_sku, resource_location)
#list_resources()
#delete_resource(resource_name)
#purge_resource(resource_name, resource_location)