package ca.otDemoSDK1.util;

import com.azure.core.management.AzureEnvironment;

public class TokenData {
    public final String clientId;
    public final String clientSecret;
    public final AzureEnvironment environment;
    public final String tenantId;
    public final String subcriptionId;
    
    public TokenData(String clientId, String domain, String secret, String subcriptionId, AzureEnvironment environment) {
        this.environment = (environment == null) ? AzureEnvironment.AZURE : environment;
        this.clientId = clientId;
        this.clientSecret = secret;
        this.tenantId = domain;
        this.subcriptionId = subcriptionId;
    }
}
