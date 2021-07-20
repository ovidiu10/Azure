using System;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

namespace otkvcapp
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Dot Core 3 Console - Azure Key Vault");
            string keyVaultName = "otkv1";
            string secretName = "App1Test";
            var kvUri = "https://" + keyVaultName + ".vault.azure.net";
            var client = new SecretClient(new Uri(kvUri), new DefaultAzureCredential());
            KeyVaultSecret secret = client.GetSecret(secretName);
            Console.WriteLine("Your secret is '" + secret.Value + "'.");
        }
    }
}
