# Update-UserAttributes

A PowerShell script to update Entra ID user object attributes either for a single user or from a CSV batch file.

## Overview

`Update-UserAttributes.ps1` connects to Microsoft Graph, reads user update data, and applies attribute changes to Entra ID users.

## Location

- `Update-UserAttributes/Update-UserAttributes.ps1`

## Prerequisites

- Windows PowerShell or PowerShell Core
- `Microsoft.Graph` PowerShell module
- Permission to update user objects in Entra ID
- Access to Microsoft Graph with at least `Directory.Read.All` and `RoleManagement.Read.Directory` scopes

## Usage

### Update from CSV file

```powershell
.\
Update-UserAttributes.ps1 -CSVFilePath .\userlist.csv
```

- The CSV must contain a `UserId` column.
- Additional columns must match the exact Entra ID user attribute names.
- Each row updates the matching user with the provided attribute values.

### Update a single user attribute

```powershell
.\
Update-UserAttributes.ps1 -UserId user@domain.com -Attribute jobTitle -Value "Marketing Manager"
```

- Use `-UserId` for a single user.
- `-Attribute` is the Entra ID user property to update.
- `-Value` is the new value to set.

## Supported Scenarios

- Batch updates via CSV import
- Single user attribute updates
- Special handling for updating the `Manager` attribute via Graph manager reference API

## CSV Format Example

```csv
UserId,jobTitle,department,Manager
user1@domain.com,Sales Director,Sales,manager@domain.com
user2@domain.com,Engineer,Development,manager@domain.com
```

## Output

- The script accepts an optional `-Output` parameter for output directory path, but the current implementation does not write logs to it.

## Notes

- The script uses `Connect-MgGraph` and `Disconnect-MgGraph` to manage Microsoft Graph authentication.
- If the CSV import fails, the script will display the error and exit.
- The script is authored by Scott Pack and was last updated on 26 November 2024.
