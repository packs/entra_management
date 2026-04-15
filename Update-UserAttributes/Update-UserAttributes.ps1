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

    .EXAMPLE
        PS C:\> .\Update-UserAttributes.ps1 -CSVFilePath userlist.csv
        Updates the list of users and corresponding types from the input file. Must contain column "UserId" as primary key. All other columns must exactly match the attribute name in Entra ID.

    .NOTES
        Scott Pack
        scott.pack@gmail.com

        Last Update: 26 November 2024
        Version 1.0
#>

[CmdletBinding(DefaultParameterSetName="File")]
param(

    [Parameter(Mandatory = $true, ParameterSetName="File")][string]$CSVFilePath,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$UserId,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$Attribute,
    [Parameter(Mandatory = $true, ParameterSetName="User")][string]$Value
)

Function Connect-Modules
{
    Write-Host "Connecting modules(Microsoft Graph)...`n"

    try
    {
        Connect-MgGraph -Scopes Directory.ReadWrite.All,User.ReadWrite.All -ErrorAction SilentlyContinue -Errorvariable ConnectionError -NoWelcome
        if($ConnectionError -ne $null)
        {
            Write-Host $ConnectionError -Foregroundcolor Red
            Exit
        }
    }
    catch
    {
        Write-Host $_.Exception.message -ForegroundColor Red
        Exit
    }
    Write-Host "Microsoft Graph PowerShell module is connected successfully" -ForegroundColor Cyan
}

Function Disconnect-Modules
{
    Disconnect-MgGraph -ErrorAction SilentlyContinue|  Out-Null
    Exit
}

Function Main
{
    Connect-Modules

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
            Write-Host $_.Exception.Message -ForegroundColor Red
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
        Write-Host "Processing", $account['UserId']

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
                Write-Host $_.Exception.Message -ForegroundColor Red
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
            Write-Host $_.Exception.Message -ForegroundColor Red
        }

    }

    Disconnect-Modules
}

Main
