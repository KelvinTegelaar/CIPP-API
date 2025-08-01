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
    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/entra/uxSetting' -tenantid $Tenant
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DisableEntraPortal state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

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
            Write-StandardsAlert -message 'Disable user access to Entra Portal is not enabled' -object $CurrentInfo -tenant $tenant -standardName 'DisableEntraPortal' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disable user access to Entra Portal is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        set-CIPPStandardsCompareField -FieldName 'standards.DisableEntraPortal' -FieldValue $CurrentInfo.isSoftwareOathEnabled -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'DisableEntraPortal' -FieldValue $CurrentInfo.isSoftwareOathEnabled -StoreAs bool -Tenant $tenant
    }

}
