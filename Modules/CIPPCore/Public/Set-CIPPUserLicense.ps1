function Set-CIPPUserLicense {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter()][array]$AddLicenses = @(),
        [Parameter()][array]$RemoveLicenses = @(),
        $Headers
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
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserId/assignLicense" -tenantid $TenantFilter -type POST -body $LicenseBodyJson -Verbose
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign the license. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to assign the license. $($ErrorMessage.NormalizedError)"
    }

    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned licenses to user $UserId. Added: $AddLicenses; Removed: $RemoveLicenses" -Sev 'Info'
    return 'Set licenses successfully'
}
