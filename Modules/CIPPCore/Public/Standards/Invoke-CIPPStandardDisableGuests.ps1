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
            "mediumimpact"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableGuests'

    $Lookup = (Get-Date).AddDays(-90).ToUniversalTime().ToString('o')
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=(signInActivity/lastSuccessfulSignInDateTime le $Lookup)&`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant | Where-Object { $_.userType -EQ 'Guest' -and $_.AccountEnabled -EQ $true }

    If ($Settings.remediate -eq $true) {

        if ($GraphRequest) {
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

        if ($GraphRequest) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No guests accounts with a login longer than 90 days ago.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $filtered -StoreAs json -Tenant $tenant
    }
}
