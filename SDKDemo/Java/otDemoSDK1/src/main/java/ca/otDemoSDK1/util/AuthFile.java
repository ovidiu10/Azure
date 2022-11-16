package ca.otDemoSDK1.util;

import java.io.File;
import java.io.IOException;
import java.io.StringReader;
import java.util.Properties;

import com.azure.core.management.AzureEnvironment;
import com.google.common.base.Charsets;
import com.google.common.io.Files;

public class AuthFile {
    private String clientId;
    private String tenantId;
    private String clientSecret;
    private String clientCertificate;
    private String clientCertificatePassword;
    private String subscriptionId;
    private AzureEnvironment environment;
    private String authFilePath;

    public static AuthFile parse(File file) throws IOException {
        String content = Files.toString(file, Charsets.UTF_8).trim();

        Properties authSettings = new Properties(); 
        authSettings.put(CredentialSettings.AUTH_URL.toString(), AzureEnvironment.AZURE.getActiveDirectoryEndpoint());
        authSettings.put(CredentialSettings.BASE_URL.toString(), AzureEnvironment.AZURE.getResourceManagerEndpoint());
        authSettings.put(CredentialSettings.MANAGEMENT_URI.toString(), AzureEnvironment.AZURE.getManagementEndpoint());
        authSettings.put(CredentialSettings.GRAPH_URL.toString(), AzureEnvironment.AZURE.getGraphEndpoint());
        authSettings.put(CredentialSettings.VAULT_SUFFIX.toString(), AzureEnvironment.AZURE.getKeyVaultDnsSuffix());

        AuthFile authFile;
        StringReader credentialsReader = new StringReader(content);
        authSettings.load(credentialsReader);
        credentialsReader.close();
        authFile = new AuthFile();
        if (authSettings.getProperty(CredentialSettings.CLIENT_ID.toString()) != "") {
            authFile.clientId = authSettings.getProperty(CredentialSettings.CLIENT_ID.toString());
            authFile.tenantId = authSettings.getProperty(CredentialSettings.TENANT_ID.toString());
            authFile.clientSecret = authSettings.getProperty(CredentialSettings.CLIENT_KEY.toString());
            authFile.clientCertificate = authSettings.getProperty(CredentialSettings.CLIENT_CERT.toString());
            authFile.clientCertificatePassword = authSettings.getProperty(CredentialSettings.CLIENT_CERT_PASS.toString());
            authFile.subscriptionId = authSettings.getProperty(CredentialSettings.SUBSCRIPTION_ID.toString());
        }
        else {
            authFile.clientId = authSettings.getProperty("client");
            authFile.tenantId = authSettings.getProperty("tenant");
            authFile.clientSecret = authSettings.getProperty("key");
            authFile.clientCertificate = ""; // need to improve
            authFile.clientCertificatePassword = ""; // need to improve 
            authFile.subscriptionId = authSettings.getProperty("subscription");
        }    
        authFile.authFilePath = file.getParent();

        return authFile;
    }

    /**
     * @return
     */
    public TokenData generateCredentials() throws IOException {
        if (clientSecret != null) {
            return (TokenData) new TokenData(
                    clientId,
                    tenantId,
                    clientSecret,
                    subscriptionId,
                    AzureEnvironment.AZURE);
        } else {
            throw new IllegalArgumentException("Please specify either a client key or a client certificate.");
        }
    }

    private enum CredentialSettings {
        /** The subscription GUID. */
        SUBSCRIPTION_ID("subscription"),
        /** The tenant GUID or domain. */
        TENANT_ID("tenant"),
        /** The client id for the client application. */
        CLIENT_ID("client"),
        /** The client secret for the service principal. */
        CLIENT_KEY("key"),
        /** The client certificate for the service principal. */
        CLIENT_CERT("certificate"),
        /** The password for the client certificate for the service principal. */
        CLIENT_CERT_PASS("certificatePassword"),
        /** The management endpoint. */
        MANAGEMENT_URI("managementURI"),
        /** The base URL to the current Azure environment. */
        BASE_URL("baseURL"),
        /** The URL to Active Directory authentication. */
        AUTH_URL("authURL"),
        /** The URL to Active Directory Graph. */
        GRAPH_URL("graphURL"),
        /** The suffix of Key Vaults. */
        VAULT_SUFFIX("vaultSuffix");

        /** The name of the key in the properties file. */
        private final String name;

        CredentialSettings(String name) {
            this.name = name;
        }

        @Override
        public String toString() {
            return this.name;
        }
    }

}
