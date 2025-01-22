### /* spell-checker: disable */
from azure.identity import DefaultAzureCredential
from azure.mgmt.network import NetworkManagementClient
from dotenv import load_dotenv
import os
import json

def load_env():
    load_dotenv(".env") 
    print(os.environ['AZURE_SUBSCRIPTION_ID'])

def capture():
    print("Capture Azure Firewall")
    load_env()
    client = NetworkManagementClient(
        credential=DefaultAzureCredential(),
        subscription_id=os.environ['AZURE_SUBSCRIPTION_ID']
    )
    sSASURL = os.environ['AZURE_STORAGE_SAS_URL']
    
    client.azure_firewalls.begin_packet_capture(
        resource_group_name="rg-netcore2",
        azure_firewall_name="otcore2-azfw",
        parameters={
            "durationInSeconds": 300,
            "fileName": "azureFirewallPacketCapture",
            "filters": [
                {
                    "destinationPorts": ["443"],
                    "destinations": ["172.253.115.147"],
                    "sources": ["192.168.252.4"],
                },
            ],
            "flags": [{"type": "syn"}, {"type": "fin"}],
            "numberOfPacketsToCapture": 5000,
            "protocol": "Any",
            "sasUrl": sSASURL,
        },
    ).result()

if __name__ == "__main__":
    capture()

