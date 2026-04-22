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
    [string[]]$PrincipalDisplayNames,
    [string[]]$SubscriptionIds,
    [string]$OutputPath = (Get-Location).Path,

    # Authentication parameters (optional - will use existing context if not provided)
    [string]$TenantId,
    [string]$ClientId,
    [System.Security.SecureString]$ClientSecret,
    [string]$CertificateThumbprint,
    [string]$CertificateName,
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$ServicePrincipal,
    [string]$Environment,
    [bool]$NoWelcome = $true
)

# Script-scoped connection state tracker
$script:ConnectedServices = @{
    MgGraph  = $false
    AzAccount = $false
}



function Connect-Modules {


    param([hashtable]$ModuleParams)

    $mgParams = @{}
    $mgParams['Scopes']        = @("Directory.ReadWrite.All", "User.ReadWrite.All")
    $mgParams['ErrorAction']   = 'SilentlyContinue'
    $mgParams['ErrorVariable'] = 'ConnectionError'

    # --- Connect-MgGraph ---
    if ($ModuleParams.ContainsKey('NoWelcome'))            { $mgParams['NoWelcome']            = $NoWelcome }
    if ($ModuleParams.ContainsKey('TenantId'))             { $mgParams['TenantId']             = $TenantId }
    if ($ModuleParams.ContainsKey('ClientId'))             { $mgParams['ClientId']             = $ClientId }
    if ($ModuleParams.ContainsKey('ClientSecret'))         { $mgParams['ClientSecret']         = $ClientSecret }
    if ($ModuleParams.ContainsKey('CertificateThumbprint')){ $mgParams['CertificateThumbprint'] = $CertificateThumbprint }
    if ($ModuleParams.ContainsKey('CertificateName'))      { $mgParams['CertificateName']      = $CertificateName }

    try {
        Connect-MgGraph @mgParams -ErrorAction Stop
        $script:ConnectedServices.MgGraph = $true
        Write-Host "Connected to Microsoft Graph."
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        return
    }

    # --- Connect-AzAccount ---
    $azParams = @{}
    if ($ModuleParams.ContainsKey('TenantId'))    { $azParams['TenantId']    = $TenantId }
    if ($ModuleParams.ContainsKey('Credential'))  { $azParams['Credential']  = $Credential }
    if ($ModuleParams.ContainsKey('ServicePrincipal') -and $ServicePrincipal) { $azParams['ServicePrincipal'] = $true }
    if ($ModuleParams.ContainsKey('Environment')) { $azParams['Environment']  = $Environment }
    if ($ModuleParams.ContainsKey('CertificateThumbprint')) { $azParams['CertificateThumbprint'] = $CertificateThumbprint }
    if ($ModuleParams.ContainsKey('ApplicationId')) { $azParams['ApplicationId'] = $ApplicationId }

    try {
        # Connect to Azure without showing warnings (e.g., about missing context) and stop on errors. A little gross, but the best analog to Graph's NoWelcome.
        Connect-AzAccount @azParams -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        $script:ConnectedServices.AzAccount = $true
        Write-Host "Connected to Azure."
    }
    catch {
        Write-Error "Failed to connect to Azure: $_"
        return
    }
}

function Disconnect-Modules {
    [CmdletBinding()]
    param ()

    if ($script:ConnectedServices.MgGraph) {
        try {
            Disconnect-MgGraph -ErrorAction Stop
            $script:ConnectedServices.MgGraph = $false
            Write-Host "Disconnected from Microsoft Graph."
        }
        catch {
            Write-Warning "Failed to disconnect from Microsoft Graph: $_"
        }
    }

    if ($script:ConnectedServices.AzAccount) {
        try {
            Disconnect-AzAccount -ErrorAction Stop | Out-Null
            $script:ConnectedServices.AzAccount = $false
            Write-Host "Disconnected from Azure."
        }
        catch {
            Write-Warning "Failed to disconnect from Azure: $_"
        }
    }
}

