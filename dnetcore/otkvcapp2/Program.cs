using System;
using System.Threading.Tasks;
using Microsoft.Azure.KeyVault;
using  Microsoft.Azure.Management.Fluent;
using Microsoft.IdentityModel.Clients.ActiveDirectory;
using Microsoft.Azure.Management.ResourceManager.Fluent;
using Microsoft.Azure.Management.ResourceManager.Fluent.Authentication;

namespace otkvcapp2
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Dot Core 3 Console - Azure Key Vault");
            string keyVaultName = "otkv1";
            string secretName = "App1Test";
            var kvUri = "https://" + keyVaultName + ".vault.azure.net";
            var credentials = SdkContext.AzureCredentialsFactory.FromFile(Environment
                                        .GetEnvironmentVariable("AZURE_AUTH_LOCATION"));
            string clientId = Environment.GetEnvironmentVariable("azureclientid");
            string clientSecret = Environment.GetEnvironmentVariable("azureclientsecret");
            KeyVaultClient kvClient = new KeyVaultClient(async(authority, resource, scope) => 
            {
                var adCredential = new ClientCredential(clientId, clientSecret);
                var authenticationContext = new AuthenticationContext(authority, null);
                return (await authenticationContext.AcquireTokenAsync(resource, adCredential)).AccessToken;
            });
            KV1 kv1 = new KV1();
            var a1 = kv1.GetSecret(kvClient, kvUri, secretName);
            Console.WriteLine("Your secret is '" + a1.Result + "' ");
            //Console.WriteLine(credentials);
            //IAzure azure = Azure.Configure().Authenticate(credentials).WithDefaultSubscription();
        }
    }

    public class KV1 
    {
        public async Task<string> GetSecret(KeyVaultClient kvClient, string kvURL, string secretName)
        {                
            var keyvaultSecret = await kvClient.GetSecretAsync($"{kvURL}", secretName).ConfigureAwait(false);
            return keyvaultSecret.Value;
        }
    }
}
