<#
    .SYNOPSIS
        Updates the specified user objects in Entra ID with the corresponding attribute changes.
    
    .PARAMETER CSVFilePath
        Filename, in CSV format, containing the list of user accounts and attributes. Cannot be used with UserId.

    .PARAMETER UserId
        The UserId of an individual user object to update. Cannot be used with CSVFilePath.
    
    .PARAMETER Attribute 
        The Entra ID user object attribute to modify.

    .PARAMETER Value
        Used in conjunction with the Attribute parameter. The new contents to store in the attribute.

    .PARAMETER TenantId
        The Entra ID tenant ID to connect to. Useful for multi-tenant scenarios.

    .PARAMETER ClientId
        The client ID of an app registration to use for authentication instead of the default Microsoft Graph PowerShell app.

    .PARAMETER CertificateThumbprint
        The thumbprint of a certificate to use for app-only authentication. Must be paired with -ClientId.

    .PARAMETER NoWelcome
        Suppresses the Microsoft Graph connection banner.

    .PARAMETER Environment
        The Microsoft cloud environment to connect to. Defaults to the global endpoint.
        Valid values: Global, USGov, USGovDoD, China

    .EXAMPLE
        PS C:\> .\Update-UserAttributes.ps1 -CSVFilePath userlist.csv
        Updates the list of users and corresponding types from the input file. Must contain column "UserId" as primary key. All other columns must exactly match the attribute name in Entra ID.

    .NOTES
        Scott Pack
        scott.pack@gmail.com

        Last Update: 16 April 2026
        Version 1.0
#>

[CmdletBinding(DefaultParameterSetName="File")]
param(

    [Parameter(Mandatory = $true, ParameterSetName="File")][string]$CSVFilePath,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$UserId,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$Attribute,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$Value,
    [Parameter(Mandatory = $false)][string]$TenantId,
    [Parameter(Mandatory = $false)][string]$ClientId,
    [Parameter(Mandatory = $false)][string]$CertificateThumbprint,
    [Parameter(Mandatory = $false)][bool]$NoWelcome = $true,
    [Parameter(Mandatory = $false)][ValidateSet("Global","USGov","USGovDoD","China")][string]$Environment
)

Function Connect-Modules
{
    param([hashtable]$MgParams)

    Write-Information "Connecting modules(Microsoft Graph)...`n"

    $MgParams['Scopes']        = @("Directory.ReadWrite.All", "User.ReadWrite.All")
    $MgParams['ErrorAction']   = 'SilentlyContinue'
    $MgParams['ErrorVariable'] = 'ConnectionError'

    try
    {
        Connect-MgGraph @MgParams
        if($ConnectionError.Count -gt 0)
        {
            Write-Error $ConnectionError
            Exit
        }
    }
    catch
    {
        Write-Error $_.Exception.message
        Exit
    }
    Write-Information "Microsoft Graph PowerShell module is connected successfully" -ForegroundColor Cyan
}

Function Disconnect-Modules
{
    Disconnect-MgGraph -ErrorAction SilentlyContinue|  Out-Null
    Exit
}


$mgParams = @{}
if ($PSBoundParameters.ContainsKey('TenantId'))             { $mgParams['TenantId']             = $TenantId }
if ($PSBoundParameters.ContainsKey('ClientId'))             { $mgParams['ClientId']             = $ClientId}
if ($PSBoundParameters.ContainsKey('CertificateThumbprint')){ $mgParams['CertificateThumbprint']= $CertificateThumbprint }
if ($PSBoundParameters.ContainsKey('Environment'))          { $mgParams['Environment']          = $Environment}
$mgParams['NoWelcome'] = $NoWelcome

Connect-Modules -MgParams $mgParams

# Since I'm using naive input detection let's define the Account list now
$AccountList = @()

if($CSVFilePath)
{
    $CSVFilePath = $CSVFilePath.Trim()

    # Import the CSV file into an array of objects if provided
    try
    {
        $csvImportData = Import-Csv -Path $CSVFilePath
    }
    catch
    {
        Write-Error $_.Exception.Message
        Exit
    }

    # Run through the imported CSV data and builds the list of updates
    foreach ($item in $csvImportData)
    {
        $tempHash = @{}
        $item.psobject.properties | ForEach-Object { $tempHash[$_.Name.Trim("'")] = $_.Value.Trim("'") }
        $AccountList += $tempHash
    }
}
elseif($UserId)
{
    # When working with only one user let's quick and dirty build the array as if we had a single entry CSV import. Only supports a single attribute update at a time but hey, it works and is easy to use for quick updates without needing to build a CSV file.
    $AccountList += @{
        'UserId'             = $UserId
        $Attribute           = $Value
    }
}


Foreach( $account in $AccountList)
{
    Write-Information "Processing", $account['UserId']

    # Check to see if the manager is being updated since that requires a separate process
    if($account['Manager'])
    {
        $ManagerId = (Get-MgUser -UserId $account['Manager']).Id
        $NewManager = @{
            "@odata.id"="https://graph.microsoft.com/v1.0/users/$($ManagerId)"
        }

        try
        {
            Set-MgUserManagerByRef -UserId $account['UserId'] -BodyParameter $NewManager
        }
        catch
        {
            Write-Error $_.Exception.Message
        }

        #Remove the Manager field before continuing to process
        $account.Remove('Manager')
    }

    try
    {
        # Convert account psobject to a hashtable for splatting. Kind of gross, but is overall clean
        $accountSplattable = $account | ConvertTo-Json | ConvertFrom-Json  -AsHashtable
        Update-MgUser @accountSplattable
    }
    catch
    {
        Write-Error $_.Exception.Message
    }

}

Disconnect-Modules
