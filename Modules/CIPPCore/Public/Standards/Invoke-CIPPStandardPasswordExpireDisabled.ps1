function Invoke-CIPPStandardPasswordExpireDisabled {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $Tenant
    $DomainswithoutPassExpire = $GraphRequest | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647'

    If ($Settings.remediate) {

        if ($DomainswithoutPassExpire) {
            $DomainswithoutPassExpire | ForEach-Object {
                try {
                    New-GraphPostRequest -type Patch -tenantid $Tenant -uri "https://graph.microsoft.com/beta/domains/$($_.id)" -body '{"passwordValidityPeriodInDays": 2147483647 }'
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled Password Expiration for $($_.id)." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Password Expiration for $($_.id). Error: $($_.exception.message)" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is already disabled for all $($GraphRequest.Count) domains." -sev Info
        }
    
    }

    if ($Settings.alert) {
        if ($DomainswithoutPassExpire) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is not disabled for the following $($DomainswithoutPassExpire.Count) domains: $($DomainswithoutPassExpire.id -join ', ')" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is disabled for all $($GraphRequest.Count) domains." -sev Info
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'PasswordExpireDisabled' -FieldValue $DomainswithoutPassExpire -StoreAs json -Tenant $tenant
    }
}