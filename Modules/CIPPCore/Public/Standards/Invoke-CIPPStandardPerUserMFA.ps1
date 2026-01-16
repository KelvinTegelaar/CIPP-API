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
            "CIS M365 5.0 (1.2.1)"
            "CIS M365 5.0 (1.1.1)"
            "CIS M365 5.0 (1.1.2)"
            "CISA (MS.AAD.1.1v1)"
            "CISA (MS.AAD.1.2v1)"
            "Essential 8 (1504)"
            "Essential 8 (1173)"
            "Essential 8 (1401)"
            "NIST CSF 2.0 (PR.AA-03)"
        EXECUTIVETEXT
            Requires all employees to use multi-factor authentication for enhanced account security, significantly reducing the risk of unauthorized access from compromised passwords. This fundamental security measure protects against the majority of account-based attacks and is essential for maintaining strong cybersecurity posture.
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=userPrincipalName,displayName,accountEnabled,perUserMfaState&`$filter=userType eq 'Member' and accountEnabled eq true and displayName ne 'On-Premises Directory Synchronization Service Account'&`$count=true" -tenantid $Tenant -ComplexFilter
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the PerUserMFA state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $UsersWithoutMFA = $GraphRequest | Where-Object -Property perUserMfaState -NE 'enforced' | Select-Object -Property userPrincipalName, displayName, accountEnabled, perUserMfaState

    if ($Settings.remediate -eq $true) {
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
        $CurrentValue = @{
            UsersWithoutMFA = @($UsersWithoutMFA)
        }
        $ExpectedValue = @{
            UsersWithoutMFA = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.PerUserMFA' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $tenant
        Add-CIPPBPAField -FieldName 'LegacyMFAUsers' -FieldValue $UsersWithoutMFA -StoreAs json -Tenant $tenant
    }
}
