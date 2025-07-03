Function Invoke-ExecBulkLicense {
    <#
    .SYNOPSIS
    Perform bulk license operations for users in Microsoft Entra ID (Azure AD)
    
    .DESCRIPTION
    Performs bulk license operations (add, remove, replace) for users in Microsoft Entra ID (Azure AD) across one or more tenants, supporting error handling and logging for each user.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Exec Bulk License
    Description: Performs bulk license operations (add, remove, replace) for users in Microsoft Entra ID (Azure AD) across one or more tenants, supporting error handling and logging for each user. Handles grouping by tenant and supports removing all licenses.
    Tags: Identity,Licenses,Bulk,Azure AD,Entra ID
    Parameter: Body (array) [body] - Array of user license operation objects, each containing userIds, LicenseOperation, RemoveAllLicenses, Licenses, tenantFilter
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of status messages for each user
    Response: On success: Array of success messages for each user
    Response: On error: Array of error messages for each user
    Example: {
      "Results": [
        "Successfully processed licenses for user john.doe@contoso.com",
        "Failed to process licenses for user jane.smith@contoso.com. Error: [error details]"
      ]
    }
    Error: Returns error details if the operation fails for any user.
    #>
    [CmdletBinding()]
    param (
        $Request,
        $TriggerMetadata
    )

    $APIName = $TriggerMetadata.FunctionName
    $Results = [System.Collections.Generic.List[string]]::new()
    $StatusCode = [HttpStatusCode]::OK

    try {
        $UserRequests = $Request.Body
        $TenantGroups = $UserRequests | Group-Object -Property tenantFilter

        foreach ($TenantGroup in $TenantGroups) {
            $TenantFilter = $TenantGroup.Name
            $TenantRequests = $TenantGroup.Group
            $AllUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?&`$select=id,userPrincipalName,assignedLicenses" -tenantid $TenantFilter
            $UserLookup = @{}
            foreach ($User in $AllUsers) {
                $UserLookup[$User.id] = $User
            }

            # Process each user request
            foreach ($UserRequest in $TenantRequests) {
                try {
                    $UserId = $UserRequest.userIds
                    $User = $UserLookup[$UserId]
                    $UserPrincipalName = $User.userPrincipalName
                    $LicenseOperation = $UserRequest.LicenseOperation
                    $RemoveAllLicenses = [bool]$UserRequest.RemoveAllLicenses
                    $Licenses = $UserRequest.Licenses | ForEach-Object { $_.value }
                    # Handle license operations
                    if ($LicenseOperation -eq 'Add' -or $LicenseOperation -eq 'Replace') {
                        $AddLicenses = $Licenses
                    }

                    if ($LicenseOperation -eq 'Remove' -and $RemoveAllLicenses) {
                        $RemoveLicenses = $User.assignedLicenses.skuId
                    } elseif ($LicenseOperation -eq 'Remove') {
                        $RemoveLicenses = $Licenses
                    } elseif ($LicenseOperation -eq 'Replace') {
                        $RemoveReplace = $User.assignedLicenses.skuId
                        if ($RemoveReplace) { Set-CIPPUserLicense -UserId $UserId -TenantFilter $TenantFilter -RemoveLicenses $RemoveReplace }
                    } elseif ($RemoveAllLicenses) {
                        $RemoveLicenses = $User.assignedLicenses.skuId
                    }
                    #todo: Actually build bulk support into set-cippuserlicense.
                    $TaskResults = Set-CIPPUserLicense -UserId $UserId -TenantFilter $TenantFilter -AddLicenses $AddLicenses -RemoveLicenses $RemoveLicenses

                    $Results.Add($TaskResults)
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Successfully processed licenses for user $UserPrincipalName" -Sev 'Info'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Results.Add("Failed to process licenses for user $($UserRequest.userIds). Error: $($ErrorMessage.NormalizedError)")
                    Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to process licenses for user $($UserRequest.userIds). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }

        $Body = @{
            Results = @($Results)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Results = @("Failed to process bulk license operation: $($ErrorMessage.NormalizedError)")
        }
        Write-LogMessage -API $APIName -message "Failed to process bulk license operation: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    # Return response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
