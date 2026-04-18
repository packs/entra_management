<#
    .SYNOPSIS
        This script accepts an Entra security group and enumerates all of the Azure roles and permissions assigned to the provided group across all subscriptions.

    .NOTES
        Scott Pack
        scott.pack@gmail.com

        Last Update: 28 August 2025
        Version 1.0
#>


param (
    [string[]]$GroupDisplayNames
)

# Prepare output list
$results = @()

# Connect to Microsoft services
Connect-MgGraph -Scopes "RoleManagement.Read.All", "Directory.Read.All", "Application.Read.All"
Connect-AzAccount

# Get all subscriptions
$subscriptions = Get-AzSubscription

foreach ($GroupDisplayName in $GroupDisplayNames) {
    $group = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'"
    if (-not $group) {
        Write-Warning "Group '$GroupDisplayName' not found."
        continue
    }

    $groupId = $group.Id

    # Azure Role Assignments across all subscriptions
    foreach ($sub in $subscriptions) {
        Set-AzContext -SubscriptionId $sub.Id | Out-Null
        $roleAssignments = Get-AzRoleAssignment -ObjectId $groupId
        foreach ($assignment in $roleAssignments) {
            $roleDef = Get-AzRoleDefinition -Id $assignment.RoleDefinitionId
            $results += [PSCustomObject]@{
                GroupName = $GroupDisplayName
                Type = "Azure Role"
                RoleOrApp = $roleDef.RoleName
                Scope = $assignment.Scope
                Subscription = $sub.Name
            }
        }
    }

    # Entra Role Assignments
    $graphRoles = Get-MgDirectoryRole | Where-Object {
        $_.Members -contains $groupId
    }
    foreach ($role in $graphRoles) {
        $results += [PSCustomObject]@{
            GroupName = $GroupDisplayName
            Type = "Entra Role"
            RoleOrApp = $role.DisplayName
            Scope = "Directory"
            Subscription = "N/A"
        }
    }

    # Enterprise App Assignments
    $servicePrincipals = Get-MgServicePrincipal
    foreach ($sp in $servicePrincipals) {
        $assignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id
        foreach ($assignment in $assignments) {
            if ($assignment.PrincipalId -eq $groupId) {
                $results += [PSCustomObject]@{
                    GroupName = $GroupDisplayName
                    Type = "App Assignment"
                    RoleOrApp = $sp.DisplayName
                    Scope = "Application"
                    Subscription = "N/A"
                }
            }
        }
    }
}

# Export results to CSV
$results | Export-Csv -Path "GroupAccessReview.csv" -NoTypeInformation
Write-Host "Access review exported to GroupAccessReview.csv"
