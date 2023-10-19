package io.otnwappgw.model;

public class Credential 
{
    private String clientId;
    private String clientSecret;
    private String subscriptionId;
    private String tenantId;

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