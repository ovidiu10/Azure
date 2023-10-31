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
    
    client.azure_firewalls.begin_packet_capture(
        resource_group_name="rg1",
        azure_firewall_name="azureFirewall1",
        parameters={
            "properties": {
                "durationInSeconds": 300,
                "fileName": "azureFirewallPacketCapture",
                "filters": [
                    {"destinationPorts": ["4500"], "destinations": ["20.1.2.0"], "sources": ["20.1.1.0"]},
                    {
                        "destinationPorts": ["123", "80"],
                        "destinations": ["10.1.2.0"],
                        "sources": ["10.1.1.0", "10.1.1.1"],
                    },
                ],
                "flags": [{"type": "syn"}, {"type": "fin"}],
                "numberOfPacketsToCapture": 5000,
                "protocol": "Any",
                "sasUrl": "someSASURL",
            }
        },
    ).result()

if __name__ == "__main__":
    capture()

