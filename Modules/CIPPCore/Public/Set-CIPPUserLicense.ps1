function Set-CIPPUserLicense {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter()][array]$AddLicenses = @(),
        [Parameter()][array]$RemoveLicenses = @(),
        $Headers,
        $APIName = 'Set User License'
    )

    # Build the addLicenses array
    $AddLicensesArray = foreach ($license in $AddLicenses) {
        @{
            'disabledPlans' = @()
            'skuId'         = $license
        }
    }

    # Build the LicenseBody hashtable
    $LicenseBody = @{
        'addLicenses'    = @($AddLicensesArray)
        'removeLicenses' = @($RemoveLicenses) ? @($RemoveLicenses) : @()
    }

    # Convert the LicenseBody to JSON
    $LicenseBodyJson = ConvertTo-Json -InputObject $LicenseBody -Depth 10 -Compress

    Write-Host "License body JSON: $LicenseBodyJson"

    try {
        try {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserId/assignLicense" -tenantid $TenantFilter -type POST -body $LicenseBodyJson -Verbose
        } catch {
            # Handle if the error is due to missing usage location
            if ($_.Exception.Message -like '*invalid usage location*') {
                $Table = Get-CippTable -tablename 'UserSettings'
                $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq 'allUsers'"
                if ($UserSettings) { $DefaultUsageLocation = (ConvertFrom-Json $UserSettings.JSON -Depth 5 -ErrorAction SilentlyContinue).usageLocation.value }
                $DefaultUsageLocation ??= 'US' # Fallback to US if not set

                $UsageLocationJson = ConvertTo-Json -InputObject @{'usageLocation' = $DefaultUsageLocation } -Depth 5 -Compress
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserId" -tenantid $TenantFilter -type PATCH -body $UsageLocationJson -Verbose
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Set usage location for user $UserId to $DefaultUsageLocation" -Sev 'Info'
                # Retry assigning the license
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserId/assignLicense" -tenantid $TenantFilter -type POST -body $LicenseBodyJson -Verbose
            } else {
                throw $_
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign the license. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to assign the license. $($ErrorMessage.NormalizedError)"
    }

    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned licenses to user $UserId. Added: $AddLicenses; Removed: $RemoveLicenses" -Sev 'Info'
    return "Successfully set licenses for $UserId. It may take 2–5 minutes before the changes become visible."
}
