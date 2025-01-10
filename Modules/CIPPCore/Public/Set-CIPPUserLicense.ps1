function Set-CIPPUserLicense {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$UserId,
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter()][array]$AddLicenses = @(),
        [Parameter()][array]$RemoveLicenses = @()
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
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserId/assignLicense" -tenantid $TenantFilter -type POST -body $LicenseBodyJson -Verbose
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $TenantFilter -message "Failed to assign the license. Error: $_" -Sev 'Error'
        throw "Failed to assign the license. $_"
    }

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $TenantFilter -message "Assigned licenses to user $UserId. Added: $AddLicenses; Removed: $RemoveLicenses" -Sev 'Info'
    return 'Set licenses successfully'
}
