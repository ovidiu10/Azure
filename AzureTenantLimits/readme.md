# Azure Tenant Limits

Azure ecosystem has a lot of limits some hard limits sometime adjustable limits.

Some services have adjustable limits.
When a service doesn't have adjustable limits, the following tables use the header Limit. In those cases, the default and the maximum limits are the same.

When the limit can be adjusted, the tables include Default limit and Maximum limit headers. The limit can be raised above the default limit but not above the maximum limit.

If you want to raise the limit or quota above the default limit, open an online customer support [request at no charge](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/error-resource-quota).

The terms soft limit and hard limit often are used informally to describe the current, adjustable limit (soft limit) and the maximum limit (hard limit). If a limit isn't adjustable, there won't be a soft limit, only a hard limit.

## In this article we are looking to tenant limits which can be sometime forget to review and check

<br />
Microsoft always improve observability for limits but also we need to monitor them :smiley:.
<br />

| Resource | Limit |
| --- | --- |
| Management groups per Azure AD tenant | 10,000 |
| Subscriptions per management group | Unlimited. |
| Subscriptions [associated with an Azure Active Directory tenant](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-subscriptions-associated-directory) | Unlimited |
| Levels of management group hierarchy | Root level plus 6 levels<sup>1</sup> |
| Direct parent management group per management group | One |
| [Management group level deployments](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-to-management-group) per location | 800<sup>2</sup> |
| Locations of [Management group level deployments](.ttps://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-to-management-group) | 10 |
| [Coadministrators](../articles/cost-management-billing/manage/add-change-subscription-administrator.md) per subscription |Unlimited |
| [Resource groups](../articles/azure-resource-manager/management/overview.md) per subscription |980 |
| Azure Resource Manager API request size |4,194,304 bytes |
| Tags per subscription<sup>3</sup> |50 |
| Unique tag calculations per subscription<sup>4</sup> | 80,000 |
| [Subscription-level deployments](../articles/azure-resource-manager/templates/deploy-to-subscription.md) per location | 800<sup>5</sup> |
| Locations of [Subscription-level deployments](../articles/azure-resource-manager/templates/deploy-to-subscription.md) | 10 |

<sup>1</sup>The 6 levels don't include the subscription level. <br />
<sup>2</sup>If you reach the limit of 800 deployments, delete deployments from the history that are no longer needed. To delete management group level deployments, use [Remove-AzManagementGroupDeployment](/powershell/module/az.resources/Remove-AzManagementGroupDeployment) or [az deployment mg delete](/cli/azure/deployment/mg#az-deployment-mg-delete). <br />
<sup>3</sup>You can apply up to 50 tags directly to a subscription. However, the subscription can contain an unlimited number of tags that are applied to resource groups and resources within the subscription. The number of tags per resource or resource group is limited to 50. <br />
<sup>4</sup>Resource Manager returns a [list of tag name and values](/rest/api/resources/tags) in the subscription only when the number of unique tags is 80,000 or less. A unique tag is defined by the combination of resource ID, tag name, and tag value. For example, two resources with the same tag name and value would be calculated as two unique tags. You still can find a resource by tag when the number exceeds 80,000. <br />
<sup>5</sup>Deployments are automatically deleted from the history as you near the limit. For more information, see [Automatic deletions from deployment history](../articles/azure-resource-manager/templates/deployment-history-deletions.md).

| Category | Limit |
| --- | --- |
| Tenants | <li>A single user can belong to a maximum of 500 Azure AD tenants as a member or a guest. <li>A single user can create a maximum of 200 directories. |
| Domains | <li>You can add no more than 5,000 managed domain names. <li>If you set up all of your domains for federation with on-premises Active Directory, you can add no more than 2,500 domain names in each tenant. |
|Resources |<ul><li>By default, a maximum of 50,000 Azure AD resources can be created in a single tenant by users of the Azure Active Directory Free edition. If you have at least one verified domain, the default Azure AD service quota for your organization is extended to 300,000 Azure AD resources. <br>The Azure AD service quota for organizations created by self-service sign-up remains 50,000 Azure AD resources, even after you perform an internal admin takeover and the organization is converted to a managed tenant with at least one verified domain. This service limit is unrelated to the pricing tier limit of 500,000 resources on the Azure AD pricing page. <br>To go beyond the default quota, you must contact Microsoft Support.</li><li>A non-admin user can create no more than 250 Azure AD resources. Both active resources and deleted resources that are available to restore count toward this quota. Only deleted Azure AD resources that were deleted fewer than 30 days ago are available to restore. Deleted Azure AD resources that are no longer available to restore count toward this quota at a value of one-quarter for 30 days. <br>If you have developers who are likely to repeatedly exceed this quota in the course of their regular duties, you can [create and assign a custom role](../articles/active-directory/roles/quickstart-app-registration-limits.md) with permission to create a limitless number of app registrations.</li><li>Resource limitations apply to all directory objects in a given Azure AD tenant, including users, groups, applications, and service principals.</li></ul> |
| Schema extensions |<ul><li>String-type extensions can have a maximum of 256 characters. </li><li>Binary-type extensions are limited to 256 bytes.</li><li>Only 100 extension values, across *all* types and *all* applications, can be written to any single Azure AD resource.</li><li>Only User, Group, TenantDetail, Device, Application, and ServicePrincipal entities can be extended with string-type or binary-type single-valued attributes.</li></ul> |
| Applications | <ul><li>A maximum of 100 users and service principals can be owners of a single application.</li><li>A user, group, or service principal can have a maximum of 1,500 app role assignments. The limitation is on the service principal, user, or group across all app roles and not on the number of assignments on a single app role.</li><li>An app configured for password-based single sign-on can have a maximum of 48 groups assigned with credentials configured.</li><li>A user can have credentials configured for a maximum of 48 apps using password-based single sign-on. This limit only applies for credentials configured when the user is directly assigned the app, not when the user is a member of a group which is assigned.</li><li>See additional limits in [Validation differences by supported account types](../articles/active-directory/develop/supported-accounts-validation.md).</li></ul> |
|Application manifest |A maximum of 1,200 entries can be added to the application manifest.<br/>See additional limits in [Validation differences by supported account types](../articles/active-directory/develop/supported-accounts-validation.md). |
| Groups |<ul><li>A non-admin user can create a maximum of 250 groups in an Azure AD organization. Any Azure AD admin who can manage groups in the organization can also create an unlimited number of groups (up to the Azure AD object limit). If you assign a role to a user to remove the limit for that user, assign a less privileged, built-in role such as User Administrator or Groups Administrator.</li><li>An Azure AD organization can have a maximum of 5,000 dynamic groups and dynamic administrative units combined.</li><li>A maximum of 500 [role-assignable groups](../articles/active-directory/roles/groups-concept.md) can be created in a single Azure AD organization (tenant).</li><li>A maximum of 100 users can be owners of a single group.</li><li>Any number of Azure AD resources can be members of a single group.</li><li>A user can be a member of any number of groups. When security groups are being used in combination with SharePoint Online, a user can be a part of 2,049 security groups in total. This includes both direct and indirect group memberships. When this limit is exceeded, authentication and search results become unpredictable.</li><li>By default, the number of members in a group that you can synchronize from your on-premises Active Directory to Azure Active Directory by using Azure AD Connect is limited to 50,000 members. If you need to sync a group membership that's over this limit, you must onboard the [Azure AD Connect Sync V2 endpoint API](../articles/active-directory/hybrid/how-to-connect-sync-endpoint-api-v2.md).</li><li>When you select a list of groups, you can assign a group expiration policy to a maximum of 500 Microsoft 365 groups. There is no limit when the policy is applied to all Microsoft 365 groups.</li></ul><br/> At this time, the following scenarios are supported with nested groups:<ul><li> One group can be added as a member of another group, and you can achieve group nesting.</li><li> Group membership claims. When an app is configured to receive group membership claims in the token, nested groups in which the signed-in user is a member are included.</li><li>Conditional access (when a conditional access policy has a group scope).</li><li>Restricting access to self-serve password reset.</li><li>Restricting which users can do Azure AD Join and device registration.</li></ul><br/>The following scenarios are *not* supported with nested groups:<ul><li> App role assignment, for both access and provisioning. Assigning groups to an app is supported, but any groups nested within the directly assigned group won't have access.</li><li>Group-based licensing (assigning a license automatically to all members of a group).</li><li>Microsoft 365 Groups.</li></ul> |
| Application Proxy | <ul><li>A maximum of 500 transactions\* per second per Application Proxy application.</li><li>A maximum of 750 transactions per second for the Azure AD organization.<br><br>\*A transaction is defined as a single HTTP request and response for a unique resource. When clients are throttled, they'll receive a 429 response (too many requests). |
| Access Panel |There's no limit to the number of applications per user that can be displayed in the Access Panel, regardless of the number of assigned licenses.  |
| Reports | A maximum of 1,000 rows can be viewed or downloaded in any report. Any additional data is truncated. |
| Administrative units | <ul><li>An Azure AD resource can be a member of no more than 30 administrative units.</li><li>An Azure AD organization can have a maximum of 5,000 dynamic groups and dynamic administrative units combined.</li></ul> |
| Azure AD roles and permissions | <ul><li>A maximum of 100 [Azure AD custom roles](/azure/active-directory//users-groups-roles/roles-custom-overview?context=azure%2factive-directory%2fusers-groups-roles%2fcontext%2fugr-context) can be created in an Azure AD organization.</li><li>A maximum of 150 Azure AD custom role assignments for a single principal at any scope.</li><li>A maximum of 100 Azure AD built-in role assignments for a single principal at non-tenant scope (such as an administrative unit or Azure AD object). There is no limit to Azure AD built-in role assignments at tenant scope. For more information, see [Assign Azure AD roles at different scopes](../articles/active-directory/roles/assign-roles-different-scopes.md).</li><li>A group can't be added as a [group owner](../articles/active-directory/fundamentals/users-default-permissions.md?context=azure%2factive-directory%2fusers-groups-roles%2fcontext%2fugr-context#object-ownership).</li><li>A user's ability to read other users' tenant information can be restricted only by the Azure AD organization-wide switch to disable all non-admin users' access to all tenant information (not recommended). For more information, see [To restrict the default permissions for member users](../articles/active-directory/fundamentals/users-default-permissions.md?context=azure%2factive-directory%2fusers-groups-roles%2fcontext%2fugr-context#restrict-member-users-default-permissions).</li><li>It might take up to 15 minutes or you might have to sign out and sign back in before admin role membership additions and revocations take effect.</li></ul> |
|Conditional Access Policies|A maximum of 195 policies can be created in a single Azure AD organization (tenant).|

There's a maximum count for each object type for Azure Policy. For definitions, an entry of _Scope_ means the [management group](../articles/governance/management-groups/overview.md) or subscription. For assignments and exemptions, an entry of _Scope_ means the [management group](../articles/governance/management-groups/overview.md), subscription, resource group, or individual resource.

| Where | What | Maximum count |
|---|---|---|
| Scope | Policy definitions | 500 |
| Scope | Initiative definitions | 200 |
| Tenant | Initiative definitions | 2,500 |
| Scope | Policy or initiative assignments | 200 |
| Scope | Exemptions | 1000 |
| Policy definition | Parameters | 20 |
| Initiative definition | Policies | 1000 |
| Initiative definition | Parameters | 300 |
| Policy or initiative assignments | Exclusions (notScopes) | 400 |
| Policy rule | Nested conditionals | 512 |
| Remediation task | Resources | 50,000 |
| Policy definition, initiative, or assignment request body | Bytes | 1,048,576 |

| Area | Resource | Limit |
| --- | --- | --- |
| [Azure role assignments](../../articles/role-based-access-control/overview.md) |  |  |
|  | Azure role assignments per Azure subscription | 4,000 |
|  | Azure role assignments per Azure subscription<br/>(for Azure Government and Azure China 21Vianet) | 2,000 |
|  | Azure role assignments per management group | 500 |
|  | Size of description for Azure role assignments | 2 KB |
|  | Size of [condition](../../articles/role-based-access-control/conditions-overview.md) for Azure role assignments | 8 KB |
| [Azure custom roles](../../articles/role-based-access-control/custom-roles.md) |  |  |
|  | Azure custom roles per tenant | 5,000 |
|  | Azure custom roles per tenant<br/>(for Azure China 21Vianet) | 2,000 |
|  | Size of role name for Azure custom roles | 512 chars |
|  | Size of description for Azure custom roles | 2 KB |
|  | Number of assignable scopes for Azure custom roles | 2,000 |

The following table describes the maximum limits for Azure Virtual Desktop.

| **Azure Virtual Desktop Object**                    | **Per Parent Container Object**                     | **Service Limit**   |
|-----------------------------------------------------|-------------------------------------------------|--------------------------------------------------|
| Workspace                                           | Azure Active Directory Tenant                   | 1300 |
| HostPool                                            | Workspace                                       | 400 |
| Application group                                   | Azure Active Directory Tenant                   | 500<sup>1</sup>  |
| RemoteApp                                           | Application group                               | 500 |
| Role Assignment                                     | Any Azure Virtual Desktop Object                | 200 |
| Session Host                                        | HostPool                                        | 10,000 |

<sup>1</sup>If you require over 500 Application groups then please raise a support ticket via the Azure portal.

All other Azure resources used in Azure Virtual Desktop such as Virtual Machines, Storage, Networking etc. are all subject to their own resource limitations documented in the relevant sections of this article. 
To visualise the relationship between all the Azure Virtual Desktop objects, review this article [Relationships between Azure Virtual Desktop logical components](/azure/architecture/example-scenario/wvd/windows-virtual-desktop#azure-virtual-desktop-limitations).

To get started with Azure Virtual Desktop, use the [getting started guide](../articles/virtual-desktop/overview.md).
For deeper architectural content for Azure Virtual Desktop, use the [Azure Virtual Desktop section of the Cloud Adoption Framework](/azure/cloud-adoption-framework/scenarios/wvd/).
For pricing information for Azure Virtual Desktop, add "Azure Virtual Desktop" within the Compute section of the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator).

- Each managed identity counts towards the object quota limit in an Azure AD tenant as described in [Azure AD service limits and restrictions](../articles/active-directory/enterprise-users/directory-service-limits-restrictions.md).
-	The rate at which managed identities can be created have the following limits:

    1. Per Azure AD Tenant per Azure region: 400 create operations per 20 seconds.
    2. Per Azure Subscription per Azure region : 80 create operations per 20 seconds.

-	The rate at which a user-assigned managed identity can be assigned with an Azure resource :

    1. Per Azure AD Tenant per Azure region: 400 assignment operations per 20 seconds.
    2. Per Azure Subscription per Azure region : 300 assignment operations per 20 seconds.







---
