# Get-AzureRoleAssignments

Enumerates all direct Azure IAM role assignments across one or more subscriptions and exports the results to CSV.

## Description

`Get-AzureRoleAssignments` connects to Microsoft Graph and Azure, then retrieves all direct (non-inherited) Azure role assignments across every subscription the authenticated account has access to. Results are written to a timestamped CSV file suitable for use in access reviews.

By default the script queries all accessible subscriptions and returns assignments for all principals. Both behaviors can be narrowed using the `-SubscriptionIds` and `-PrincipalDisplayNames` parameters respectively.

## Requirements

- **PowerShell** 5.1 or later
- **Microsoft.Graph** module (`Connect-MgGraph`)
- **Az** module (`Connect-AzAccount`, `Get-AzSubscription`, `Get-AzRoleAssignment`, `Get-AzRoleDefinition`)

### Microsoft Graph Scopes

- `Directory.Read.All`
- `User.Read.All`

## Parameters

| Parameter | Type | Description |
|------------|------|-------------|
| `PrincipalDisplayNames` | `string[]` | One or more principal display names to filter results by. When provided, only role assignments where the principal's display name matches an entry in this list will be returned. When omitted, all principals are included. |
| `SubscriptionIds` | `string[]` | One or more subscription GUIDs to scope the query to. When provided, only the specified subscriptions are queried. When omitted, all subscriptions accessible to the authenticated account are queried. |
| `OutputPath` | `string` | The directory path where the output CSV file will be written. Defaults to the current working directory. The filename is auto-generated in the format `AzureRoleAssignments_yyyyMMdd_HHmmss.csv`. |
| `TenantId` | `string` | The Entra tenant ID to authenticate against. Used by both `Connect-MgGraph` and `Connect-AzAccount`. When omitted, the default tenant for the authenticated account is used. |
| `ClientId` | `string` | The application (client) ID to use for Microsoft Graph authentication when authenticating as a service principal. |
| `ClientSecret` | `SecureString` | The client secret for service principal authentication against Microsoft Graph. |
| `CertificateThumbprint` | `string` | The thumbprint of a certificate to use for service principal authentication. Applies to both Microsoft Graph and Azure connections. |
| `CertificateName` | `string` | The name of a certificate to use for Microsoft Graph service principal authentication. |
| `Credential` | `PSCredential` | A PSCredential object for Azure authentication. Typically used for service principal or username/password flows. |
| `ServicePrincipal` | `switch` | Switch indicating that the provided credentials represent a service principal rather than a user account. Used with `Connect-AzAccount`. |
| `Environment` | `string` | The Azure environment to connect to (e.g., `AzureCloud`, `AzureUSGovernment`, `AzureChinaCloud`). Defaults to `AzureCloud` when omitted. |
| `NoWelcome` | `bool` | Suppresses the Microsoft Graph welcome message on connect. Defaults to `$true`. |

## Authentication

Authentication defaults to interactive login for both Microsoft Graph and Azure. Service principal authentication is supported via:

- Credential (username/password)
- Certificate thumbprint
- Certificate name

## Usage

### Basic Usage

Connect interactively and export all direct Azure role assignments across all accessible subscriptions:

```powershell
.\Get-AzureRoleAssignments.ps1
```

### Filter by Subscription and Principal

Connect interactively, query a single subscription, filter results to named principals, and write output to a specific directory:

```powershell
.\Get-AzureRoleAssignments.ps1 -SubscriptionIds 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -PrincipalDisplayNames 'Finance Team', 'Security Admins' -OutputPath 'C:\AccessReviews'
```

### Service Principal with Certificate

Authenticate as a service principal using a certificate against the specified tenant:

```powershell
.\Get-AzureRoleAssignments.ps1 -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -CertificateThumbprint 'ABC123...' -ServicePrincipal
```

### Service Principal with Client Secret

```powershell
$secureSecret = ConvertTo-SecureString -String 'your-client-secret' -AsPlainText -Force
.\Get-AzureRoleAssignments.ps1 -TenantId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -ClientSecret $secureSecret -ServicePrincipal
```

## Output

The script generates a CSV file with the following columns:

- `SubscriptionId` — The Azure subscription ID
- `SubscriptionName` — The Azure subscription name
- `RoleAssignmentId` — The unique role assignment ID
- `RoleDefinitionName` — The role name (e.g., "Owner", "Contributor", "Reader")
- `RoleDefinitionId` — The role definition ID
- `PrincipalType` — The type of principal (e.g., User, Group, ServicePrincipal)
- `PrincipalId` — The principal's unique ID
- `PrincipalDisplayName` — The principal's display name
- `PrincipalEmail` — The principal's email (if available)
- `Scope` — The scope of the assignment
- `ScopeType` — The type of scope (e.g., /subscriptions, /resourceGroups)
- `AssignmentType` — Whether the assignment is direct or inherited
- `CreatedOn` — When the assignment was created
- `CreatedBy` — Who created the assignment

Filename format: `AzureRoleAssignments_yyyyMMdd_HHmmss.csv`

## Author

**Scott Pack**  
scott.pack@gmail.com

Last Update: 22 April 2026  
Version: 1.0