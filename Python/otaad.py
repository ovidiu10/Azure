from azure.identity import ClientSecretCredential, DefaultAzureCredential, AzureCliCredential
from kiota_authentication_azure.azure_identity_authentication_provider import AzureIdentityAuthenticationProvider
from msgraph import GraphRequestAdapter, GraphServiceClient
from msgraph.generated.applications.applications_request_builder import ApplicationsRequestBuilder

scopes = ['https://graph.microsoft.com/.default']

credential  = DefaultAzureCredential()
auth_provider = AzureIdentityAuthenticationProvider(credential, scopes=scopes)
request_adapter = GraphRequestAdapter(auth_provider)

client = GraphServiceClient(request_adapter)
async def main(appId):
    query_params = ApplicationsRequestBuilder.ApplicationsRequestBuilderGetQueryParameters(
        filter = f"appId eq '{appId}'"        
    )
    request_config = ApplicationsRequestBuilder.ApplicationsRequestBuilderGetRequestConfiguration(query_parameters=query_params)
    apps = await client.applications.get(request_configuration=request_config)
    if apps and apps.value:
        for app in apps.value:
            print(app.display_name, app.app_id, app.password_credentials[0].end_date_time)    

if __name__ == "__main__":
    import asyncio
    asyncio.run(main(appId='00000003-0000-0000-c000-000000000000'))