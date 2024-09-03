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
            "highimpact"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'PerUserMFA'


    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=userPrincipalName,displayName,accountEnabled&`$filter=userType eq 'Member' and accountEnabled eq true and displayName ne 'On-Premises Directory Synchronization Service Account'&`$count=true" -tenantid $Tenant -ComplexFilter
    $int = 0
    $Requests = foreach ($id in $GraphRequest.userPrincipalName) {
        @{
            id     = $int++
            method = 'GET'
            url    = "/users/$id/authentication/requirements"
        }
    }
    $UsersWithoutMFA = (New-GraphBulkRequest -tenantid $tenant -Requests @($Requests) -asapp $true).body | Where-Object { $_.perUserMfaState -ne 'enforced' } | Select-Object peruserMFAState, @{Name = 'userPrincipalName'; Expression = { [System.Web.HttpUtility]::UrlDecode($_.'@odata.context'.split("'")[1]) } }

    If ($Settings.remediate -eq $true) {
        if (($UsersWithoutMFA.userPrincipalName | Measure-Object).Count -gt 0) {
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
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The following accounts do not have Legacy MFA Enforced: $($UsersWithoutMFA.userPrincipalName -join ', ')" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No accounts do not have legacy per user MFA Enforced' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'LegacyMFAUsers' -FieldValue $UsersWithoutMFA -StoreAs json -Tenant $tenant
    }
}
