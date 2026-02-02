function Invoke-CIPPStandardDisableTenantCreation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableTenantCreation
    .SYNOPSIS
        (Label) Disable M365 Tenant creation by users
    .DESCRIPTION
        (Helptext) Restricts creation of M365 tenants to the Global Administrator or Tenant Creator roles.
        (DocsDescription) Users by default are allowed to create M365 tenants. This disables that so only admins can create new M365 tenants.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 5.0 (1.2.3)"
            "CISA (MS.AAD.6.1v1)"
        EXECUTIVETEXT
            Prevents regular employees from creating new Microsoft 365 organizations, ensuring all new tenants are properly managed and controlled by IT administrators. This prevents unauthorized shadow IT environments and maintains centralized governance over Microsoft 365 resources.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2022-11-29
        POWERSHELLEQUIVALENT
            Update-MgPolicyAuthorizationPolicy
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
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableTenantCreation state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }
    $StateIsCorrect = ($CurrentState.defaultUserRolePermissions.allowedToCreateTenants -eq $false)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are already disabled from creating tenants.' -sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantid = $Tenant
                    uri      = 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy'
                    Type     = 'PATCH'
                    Body     = '{"defaultUserRolePermissions":{"allowedToCreateTenants":false}}'
                }
                New-GraphPOSTRequest @GraphRequest
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully disabled users from creating tenants.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable users from creating tenants. Error: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are not allowed to create tenants.' -sev Info
        } else {
            Write-StandardsAlert -message 'Users are allowed to create tenants' -object $CurrentState -tenant $Tenant -standardName 'DisableTenantCreation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are allowed to create tenants.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            DisableTenantCreation = $StateIsCorrect
        }
        $ExpectedValue = [PSCustomObject]@{
            DisableTenantCreation = $true
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.DisableTenantCreation' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableTenantCreation' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
