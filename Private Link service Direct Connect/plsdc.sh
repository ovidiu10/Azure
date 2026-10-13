#!/bin/bash
#cSpell:disable
# connect to Azure using CLI
az login
# set the subscription context
subscriptionId="your-subscription-id"
az account set --subscription "your-subscription-id"

# check if the feature is registered
az feature show --name AllowPrivateLinkserviceUDR   --namespace Microsoft.Network -o table
# register the feature if not registered
az feature register --name AllowPrivateLinkserviceUDR --namespace Microsoft.Network

resourceGroupName="rg-pls-directconnect"
location="westus"
vnetName="pls-vnet"
subnetName="pls-subnet"
plsName="pls-directconnect"
destinationIP="10.0.1.100"
lbName="pls-ilb"
myNSG="myNSG"
az group create --name $resourceGroupName --location $location
az network vnet create -g $resourceGroupName --name $vnetName --address-prefix 10.0.0.0/16 --subnet-name $subnetName --subnet-prefix 10.0.1.0/24
# disable private endpoint network policies on the subnet
az network vnet subnet update --resource-group $resourceGroupName --vnet-name $vnetName --name $subnetName --private-link-service-network-policies Disabled
# create the private link service with two static IP configurations and a destination IP ( IP of the frontend Azure Internal Load Balancer)
az network private-link-service create -g $resourceGroupName --name $plsName --destination-ip-address $destinationIP --location $location --ip-configurations '[
      {
        "name": "ipconfig1",
        "primary": true,
        "private-ip-allocation-method": "Static",
        "private-ip-address": "10.0.1.10",
        "subnet": {
          "id": "/subscriptions/'$subscriptionId'/resourceGroups/'$resourceGroupName'/providers/Microsoft.Network/virtualNetworks/'$vnetName'/subnets/'$subnetName'"
        }
      },
      {
        "name": "ipconfig2",
        "primary": false,
        "private-ip-allocation-method": "Static",
        "private-ip-address": "10.0.1.11",
        "subnet": {
          "id": "/subscriptions/'$subscriptionId'/resourceGroups/'$resourceGroupName'/providers/Microsoft.Network/virtualNetworks/'$vnetName'/subnets/'$subnetName'"
        }
      }
    ]'
# create Azure Internal Load Balancer as the backend for the Private Link Service
az network lb create -g $resourceGroupName --name $lbName --sku Standard --vnet-name $vnetName --subnet $subnetName --private-ip-address $destinationIP --frontend-ip-name pls-ilb-frontend --backend-pool-name pls-ilb-backendpool
az network lb probe create --resource-group $resourceGroupName --lb-name $lbName --name pls-ilb-healthprobe --protocol tcp --port 80
az network lb rule create --resource-group $resourceGroupName --lb-name $lbName --name pls-ilb-http-rule --protocol tcp --frontend-port 80 --backend-port 80 --frontend-ip-name pls-ilb-frontend --backend-pool-name pls-ilb-backendpool --probe-name pls-ilb-healthprobe --idle-timeout 15 --enable-tcp-reset true

az network nsg create --resource-group $resourceGroupName --name $myNSG
az network nsg rule create --resource-group $resourceGroupName --nsg-name $myNSG --name myNSGRuleHTTP --protocol '*' --direction inbound --source-address-prefix '*' --source-port-range '*' --destination-address-prefix '*' --destination-port-range 80 --access allow --priority 200

array=(myNicVM1 myNicVM2)
  for vmnic in "${array[@]}"
  do
    az network nic create --resource-group $resourceGroupName --name $vmnic --vnet-name myVNet --subnet myBackEndSubnet --network-security-group $myNSG
  done

array=(1 2)
  for n in "${array[@]}"
  do
    az vm create --resource-group $resourceGroupName2 --name myVM$n --nics myNicVM$n --image win2022datacenter --admin-username azureuser --zone $n --no-wait
  done