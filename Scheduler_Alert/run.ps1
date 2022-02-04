param($tenant)

try {
    $Alerts = Get-Content ".\Cache_Scheduler\$tenant.alert.json" | ConvertFrom-Json
    switch ($Alerts) {

        { $_."AdminPassword" -eq $true } {}
        { $_."DefenderMalware" -eq $true } {}
        { $_."DefenderStatus" -eq $true } {}
        { $_."DisableRestart" -eq $true } {}
        { $_."InstallAsSystem" -eq $true } {}
        { $_."MFAAdmins" -eq $true } {}
        { $_."MFAAlertUsers" -eq $true } {}
        { $_."NewApprovedApp" -eq $true } {}
        { $_."NewGA" -eq $true } {}
        { $_."NewRole" -eq $true } {}
        { $_."QuotaUsed" -eq $true } {}
        { $_."UnusedLicenses" -eq $true } {}
   
    }

    Log-request -API "Scheduler" -tenant $tenant -message "Collecting alerts for $($tenant)" -sev debug

}
catch {
    Log-request -API "Scheduler" -tenant $tenant -message "Failed to get alerts for $($tenant) Error: $($_.exception.message)" -sev Error
}