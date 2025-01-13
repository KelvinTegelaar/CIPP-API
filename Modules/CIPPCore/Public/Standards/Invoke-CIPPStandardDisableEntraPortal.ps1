function Invoke-CIPPStandardDisableEntraPortal {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DisableEntraPortal
    .SYNOPSIS
        (Label) Disables the Entra Portal for standard users
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'allowOTPTokens' -Settings $Settings
    #This standard is still unlisted due to MS fixing some permissions. This will be added to the list once it is fixed.
    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/entra/uxSetting' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        if ($CurrentInfo.restrictNonAdminAccess) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disable user access to Entra Portal is already enabled.' -sev Info
        } else {
            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/admin/entra/uxSetting' -tenantid $Tenant -body '{"restrictNonAdminAccess":true}' -type PATCH
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.isSoftwareOathEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disable user access to Entra Portal is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disable user access to Entra Portal is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableEntraPortal' -FieldValue $CurrentInfo.isSoftwareOathEnabled -StoreAs bool -Tenant $tenant
    }

}
