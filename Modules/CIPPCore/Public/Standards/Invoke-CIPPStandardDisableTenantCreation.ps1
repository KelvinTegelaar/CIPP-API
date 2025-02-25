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
            "CIS"
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
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableTenantCreation'

    $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.defaultUserRolePermissions.allowedToCreateTenants -eq $false)

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already disabled from creating tenants.' -sev Info
        } else {
            try {
                $GraphRequest = @{
                    tenantid = $tenant
                    uri = 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy'
                    AsApp = $false
                    Type = 'PATCH'
                    ContentType = 'application/json'
                    Body = '{"defaultUserRolePermissions":{"allowedToCreateTenants":false}}'
                }
                New-GraphPostRequest @GraphRequest
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating tenants.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating tenants" -sev 'Error' -LogData $_
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create tenants.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create tenants.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableTenantCreation' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
