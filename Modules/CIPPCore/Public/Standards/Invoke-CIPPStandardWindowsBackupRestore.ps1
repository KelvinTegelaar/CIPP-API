function Invoke-CIPPStandardWindowsBackupRestore {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) WindowsBackupRestore
    .SYNOPSIS
        (Label) Set Windows Backup and Restore state
    .DESCRIPTION
        (Helptext) Configures the Windows Backup and Restore enrollment setting in Intune. When enabled, users see a restore page during Windows Autopilot/OOBE that allows them to restore their apps and settings from a previous device backup. **Before you can restore a backup, a policy to enable it on devices must be set up in Settings Catalog.**
        (DocsDescription) Configures the Windows Backup and Restore (WBfO) device enrollment setting in Intune. This feature allows users to restore apps and settings from a previous device backup during Windows setup. Enabling this shows a restore page during enrollment (OOBE) so users can migrate their workspace configuration to a new device. More information can be found in [Microsoft's documentation.](https://learn.microsoft.com/en-us/intune/intune-service/enrollment/windows-backup-restore)
    .NOTES
        CAT
            Intune Standards
        TAG
        EXECUTIVETEXT
            Controls the Windows Backup and Restore for Organizations feature in Intune. When enabled, employees setting up new devices can restore their apps and settings from a previous backup during Windows enrollment. This streamlines device provisioning, reduces setup time for new or replacement devices, and improves the employee experience during device transitions.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.WindowsBackupRestore.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"},{"label":"Not Configured","value":"notConfigured"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-02-26
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    [CmdletBinding()]
    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'WindowsBackupRestore' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        return $true
    }

    # Get state value using null-coalescing operator
    $WantedState = $Settings.state.value ?? $Settings.state

    try {
        $Config = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?$filter=deviceEnrollmentConfigurationType eq ''windowsRestore''' -tenantid $Tenant
        $CurrentState = $Config.state
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve Windows Backup and Restore configuration. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $StateIsCorrect = $CurrentState -eq $WantedState

    $CurrentValue = [PSCustomObject]@{
        state = $CurrentState
    }
    $ExpectedValue = [PSCustomObject]@{
        state = $WantedState
    }

    # Input validation
    if ([string]::IsNullOrWhiteSpace($WantedState)) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'WindowsBackupRestore: Invalid state parameter set' -sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Backup and Restore is already set to $WantedState." -sev Info
        } else {
            try {
                $Body = @{
                    '@odata.type' = '#microsoft.graph.windowsRestoreDeviceEnrollmentConfiguration'
                    state         = $WantedState
                } | ConvertTo-Json -Depth 10

                New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations/$($Config.id)" -tenantid $Tenant -type PATCH -body $Body
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set Windows Backup and Restore to $WantedState." -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Windows Backup and Restore to $WantedState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Backup and Restore is set correctly to $WantedState." -sev Info
        } else {
            Write-StandardsAlert -message "Windows Backup and Restore is not set correctly. Expected: $WantedState, Current: $CurrentState" -object @{ CurrentState = $CurrentState; WantedState = $WantedState } -tenant $Tenant -standardName 'WindowsBackupRestore' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Windows Backup and Restore is not set correctly to $WantedState." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.WindowsBackupRestore' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'WindowsBackupRestore' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