function Get-AzureRoleAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][object[]]$Subscriptions,
        [Parameter()][string[]]$PrincipalDisplayNames
    )

    $roleResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Iterate through each subscription that's been passed
    foreach ($sub in $Subscriptions) {
        Write-Verbose "Processing subscription '$($sub.Name)' ($($sub.Id))..."
        try {
            Set-AzContext -SubscriptionId $sub.Id -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "Could not set context for subscription '$($sub.Name)' ($($sub.Id)): $_"
            continue
        }

        try {
            $roleAssignments = Get-AzRoleAssignment -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not retrieve role assignments for subscription '$($sub.Name)' ($($sub.Id)): $_"
            continue
        }

        # Filter to specified principals if provided
        if ($PSBoundParameters.ContainsKey('PrincipalDisplayNames')) {
            write-host "Filtering role assignments for subscription '$($sub.Name)' by $principalDisplayNames...."
            $roleAssignments = $roleAssignments | Where-Object {
                $PrincipalDisplayNames -contains $_.DisplayName
            }
        }

        Write-Host "Found $($roleAssignments.Count) role assignment(s) in subscription '$($sub.Name)' after filtering by principal display names."

        foreach ($assignment in $roleAssignments) {
            # Determine scope level
            $scopeLevel = switch -Regex ($assignment.Scope) {
                '\/providers\/Microsoft\.Management\/managementGroups\/' { 'ManagementGroup' }
                '^\/subscriptions\/[^\/]+$'                              { 'Subscription'    }
                '\/resourceGroups\/[^\/]+$'                              { 'ResourceGroup'   }
                '\/resourceGroups\/.+\/'                                 { 'Resource'        }
                default                                                  { 'Unknown'         }
            }

            try {
                $roleDef = Get-AzRoleDefinition -Id $assignment.RoleDefinitionId -ErrorAction Stop
                $roleName = $roleDef.Name
            }
            catch {
                Write-Warning "Could not resolve role definition '$($assignment.RoleDefinitionId)' in subscription '$($sub.Name)': $_"
                $roleName = $assignment.RoleDefinitionId
            }

            $roleResults.Add([PSCustomObject]@{
                PrincipalDisplayName = $assignment.DisplayName
                PrincipalObjectId    = $assignment.ObjectId
                PrincipalType        = $assignment.ObjectType
                Type                 = 'Azure Role'
                RoleOrApp            = $roleName
                Scope                = $assignment.Scope
                ScopeLevel           = $scopeLevel
                Subscription         = $sub.Name
                SubscriptionId       = $sub.Id
            })
        }
    }

    Write-Verbose "Completed processing subscriptions. Total role assignments found: $($roleResults.Count)"
    return $roleResults
}


Function Main
{
    param([hashtable]$BoundParams)

    $mgParams = @{}
    if ($BoundParams.ContainsKey('TenantId'))             { $mgParams['TenantId']             = $TenantId }
    if ($BoundParams.ContainsKey('ClientId'))             { $mgParams['ClientId']             = $ClientId}
    if ($BoundParams.ContainsKey('ClientSecret'))         { $mgParams['ClientSecret']         = $ClientSecret}
    if ($BoundParams.ContainsKey('CertificateThumbprint')){ $mgParams['CertificateThumbprint']= $CertificateThumbprint }
    if ($BoundParams.ContainsKey('CertificateName'))      { $mgParams['CertificateName']      = $CertificateName }
    if ($BoundParams.ContainsKey('Environment'))          { $mgParams['Environment']          = $Environment}
    $mgParams['NoWelcome'] = $NoWelcome

    Connect-Modules -ModuleParams $mgParams

    # Fetch and, if requested, filter subscriptions
    $allSubscriptions = Get-AzSubscription
    if ($SubscriptionIds -and $SubscriptionIds.Count -gt 0) {
        $subscriptions = $allSubscriptions | Where-Object { $SubscriptionIds -contains $_.Id }
        $missing = $SubscriptionIds | Where-Object { $allSubscriptions.Id -notcontains $_ }
        if ($missing) {
            Write-Warning "The following subscription IDs were not found or are not accessible: $($missing -join ', ')"
        }
    } else {
        $subscriptions = $allSubscriptions
    }

    Write-Verbose "Found $($subscriptions.Count) subscription(s) to process."

    # Build parameter set for Azure role retrieval for splatting, in case principal filtering is not used
    $azureParams = @{}
    if ($BoundParams.ContainsKey('PrincipalDisplayNames'))  { $azureParams['PrincipalDisplayNames'] = $PrincipalDisplayNames }

    $results = Get-AzureRoleAssignments -Subscriptions $subscriptions @azureParams

    # Let's finally write out the results
    if ($results.Count -eq 0) {
        Write-Warning "No role assignments found. No output file written."
    }
    else {
        $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
        $filename   = "AzureRoleAssignments_$timestamp.csv"
        $outputFile = Join-Path -Path $OutputPath -ChildPath $filename

        try {
            $results | Export-Csv -Path $outputFile -NoTypeInformation -ErrorAction Stop
            Write-Host "Role assignments exported to: $outputFile"
        }
        catch {
            Write-Error "Failed to write output file '$outputFile': $_"
        }
    }

    Disconnect-Modules
}


Main -BoundParams $PSBoundParameters