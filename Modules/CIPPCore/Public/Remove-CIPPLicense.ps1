function Remove-CIPPLicense {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = "Remove License",
        $TenantFilter
    )

    try {
        $CurrentLicenses = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter).assignedlicenses.skuid
        $LicensesToRemove = if ($CurrentLicenses) { ConvertTo-Json @( $CurrentLicenses) } else { "[]" }
        $LicenseBody = '{"addLicenses": [], "removeLicenses": ' + $LicensesToRemove + '}'
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/assignlicense" -tenantid $tenantFilter -type POST -body $LicenseBody -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed license for $($username)" -Sev "Info" -tenant $TenantFilter
        Return "Removed current licenses: $(($ConvertTable | Where-Object { $_.guid -in $CurrentLicenses }).'Product_Display_Name' -join ',')"

    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not remove license for $username" -Sev "Error" -tenant $TenantFilter
        return "Could not remove license for $($username). Error: $($_.Exception.Message)"
    }
}
