function Invoke-CIPPStandardDisableAgentBlueprintCreation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableAgentBlueprintCreation
    .SYNOPSIS
        (Label) Disable agent identity blueprint creation by users
    .DESCRIPTION
        (Helptext) Disables the ability for users to register agent identity blueprints in the tenant. This is a separate setting from 'Users can register applications'; disabling app registrations does not stop users from creating agent identity blueprints.
        (DocsDescription) Sets the Entra default user role permission 'Users can register agent identity blueprints' to No. Microsoft enables this for all users by default, and the creator of a blueprint becomes its owner and can manage its credentials. This setting is independent of 'Users can register applications', so apply both standards to keep application and agent identity creation limited to the Agent ID Developer and Agent ID Administrator roles.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Prevents regular employees from creating AI agent identity blueprints, which are the templates that agent identities are issued from. Restricting this to designated roles keeps agent identities and their credentials under IT governance and avoids a sprawl of unmanaged agent registrations.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-10-15
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthorizationPolicy
        RECOMMENDEDBY
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    try {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy?$select=defaultUserRolePermissions' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableAgentBlueprintCreation state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $CurrentValue = $CurrentInfo.defaultUserRolePermissions | Select-Object -Property allowedToCreateAgentIdentityBlueprints
    $ExpectedValue = [PSCustomObject]@{
        allowedToCreateAgentIdentityBlueprints = $false
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateAgentIdentityBlueprints -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are already not allowed to create agent identity blueprints.' -sev Info
        } else {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateAgentIdentityBlueprints":false}}'
                $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Disabled users from creating agent identity blueprints.' -sev Info
                $CurrentInfo.defaultUserRolePermissions.allowedToCreateAgentIdentityBlueprints = $false
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable users from creating agent identity blueprints: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateAgentIdentityBlueprints -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are not allowed to create agent identity blueprints.' -sev Info
        } else {
            Write-StandardsAlert -message 'Users are allowed to create agent identity blueprints.' -object $CurrentInfo -tenant $Tenant -standardName 'DisableAgentBlueprintCreation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Users are allowed to create agent identity blueprints.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableAgentBlueprintCreation' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
