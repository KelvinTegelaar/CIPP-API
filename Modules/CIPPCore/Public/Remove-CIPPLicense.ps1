function Remove-CIPPLicense {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = 'Remove License',
        $TenantFilter
    )

    try {
        $ConvertTable = Import-Csv Conversiontable.csv
        $CurrentLicenses = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter).assignedlicenses.skuid
        $ConvertedLicense = $(($ConvertTable | Where-Object { $_.guid -in $CurrentLicenses }).'Product_Display_Name' | Sort-Object -Unique) -join ','
        $LicensesToRemove = if ($CurrentLicenses) { ConvertTo-Json @( $CurrentLicenses) } else { '[]' }
        $LicenseBody = '{"addLicenses": [], "removeLicenses": ' + $LicensesToRemove + '}'
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/assignlicense" -tenantid $tenantFilter -type POST -body $LicenseBody -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed licenses for $($username): $ConvertedLicense" -Sev 'Info' -tenant $TenantFilter
        return "Removed licenses for $($Username): $ConvertedLicense"

    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not remove license for $username" -Sev 'Error' -tenant $TenantFilter
        return "Could not remove license for $($username). Error: $($_.Exception.Message)"
    }
}
