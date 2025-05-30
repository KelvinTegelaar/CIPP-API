function Invoke-CIPPStandardDisableGuests {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableGuests
    .SYNOPSIS
        (Label) Disable Guest accounts that have not logged on for 90 days
    .DESCRIPTION
        (Helptext) Blocks login for guest users that have not logged in for 90 days
        (DocsDescription) Blocks login for guest users that have not logged in for 90 days
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-10-20
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableGuests'

    $90Days = (Get-Date).AddDays(-90).ToUniversalTime()
    $Lookup = $90Days.ToString('o')
    $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true &`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime,externalUserState" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant |
        Where-Object { $_.signInActivity.lastSuccessfulSignInDateTime -le $90Days }

    $RecentlyReactivatedUsers = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant |
        ForEach-Object { $_.targetResources[0].id } | Select-Object -Unique)

    $GraphRequest = $GraphRequest | Where-Object { -not ($RecentlyReactivatedUsers -contains $_.id) }

    If ($Settings.remediate -eq $true) {
        if ($GraphRequest.Count -gt 0) {
            foreach ($guest in $GraphRequest) {
                try {
                    New-GraphPostRequest -type Patch -tenantid $tenant -uri "https://graph.microsoft.com/beta/users/$($guest.id)" -body '{"accountEnabled":"false"}'
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Disabling guest $($guest.UserPrincipalName) ($($guest.id))" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable guest $($guest.UserPrincipalName) ($($guest.id)): $ErrorMessage" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No guests accounts with a login longer than 90 days ago.' -sev Info
        }

    }
    if ($Settings.alert -eq $true) {

        if ($GraphRequest.Count -gt 0) {
            Write-StandardsAlert -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -object $GraphRequest -tenant $tenant -standardName 'DisableGuests' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No guests accounts with a login longer than 90 days ago.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled
        $state = $filtered ? $filtered : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableGuests' -FieldValue $state -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $filtered -StoreAs json -Tenant $tenant
    }
}
