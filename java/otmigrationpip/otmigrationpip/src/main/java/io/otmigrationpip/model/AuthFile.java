// /* spell-checker: disable */
package io.otmigrationpip.model;

import java.io.File;
import java.io.IOException;
import java.io.StringReader;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;
import java.util.Properties;

import com.azure.core.management.AzureEnvironment;
import com.azure.core.management.serializer.SerializerFactory;
import com.azure.core.util.serializer.SerializerAdapter;
import com.azure.core.util.serializer.SerializerEncoding;
import com.fasterxml.jackson.annotation.JsonIgnore;

public class AuthFile {
    private String clientId;
    private String clientSecret;
    private String subscriptionId;
    private String tenantId;

    @JsonIgnore
    private final AzureEnvironment environment;
    @JsonIgnore
    private static final SerializerAdapter ADAPTER = SerializerFactory.createDefaultManagementSerializerAdapter();

    private AuthFile() {
        environment = new AzureEnvironment(new HashMap<>());
        environment.getEndpoints().putAll(AzureEnvironment.AZURE.getEndpoints());
    }

    public static AuthFile parse(File file) throws IOException {
        AuthFile authFile;
        String content = new String(Files.readAllBytes(Paths.get(file.getPath())), StandardCharsets.UTF_8);
        if (isJsonBased(content)) {
            authFile = ADAPTER.deserialize(content, AuthFile.class, SerializerEncoding.JSON);
            Map<String, String> endpoints = ADAPTER.deserialize(content,
                    createParameterizedType(Map.class, String.class, String.class),
                    SerializerEncoding.JSON);
            authFile.environment.getEndpoints().putAll(endpoints);
        } else {
            // Set defaults
            Properties authSettings = new Properties();
            authSettings.put(AuthFile.CredentialSettings.AUTH_URL.toString(),
                    AzureEnvironment.AZURE.getActiveDirectoryEndpoint());
            authSettings.put(AuthFile.CredentialSettings.BASE_URL.toString(),
                    AzureEnvironment.AZURE.getResourceManagerEndpoint());
            authSettings.put(AuthFile.CredentialSettings.MANAGEMENT_URI.toString(),
                    AzureEnvironment.AZURE.getManagementEndpoint());
            authSettings.put(AuthFile.CredentialSettings.GRAPH_URL.toString(),
                    AzureEnvironment.AZURE.getMicrosoftGraphEndpoint());
            authSettings.put(AuthFile.CredentialSettings.VAULT_SUFFIX.toString(),
                    AzureEnvironment.AZURE.getKeyVaultDnsSuffix());
            // Load the credentials from the file
            StringReader credentialsReader = new StringReader(content);
            authSettings.load(credentialsReader);
            credentialsReader.close();
            authFile = new AuthFile();
            authFile.clientId = authSettings.getProperty(AuthFile.CredentialSettings.CLIENT_ID.toString());
            authFile.tenantId = authSettings.getProperty(AuthFile.CredentialSettings.TENANT_ID.toString());
            authFile.clientSecret = authSettings.getProperty(AuthFile.CredentialSettings.CLIENT_KEY.toString());
            authFile.subscriptionId = authSettings.getProperty(AuthFile.CredentialSettings.SUBSCRIPTION_ID.toString());
            authFile.environment.getEndpoints().put(AzureEnvironment.Endpoint.MANAGEMENT.identifier(),
                    authSettings.getProperty(AuthFile.CredentialSettings.MANAGEMENT_URI.toString()));
            authFile.environment.getEndpoints().put(AzureEnvironment.Endpoint.ACTIVE_DIRECTORY.identifier(),
                    authSettings.getProperty(AuthFile.CredentialSettings.AUTH_URL.toString()));
            authFile.environment.getEndpoints().put(AzureEnvironment.Endpoint.RESOURCE_MANAGER.identifier(),
                    authSettings.getProperty(AuthFile.CredentialSettings.BASE_URL.toString()));
            authFile.environment.getEndpoints().put(AzureEnvironment.Endpoint.GRAPH.identifier(),
                    authSettings.getProperty(AuthFile.CredentialSettings.GRAPH_URL.toString()));
            authFile.environment.getEndpoints().put(AzureEnvironment.Endpoint.KEYVAULT.identifier(),
                    authSettings.getProperty(AuthFile.CredentialSettings.VAULT_SUFFIX.toString()));
        }
        return authFile;
    }

    private static boolean isJsonBased(String content) {
        return content.startsWith("{");
    }

    static ParameterizedType createParameterizedType(Class<?> rawClass, Type... genericTypes) {
        return new ParameterizedType() {
            @Override
            public Type[] getActualTypeArguments() {
                return genericTypes;
            }

            @Override
            public Type getRawType() {
                return rawClass;
            }

            @Override
            public Type getOwnerType() {
                return null;
            }
        };
    }

    /**
     * @return the subscription ID.
     */
    public String getSubscriptionId() {
        return this.subscriptionId;
    }

    /**
     * @return the tenant ID.
     */
    public String getTenantId() {
        return this.tenantId;
    }

    /**
     * @return the environment.
     */
    public AzureEnvironment getEnvironment() {
        return this.environment;
    }

    /**
     * @return the client ID.
     */
    public String getClientId() {
        return this.clientId;
    }

    /**
     * @return the client Secret.
     */
    public String getClientSecret() {
        return this.clientSecret;
    }

    private enum CredentialSettings {
        /**
         * The subscription GUID.
         */
        SUBSCRIPTION_ID("subscription"),
        /**
         * The tenant GUID or domain.
         */
        TENANT_ID("tenant"),
        /**
         * The client id for the client application.
         */
        CLIENT_ID("client"),
        /**
         * The client secret for the service principal.
         */
        CLIENT_KEY("key"),
        /**
         * The management endpoint.
         */
        MANAGEMENT_URI("managementURI"),
        /**
         * The base URL to the current Azure environment.
         */
        BASE_URL("baseURL"),
        /**
         * The URL to Active Directory authentication.
         */
        AUTH_URL("authURL"),
        /**
         * The URL to Active Directory Graph.
         */
        GRAPH_URL("graphURL"),
        /**
         * The suffix of Key Vaults.
         */
        VAULT_SUFFIX("vaultSuffix");

        /**
         * The name of the key in the properties file.
         */
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
