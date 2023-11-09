###/*spell-checker: disable*/
from azure.identity import ClientSecretCredential, DefaultAzureCredential, AzureCliCredential
from kiota_authentication_azure.azure_identity_authentication_provider import AzureIdentityAuthenticationProvider
from msgraph import GraphRequestAdapter, GraphServiceClient
from msgraph.generated.applications.applications_request_builder import ApplicationsRequestBuilder
import os, sys, getopt

async def main(argv):
    try:
      opts, args = getopt.getopt(argv,"ha:t:",["appId=","tenantId="])
    except getopt.GetoptError:
      print ('otaad.py -appId <appId> -tenantId <tenantId>')
      sys.exit(2)
    if (len(sys.argv) < 1):
        print ('otaad.py -appId <appId> -tenantId <tenantId>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('otaad.py -appId <appId> -tenantId <tenantId>')
            sys.exit()
        elif opt in ("-a", "--appId"):
            appId = arg   
        elif opt in ("-t", "--tenantId"):
            tenantId = arg
    if appId == '' or tenantId == '':
        print ('otaad.py -appId <appId> -tenantId <tenantId>')
        sys.exit(2)
    scopes = ['https://graph.microsoft.com/.default']
    credential  = DefaultAzureCredential(visual_studio_code_tenant_id=tenantId) 
    client = GraphServiceClient(credential, scopes)
    query_params = ApplicationsRequestBuilder.ApplicationsRequestBuilderGetQueryParameters(
        filter = f"appId eq '{appId}'" 
    )
    request_config = ApplicationsRequestBuilder.ApplicationsRequestBuilderGetRequestConfiguration(query_parameters=query_params)
    apps = await client.applications.get(request_configuration=request_config)
    if apps and apps.value:
        for app in apps.value:
            print(app.display_name, app.app_id, app.password_credentials[0].end_date_time)
    else:
        print('No apps found')    

if __name__ == "__main__":
    import asyncio      
    asyncio.run(main(sys.argv[1:])) 