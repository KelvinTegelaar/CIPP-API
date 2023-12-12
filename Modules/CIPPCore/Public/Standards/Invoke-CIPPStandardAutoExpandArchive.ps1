function Invoke-CIPPStandardAutoExpandArchive {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AutoExpandingArchiveEnabled
    If ($Settings.remediate) {
        try {
            if (!$currentstate) {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AutoExpandingArchive = $true }
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Added Auto Expanding Archive.' -sev Info
            }
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Auto Expanding Archives Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($AuditLogEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archives is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto Expanding Archives is not enabled' -sev Alert
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'AutoExpandingArchive' -FieldValue [bool]$CurrentState.AutoExpandingArchiveEnabled -StoreAs bool -Tenant $tenant
    }
}
