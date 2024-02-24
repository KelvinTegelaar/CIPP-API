function Invoke-CIPPStandardSendFromAlias {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').SendFromAliasEnabled

    If ($Settings.remediate) {
        if ($CurrentInfo -eq $false) {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ SendFromAliasEnabled = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias enabled.' -sev Info
                $CurrentInfo = $true
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable send from alias. Error: $($_.exception.message)" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is already enabled.' -sev Info
        }
    }

    if ($Settings.alert) {
        if ($CurrentInfo -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Send from alias is not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'SendFromAlias' -FieldValue [bool]$CurrentInfo -StoreAs bool -Tenant $tenant
    }
}
