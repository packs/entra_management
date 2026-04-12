<#
.SYNOPSIS
    Populates Entra ID with dummy users and groups from CSV files.

.DESCRIPTION
    Users are created as disabled accounts with a fixed unusable password.
    Column headers in the users CSV must match New-MgUser parameter names.
    Groups CSV supports a semicolon-delimited Members column of UPNs.
    A Manager column (UPN) is supported in the users CSV and applied after
    user creation via Set-MgUserManagerByRef.

.PARAMETER UsersCSV
    Path to the users CSV file.

.PARAMETER GroupsCSV
    Path to the groups CSV file.

.PARAMETER TenantId
    Entra ID Tenant ID or domain. If omitted, Connect-MgGraph prompts interactively.

.EXAMPLE
    .\New-EntraDummyData.ps1 -UsersCSV .\users.csv -GroupsCSV .\groups.csv -TenantId "contoso.onmicrosoft.com"

.NOTES
    Requires: Microsoft.Graph PowerShell SDK
    Install:  Install-Module Microsoft.Graph -Scope CurrentUser
    Scopes:   User.ReadWrite.All, Group.ReadWrite.All
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$UsersCSV,

    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$GroupsCSV,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Columns handled by the script and not passed directly to New-MgUser
$RESERVED_COLUMNS = @('Members', 'Groups', 'Manager')

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')]$Level = 'INFO')
    $colour = @{ INFO = 'Cyan'; WARN = 'Yellow'; ERROR = 'Red' }[$Level]
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')][$Level] $Message" -ForegroundColor $colour
}

#region --- Connect -----------------------------------------------------------

if (-not (Get-Module -ListAvailable -Name 'Microsoft.Graph')) {
    throw "Microsoft.Graph module not found. Run: Install-Module Microsoft.Graph -Scope CurrentUser"
}

$connectParams = @{ Scopes = @('User.ReadWrite.All', 'Group.ReadWrite.All') }
if ($TenantId) { $connectParams['TenantId'] = $TenantId }

Connect-MgGraph @connectParams
Write-Log "Connected as $((Get-MgContext).Account) to tenant $((Get-MgContext).TenantId)"

#endregion

