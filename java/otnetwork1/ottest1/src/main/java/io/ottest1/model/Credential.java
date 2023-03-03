package io.ottest1.model;

public class Credential 
{
    private String clientId;
    private String clientSecret;
    private String subscriptionId;
    private String tenantId;
    private String activeDirectoryEndpointUrl;
    private String resourceManagerEndpointUrl;
    private String sqlManagementEndpointUrl;
    private String galleryEndpointUrl;
    private String managementEndpointUrl;

    public String getclientId() {
        return clientId;
    }

    public String getclientSecret() {
        return clientSecret;
    }

    public String getsubscriptionId() {
        return subscriptionId;
    }

    public String gettenantId() {
        return tenantId;
    }
}