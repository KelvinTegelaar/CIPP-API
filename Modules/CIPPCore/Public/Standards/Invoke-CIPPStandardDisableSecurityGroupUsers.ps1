function Invoke-CIPPStandardDisableSecurityGroupUsers {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableSecurityGroupUsers
    .SYNOPSIS
        (Label) Disable Security Group creation by users
    .DESCRIPTION
        (Helptext) Completely disables the creation of security groups by users. This also breaks the ability to manage groups themselves, or create Teams
        (DocsDescription) Completely disables the creation of security groups by users. This also breaks the ability to manage groups themselves, or create Teams
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2022-07-17
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthorizationPolicy
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#medium-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableSecurityGroupUsers'

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already not allowed to create Security Groups.' -sev Info
        } else {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateSecurityGroups":false}}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating Security Groups.' -sev Info
                $CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups = $false
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating Security Groups: $ErrorMessage" -sev 'Error'
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create Security Groups.' -sev Info
        } else {
            Write-StandardsAlert -message 'Users are allowed to create Security Groups' -object $CurrentInfo -tenant $tenant -standardName 'DisableSecurityGroupUsers' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create Security Groups.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false ? $true : ($currentInfo.defaultUserRolePermissions | Select-Object allowedToCreateSecurityGroups)
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableSecurityGroupUsers' -FieldValue $state -Tenant $tenant
        Add-CIPPBPAField -FieldName 'DisableSecurityGroupUsers' -FieldValue $CurrentInfo.defaultUserRolePermissions.allowedToCreateSecurityGroups -StoreAs bool -Tenant $tenant
    }
}
