package io.otnwappgw.model;

import com.azure.core.util.serializer.SerializerAdapter;
import com.azure.core.util.serializer.SerializerEncoding;
import com.azure.core.management.AzureEnvironment;
import com.fasterxml.jackson.annotation.JsonIgnore;
import com.azure.core.management.serializer.SerializerFactory;

import java.io.File;
import java.io.IOException;
import java.lang.reflect.ParameterizedType;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;
import java.lang.reflect.Type;

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
            throw new IOException("Invalid auth file content.");
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