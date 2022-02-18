param($tenant)

try {
    if ($Tenant.tag -eq "AllTenants") {
        $Alerts = Get-Content ".\Cache_Scheduler\AllTenants.alert.json" | ConvertFrom-Json
    }
    else {
        $Alerts = Get-Content ".\Cache_Scheduler\$($tenant.tenant).alert.json" | ConvertFrom-Json
    }
    #Does not work yet.
    $ShippedAlerts = switch ($Alerts) {
        { $_."AdminPassword" -eq $true } {
            New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" -tenantid $($tenant.tenant) | ForEach-Object { 
                $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/users/$($_.PrincipalID)/`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($tenant.tenant)
                if ($LastChanges.LastPasswordChangeDateTime -lt (Get-Date).AddDays(-300)) { Write-Host "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours" }
            }
        }
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
    Write-Host "Shipped in switch."
    Write-Host $ShippedAlerts

    #EmailAllAlertsInNiceTable
    Log-request -API "Scheduler" -tenant $($tenant.tenant) -message "Collecting alerts for $($($tenant.tenant))" -sev debug

}
catch {
    Log-request -API "Scheduler" -tenant $($tenant.tenant) -message "Failed to get alerts for $($($tenant.tenant)) Error: $($_.exception.message)" -sev Error
}