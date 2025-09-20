function Invoke-CIPPStandardPasswordExpireDisabled {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PasswordExpireDisabled
    .SYNOPSIS
        (Label) Do not expire passwords
    .DESCRIPTION
        (Helptext) Disables the expiration of passwords for the tenant by setting the password expiration policy to never expire for any user.
        (DocsDescription) Sets passwords to never expire for tenant, recommended to use in conjunction with secure password requirements.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS"
            "PWAgePolicyNew"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2021-11-16
        POWERSHELLEQUIVALENT
            Update-MgDomain
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the PasswordExpireDisabled state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $DomainsWithoutPassExpire = $GraphRequest |
        Where-Object { $_.isVerified -eq $true -and $_.passwordValidityPeriodInDays -ne 2147483647 }

    if ($Settings.remediate -eq $true) {

        if ($DomainsWithoutPassExpire) {
            $DomainsWithoutPassExpire | ForEach-Object {
                try {
                    if ( $null -eq $_.passwordNotificationWindowInDays ) {
                        $Body = '{"passwordValidityPeriodInDays": 2147483647, "passwordNotificationWindowInDays": 14 }'
                        Write-Host "PasswordNotificationWindowInDays is null for $($_.id). Setting to the default of 14 days."
                    } else {
                        $Body = '{"passwordValidityPeriodInDays": 2147483647 }'
                    }
                    New-GraphPostRequest -type Patch -tenantid $Tenant -uri "https://graph.microsoft.com/v1.0/domains/$($_.id)" -body $Body
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabled Password Expiration for $($_.id)." -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Password Expiration for $($_.id). Error: $ErrorMessage" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is already disabled for all $($GraphRequest.Count) domains." -sev Info
        }

    }

    if ($Settings.alert -eq $true) {
        if ($DomainsWithoutPassExpire) {
            Write-StandardsAlert -message "Password Expiration is not disabled for the following $($DomainsWithoutPassExpire.Count) domains: $($DomainsWithoutPassExpire.id -join ', ')" -object $DomainsWithoutPassExpire -tenant $tenant -standardName 'PasswordExpireDisabled' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is not disabled for the following $($DomainsWithoutPassExpire.Count) domains: $($DomainsWithoutPassExpire.id -join ', ')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is disabled for all $($GraphRequest.Count) domains." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'PasswordExpireDisabled' -FieldValue $DomainsWithoutPassExpire -StoreAs json -Tenant $tenant
        if ($DomainsWithoutPassExpire) {
            $FieldValue = $DomainsWithoutPassExpire
        } else {
            $FieldValue = $true
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PasswordExpireDisabled' -FieldValue $FieldValue -Tenant $tenant
    }
}
