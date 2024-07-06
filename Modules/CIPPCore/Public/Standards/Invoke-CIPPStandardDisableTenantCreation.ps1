function Invoke-CIPPStandardDisableTenantCreation {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableTenantCreation
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    "CIS"
    .HELPTEXT
    Restricts creation of M365 tenants to the Global Administrator or Tenant Creator roles. 
    .DOCSDESCRIPTION
    Users by default are allowed to create M365 tenants. This disables that so only admins can create new M365 tenants.
    .ADDEDCOMPONENT
    .LABEL
    Disable M365 Tenant creation by users
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgPolicyAuthorizationPolicy
    .RECOMMENDEDBY
    "CIS"
    .DOCSDESCRIPTION
    Restricts creation of M365 tenants to the Global Administrator or Tenant Creator roles. 
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
    $State = $CurrentInfo.defaultUserRolePermissions.allowedToCreateTenants

    If ($Settings.remediate -eq $true) {

        if ($State) {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateTenants":false}}'
                New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating tenants.' -sev Info
                $State = $false
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating tenants:  $ErrorMessage" -sev 'Error'
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already disabled from creating tenants.' -sev Info
        }
    }
    if ($Settings.alert -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create tenants.' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create tenants.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableTenantCreation' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}




