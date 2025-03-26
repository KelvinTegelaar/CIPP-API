function Invoke-CIPPStandardPerUserMFA {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PerUserMFA
    .SYNOPSIS
        (Label) Enables per user MFA for all users.
    .DESCRIPTION
        (Helptext) Enables per user MFA for all users.
        (DocsDescription) Enables per user MFA for all users.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            High Impact
        ADDEDDATE
            2024-06-14
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=userPrincipalName,displayName,accountEnabled,perUserMfaState&`$filter=userType eq 'Member' and accountEnabled eq true and displayName ne 'On-Premises Directory Synchronization Service Account'&`$count=true" -tenantid $Tenant -ComplexFilter
    $UsersWithoutMFA = $GraphRequest | Where-Object -Property perUserMfaState -NE 'enforced' | Select-Object -Property userPrincipalName, displayName, accountEnabled, perUserMfaState

    If ($Settings.remediate -eq $true) {
        if (($UsersWithoutMFA | Measure-Object).Count -gt 0) {
            try {
                $MFAMessage = Set-CIPPPerUserMFA -TenantFilter $Tenant -userId @($UsersWithoutMFA.userPrincipalName) -State 'enforced'
                Write-LogMessage -API 'Standards' -tenant $tenant -message $MFAMessage -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enforce MFA for all users: $ErrorMessage" -sev Error
            }
        }
    }
    if ($Settings.alert -eq $true) {
        if (($UsersWithoutMFA.userPrincipalName | Measure-Object).Count -gt 0) {
            Write-StandardsAlert -message "The following accounts do not have Legacy MFA Enforced: $($UsersWithoutMFA.userPrincipalName -join ', ')" -object $UsersWithoutMFA -tenant $tenant -standardName 'PerUserMFA' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The following accounts do not have Legacy MFA Enforced: $($UsersWithoutMFA.userPrincipalName -join ', ')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No accounts do not have legacy per user MFA Enforced' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $State = $UsersWithoutMFA ? $UsersWithoutMFA : $true
        Set-CIPPStandardsCompareField -FieldName 'standards.PerUserMFA' -FieldValue $State -Tenant $tenant
        Add-CIPPBPAField -FieldName 'LegacyMFAUsers' -FieldValue $UsersWithoutMFA -StoreAs json -Tenant $tenant
    }
}
