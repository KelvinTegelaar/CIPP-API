function Invoke-CIPPStandardPasswordExpireDisabled {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $Tenant
    If ($Settings.remediate) {
        try {
            $GraphRequest | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647' | ForEach-Object {
                New-GraphPostRequest -type Patch -tenantid $Tenant -uri "https://graph.microsoft.com/beta/domains/$($_.id)" -body '{"passwordValidityPeriodInDays": 2147483647 }'
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Password Expiration' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Password Expiration. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        $GraphRequest | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647' | ForEach-Object {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is not disabled for $($_.name)" -sev Alert
        }
    }
    if ($Settings.report) {
        $DomainswithoutPassExpire = $GraphRequest | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647'
        Add-CIPPBPAField -FieldName 'PasswordExpireDisabled' -FieldValue $DomainswithoutPassExpire -StoreAs json -Tenant $tenant
        
    }
}
