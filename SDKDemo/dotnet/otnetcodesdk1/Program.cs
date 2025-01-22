using System;
using Azure.Identity;
using Azure.Core;
using Azure.ResourceManager;
using Azure.ResourceManager.Resources;

// See https://aka.ms/new-console-template for more information
string tenantId = "";
string subscriptionId = "";
Console.WriteLine("SDK Testing!");
ArmClient armClient = new ArmClient(new DefaultAzureCredential(
    new DefaultAzureCredentialOptions { TenantId = tenantId }
));
SubscriptionCollection subscriptions = armClient.GetSubscriptions();
SubscriptionResource subscription = subscriptions.Get(subscriptionId);
ResourceGroupCollection rgCollection = subscription.GetResourceGroups();
Console.WriteLine("Subscription ID: " + subscription.Data.SubscriptionId);
Console.WriteLine("Getting resource groups...");
Console.WriteLine($"Found {rgCollection.Count()} resource groups in the subscription");
foreach (ResourceGroupResource rg in rgCollection)
{
    Console.WriteLine($"Resource Group: {rg.Data.Name}");
}   
