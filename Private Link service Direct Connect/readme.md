# Private Link service Direct Connect

*Azure Private Link service allows service providers to make their applications available to their customers privately and securely by placing them behind a standard load balancer. Private Link service Direct Connect expands on this capability and allows customers to directly connect a private link service to any privately routable destination IP address. This configuration is particularly useful for scenarios that provide private connectivity to applications that require direct IP-based routing, such as database connections or custom applications.*

In this mini sample I'll create a PLSDC with backend Azure Internal Load Balancer using Az CLI.

This feature as today is in preview.

**This feature is in public preview and is available in select regions. Review all considerations before enabling it for your subscription.**

Official link: [Configure Private Link service Direct Connect](https://learn.microsoft.com/en-us/azure/private-link/configure-private-link-service-direct-connect)

