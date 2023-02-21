# Azure Policy

- blocking deploy Open AI [azurepolicydoai](azurepolicydoai.json)

---
ARM template specifications:

## [Microsoft.CognitiveServices accounts](https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts?pivots=deployment-language-arm-template)

```json
{
    "id": "/subscriptions/55A44XXX-ZZZZ-CCCC-8888-56677AACC1234/resourceGroups/researchlab-rg/providers/Microsoft.CognitiveServices/accounts/aitest-eu-openai",
    "name": "aitest-eu-openai",
    "type": "Microsoft.CognitiveServices/accounts",
    "etag": "\"00000000-0000-0100-0000-000000000000\"",
    "location": "EastUs",
    "sku": {
        "name": "S0"
    },
    "kind": "OpenAI",
    ...
}
```

---
