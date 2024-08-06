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
            "lowimpact"
            "CIS"
            "PWAgePolicyNew"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgDomain
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $Tenant
    $DomainswithoutPassExpire = $GraphRequest | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647'

    If ($Settings.remediate -eq $true) {

        if ($DomainswithoutPassExpire) {
            $DomainswithoutPassExpire | ForEach-Object {
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
        if ($DomainswithoutPassExpire) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is not disabled for the following $($DomainswithoutPassExpire.Count) domains: $($DomainswithoutPassExpire.id -join ', ')" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Password Expiration is disabled for all $($GraphRequest.Count) domains." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'PasswordExpireDisabled' -FieldValue $DomainswithoutPassExpire -StoreAs json -Tenant $tenant
    }
}