# Wrapping whole process in a try/finally to ensure we disconnect from Graph even if errors occur
try { 
    #region --- Process Users -----------------------------------------------------

    $createdUsers = @{}   # UPN -> MgUser, reused during manager and group membership assignment

    if ($UsersCSV) {
        Write-Log "Loading users from '$UsersCSV'..."
        $rows = Import-Csv -Path $UsersCSV

        # --- Pass 1: Create all users first so managers can be resolved in Pass 2 ---
        foreach ($row in $rows) {
            $upn = $row.UserPrincipalName
            if (-not $upn) {
                Write-Log "Row missing UserPrincipalName — skipping." -Level WARN
                continue
            }

            # All dummy users: disabled, with a fixed non-functional password
            $params = @{
                AccountEnabled  = $false
                PasswordProfile = @{
                    Password                      = [System.Guid]::NewGuid().ToString()
                    ForceChangePasswordNextSignIn = $false
                }
            }

            foreach ($prop in $row.PSObject.Properties) {
                if ($prop.Name -in $RESERVED_COLUMNS) { continue }
                if ($prop.Name -eq 'AccountEnabled')  { continue }  # always forced to $false
                if ([string]::IsNullOrWhiteSpace($prop.Value)) { continue }
                $params[$prop.Name] = $prop.Value
            }

            try {
                $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue

                if ($existing) {
                    Write-Log "User '$upn' already exists — skipping." -Level WARN
                    $createdUsers[$upn] = $existing
                } else {
                    $user = New-MgUser @params
                    $createdUsers[$upn] = $user
                    Write-Log "Created user '$upn'"
                }
            } catch {
                Write-Log "Failed to create user '$upn': $_" -Level ERROR
            }
        }

        # --- Pass 2: Assign managers after all users exist in the directory ---
        foreach ($row in $rows) {
            $upn = $row.UserPrincipalName
            if (-not $upn -or -not $createdUsers.ContainsKey($upn)) { continue }
            if (-not ($row.PSObject.Properties['Manager']) -or [string]::IsNullOrWhiteSpace($row.Manager)) { continue }

            $managerUpn = $row.Manager.Trim()

            # Resolve manager from cache first, then fall back to a Graph lookup
            # so that managers defined elsewhere in the tenant are also supported
            $managerObj = if ($createdUsers.ContainsKey($managerUpn)) {
                $createdUsers[$managerUpn]
            } else {
                Get-MgUser -Filter "userPrincipalName eq '$managerUpn'" -ErrorAction SilentlyContinue
            }

            if (-not $managerObj) {
                Write-Log "Manager '$managerUpn' not found for '$upn' — skipping." -Level WARN
                continue
            }

            try {
                $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($managerObj.Id)" }
                Set-MgUserManagerByRef -UserId $createdUsers[$upn].Id -BodyParameter $ref
                Write-Log "Set manager '$managerUpn' on '$upn'"
            } catch {
                Write-Log "Failed to set manager '$managerUpn' on '$upn': $_" -Level ERROR
            }
        }

        Write-Log "Users complete. Processed: $($createdUsers.Count)"
    }

    #endregion

    #region --- Process Groups ----------------------------------------------------

    if ($GroupsCSV) {
        Write-Log "Loading groups from '$GroupsCSV'..."
        $rows = Import-Csv -Path $GroupsCSV

        foreach ($row in $rows) {
            $displayName = $row.DisplayName
            if (-not $displayName) {
                Write-Log "Row missing DisplayName — skipping." -Level WARN
                continue
            }

            $isMicrosoft365 = ($row.PSObject.Properties['GroupTypes'] -and $row.GroupTypes -ieq 'Microsoft365')

            $groupParams = @{
                DisplayName     = $displayName
                MailNickname    = $row.MailNickname
                SecurityEnabled = -not $isMicrosoft365
                MailEnabled     = $isMicrosoft365
                GroupTypes      = if ($isMicrosoft365) { @('Unified') } else { @() }
            }
            if ($row.PSObject.Properties['Description'] -and $row.Description) {
                $groupParams['Description'] = $row.Description
            }

            try {
                $existing = Get-MgGroup -Filter "displayName eq '$displayName'" -ErrorAction SilentlyContinue

                $group = if ($existing) {
                    Write-Log "Group '$displayName' already exists — skipping creation." -Level WARN
                    $existing
                } else {
                    $g = New-MgGroup @groupParams
                    Write-Log "Created group '$displayName'"
                    $g
                }

                if ($row.PSObject.Properties['Members'] -and $row.Members) {
                    foreach ($memberUpn in ($row.Members -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                        try {
                            $memberObj = if ($createdUsers.ContainsKey($memberUpn)) {
                                $createdUsers[$memberUpn]
                            } else {
                                Get-MgUser -Filter "userPrincipalName eq '$memberUpn'" -ErrorAction SilentlyContinue
                            }

                            if (-not $memberObj) {
                                Write-Log "  Member '$memberUpn' not found — skipping." -Level WARN
                                continue
                            }

                            $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($memberObj.Id)" }
                            New-MgGroupMember -GroupId $group.Id -BodyParameter $ref
                            Write-Log "  Added '$memberUpn' to '$displayName'"
                        } catch {
                            Write-Log "  Failed to add '$memberUpn' to '$displayName': $_" -Level ERROR
                        }
                    }
                }

            } catch {
                Write-Log "Failed to process group '$displayName': $_" -Level ERROR
            }
        }

        Write-Log "Groups complete."
    }
    #endregion
    
} finally {
    Write-Log "Cleaning up Graph connections..."
    Disconnect-MgGraph  

}

Write-Log "Done."