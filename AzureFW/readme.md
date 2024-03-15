# Azure Firewall package capture #

The Azure Firewall package capture feature allows you to capture network traffic that flows through your Azure Firewall. This feature can be useful for troubleshooting network issues, analyzing network traffic patterns, and detecting security threats.

To use the package capture feature, you must first enable it on your Azure Firewall. You can do this through the Azure portal or by using Azure PowerShell or Azure CLI (in the future today only Rest API and [SDKs: Python, Go, Java, JavaScripts and dotNet](https://learn.microsoft.com/en-us/rest/api/firewall/azure-firewalls/packet-capture?tabs=HTTP)). Once enabled, you can configure the capture settings, such as the capture duration, capture filter, and capture format.

After you have configured the capture settings, you can start a capture session. During the capture session, the Azure Firewall captures network traffic that matches the capture filter and saves it to a capture file in the specified format. You can then download the capture file and analyze it using a network protocol analyzer, such as Wireshark.

It is *important to note that the package capture feature may impact the performance of your Azure Firewall*, so it is recommended to use it only when necessary and for a limited duration. Additionally, you should ensure that you comply with any applicable data privacy and security regulations when capturing network traffic.

Sample circular capture using Go: [OTAzfwCapture](/OTAzFwCapture/otazfwcapture.go)
