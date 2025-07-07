function Invoke-ExecBulkLicense {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param ($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.Generic.List[string]]::new()


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
                    #todo: Actually build bulk support into Set-CIPPUserLicense.
                    $TaskResults = Set-CIPPUserLicense -UserId $UserId -TenantFilter $TenantFilter -AddLicenses $AddLicenses -RemoveLicenses $RemoveLicenses

                    $Results.Add($TaskResults)
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Successfully processed licenses for user $UserPrincipalName" -Sev 'Info'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Results.Add("Failed to process licenses for user $($UserRequest.userIds). Error: $($ErrorMessage.NormalizedError)")
                    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed to process licenses for user $($UserRequest.userIds). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results.Add("Failed to process bulk license operation: $($ErrorMessage.NormalizedError)")
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to process bulk license operation: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    # Return response
    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
