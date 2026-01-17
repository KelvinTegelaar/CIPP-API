function Invoke-CIPPStandardDisableAppCreation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableAppCreation
    .SYNOPSIS
        (Label) Disable App creation by users
    .DESCRIPTION
        (Helptext) Disables the ability for users to create App registrations in the tenant.
        (DocsDescription) Disables the ability for users to create applications in Entra. Done to prevent breached accounts from creating an app to maintain access to the tenant, even after the breached account has been secured.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "CIS M365 5.0 (1.2.2)"
            "CISA (MS.AAD.4.1v1)"
            "EIDSCA.AP10"
            "Essential 8 (1175)"
            "NIST CSF 2.0 (PR.AA-05)"
        EXECUTIVETEXT
            Prevents regular employees from creating application registrations that could be used to maintain unauthorized access to company systems. This security measure ensures that only authorized IT personnel can create applications, reducing the risk of persistent security breaches through malicious applications.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-03-20
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
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'DisableAppCreation'


    try {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy?$select=defaultUserRolePermissions' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableAppCreation state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $CurrentValue = $CurrentInfo.defaultUserRolePermissions | Select-Object -Property allowedToCreateApps
    $ExpectedValue = [PSCustomObject]@{
        allowedToCreateApps = $false
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateApps -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are already not allowed to create App registrations.' -sev Info
        } else {
            try {
                $body = '{"defaultUserRolePermissions":{"allowedToCreateApps":false}}'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json'
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled users from creating App registrations.' -sev Info
                $CurrentInfo.defaultUserRolePermissions.allowedToCreateApps = $false
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable users from creating App registrations: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($CurrentInfo.defaultUserRolePermissions.allowedToCreateApps -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are not allowed to create App registrations.' -sev Info
        } else {
            Write-StandardsAlert -message 'Users are allowed to create App registrations.' -object $CurrentInfo -tenant $tenant -standardName 'DisableAppCreation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Users are allowed to create App registrations.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $State = -not $CurrentInfo.defaultUserRolePermissions.allowedToCreateApps
        Set-CIPPStandardsCompareField -FieldName 'standards.DisableAppCreation' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'UserAppCreationDisabled' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}
