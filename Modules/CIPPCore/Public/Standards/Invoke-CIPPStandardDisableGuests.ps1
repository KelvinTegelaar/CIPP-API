function Invoke-CIPPStandardDisableGuests {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $lookup = (Get-Date).AddDays(-90).ToUniversalTime().ToString('o')
    $GraphRequest = New-GraphgetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=(signInActivity/lastSignInDateTime le $lookup)&`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant | Where-Object { $_.userType -EQ 'Guest' -and $_.AccountEnabled -EQ $true }

    If ($Settings.remediate) {
        try {
            foreach ($guest in $GraphRequest) {
                New-GraphPostRequest -type Patch -tenantid $tenant -uri "https://graph.microsoft.com/beta/users/$($guest.id)" -body '{"accountEnabled":"false"}'
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabling guest $($guest.UserPrincipalName) ($($guest.id))" -sev Info
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled guests accounts with a login longer than 90 days ago.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guests older than 90 days: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($GraphRequest) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No guests accounts with a login longer than 90 days ago.' -sev Info
        }
    }
    if ($Settings.report) {
        $filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $filtered -StoreAs json -Tenant $tenant
    }
}
