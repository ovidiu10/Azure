using System;
using Azure.Identity;
using Azure.Core;
using Azure.ResourceManager;
using Azure.ResourceManager.Resources;

// See https://aka.ms/new-console-template for more information
Console.WriteLine("SDK Testing!");
ArmClient armClient = new ArmClient(new DefaultAzureCredential(
    new DefaultAzureCredentialOptions { TenantId = "3daa70ca-2390-4c3a-8d40-86f93d5d5b10" }
));
SubscriptionCollection subscriptions = armClient.GetSubscriptions();
SubscriptionResource subscription = subscriptions.Get("8451578e-4ec2-47cb-aa28-45d9209f3a9c");
ResourceGroupCollection rgCollection = subscription.GetResourceGroups();
Console.WriteLine("Subscription ID: " + subscription.Data.SubscriptionId);
Console.WriteLine("Getting resource groups...");
Console.WriteLine($"Found {rgCollection.Count()} resource groups in the subscription");
