param($tenant)

try {

    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet "Get-OrganizationConfig").AutoExpandingArchiveEnabled
    if (!$currentstate) {
        New-ExoRequest -tenantid $Tenant -cmdlet "Set-OrganizationConfig" -cmdParams @{AutoExpandingArchive = $true }
        Write-LogMessage -API "Standards" -tenant $tenant -message "Added Auto Expanding Archive." -sev Info
    }

}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to apply Auto Expanding Archives Error: $($_.exception.message)" -sev Error
}