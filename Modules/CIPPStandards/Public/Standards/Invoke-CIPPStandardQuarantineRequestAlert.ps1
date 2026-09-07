function Invoke-CIPPStandardQuarantineRequestAlert {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) QuarantineRequestAlert
    .SYNOPSIS
        (Label) Quarantine Release Request Alert
    .DESCRIPTION
        (Helptext) Sets a e-mail address to alert when a User requests to release a quarantined message. Set the alert state to Removed to delete the alert rule CIPP created from the tenant.
        (DocsDescription) Sets a e-mail address to alert when a User requests to release a quarantined message. This is useful for monitoring and ensuring that the correct messages are released. Setting the alert state to Removed deletes the alert rule CIPP created from the tenant, for when the alert is no longer wanted.
    .NOTES
        CAT
            Defender Standards
        TAG
        EXECUTIVETEXT
            Notifies IT administrators when employees request to release emails that were quarantined for security reasons, enabling oversight of potentially dangerous messages. This helps ensure that legitimate emails are released while maintaining security controls over suspicious content.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"label":"Alert state (blank or Enabled creates the alert, Removed deletes it)","name":"standards.QuarantineRequestAlert.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Removed","value":"removed"}]}
            {"type":"textField","name":"standards.QuarantineRequestAlert.NotifyUser","label":"E-mail to receive the alert","condition":{"field":"standards.QuarantineRequestAlert.state","compareType":"isNot","compareValue":{"label":"Removed","value":"removed"}}}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-15
        POWERSHELLEQUIVALENT
            New-ProtectionAlert, Set-ProtectionAlert and Remove-ProtectionAlert
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "EXCHANGE_S_STANDARD"
            "EXCHANGE_S_ENTERPRISE"
            "EXCHANGE_S_STANDARD_GOV"
            "EXCHANGE_S_ENTERPRISE_GOV"
            "EXCHANGE_LITE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param ($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'QuarantineRequestAlert' -TenantFilter $Tenant -Preset Exchange #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        return $true
    } #we're done.
    $PolicyName = 'CIPP User requested to release a quarantined message'

    # Templates saved before the state selector existed carry no state value: treat those as
    # enabled, the only behaviour that existed at the time.
    $State = $Settings.state.value ?? $Settings.state
    if ([string]::IsNullOrWhiteSpace($State)) { $State = 'enabled' }

    if ($State -ne 'removed' -and [string]::IsNullOrWhiteSpace($Settings.NotifyUser) -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'QuarantineRequestAlert: NotifyUser is required when the alert state is Enabled' -sev Error
        return
    }

    try {
        $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-ProtectionAlert' -Compliance | Where-Object { $_.Name -eq $PolicyName }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the QuarantineRequestAlert state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Expected recipients, normalised (blanks removed, sorted, de-duplicated) so the alert's actual
    # recipients and the configured recipients can be compared as values, order-insensitively.
    $ExpectedNotify = if ($State -eq 'removed') { @() } else { @($Settings.NotifyUser | Where-Object { $_ } | Sort-Object -Unique) }

    # State is a value comparison of the alert's recipients against the expected recipients. Wrapped in a
    # scriptblock so it can be re-evaluated against a fresh read after remediation (see below), and so the
    # report's Current/Expected fields below are the exact values this comparison is made on.
    $GetStateIsCorrect = {
        if ($State -eq 'removed') {
            -not $CurrentState
        } else {
            $CurrentNotify = @($CurrentState.NotifyUser | Where-Object { $_ } | Sort-Object -Unique)
            ($CurrentNotify -join "`n") -eq ($ExpectedNotify -join "`n")
        }
    }
    $StateIsCorrect = & $GetStateIsCorrect

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            if ($State -eq 'removed') {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Quarantine Request Alert is already removed.' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Quarantine Request Alert is already configured correctly.' -sev Info
            }
        } elseif ($State -eq 'removed') {
            try {
                New-ExoRequest -TenantId $Tenant -cmdlet 'Remove-ProtectionAlert' -Compliance -cmdParams @{ Identity = $PolicyName } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully removed Quarantine Request Alert' -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to remove Quarantine Request Alert. Error: $ErrorMessage" -sev Error
            }
        } else {
            $cmdParams = @{
                'NotifyUser'      = $Settings.NotifyUser
                'Category'        = 'ThreatManagement'
                'Operation'       = 'QuarantineRequestReleaseMessage'
                'Severity'        = 'Informational'
                'AggregationType' = 'None'
            }

            if ($CurrentState.Name -eq $PolicyName) {
                try {
                    $cmdParams['Identity'] = $PolicyName
                    New-ExoRequest -TenantId $Tenant -cmdlet 'Set-ProtectionAlert' -Compliance -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully configured Quarantine Request Alert' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to configure Quarantine Request Alert. Error: $ErrorMessage" -sev Error
                }
            } else {
                try {
                    $cmdParams['name'] = $PolicyName
                    $cmdParams['ThreatType'] = 'Activity'

                    New-ExoRequest -TenantId $Tenant -cmdlet 'New-ProtectionAlert' -Compliance -cmdParams $cmdParams -UseSystemMailbox $true
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully created Quarantine Request Alert' -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to create Quarantine Request Alert. Error: $ErrorMessage" -sev Error
                }
            }
        }
        # Re-read the live state after remediating so the alert and report modes below reflect what was
        # actually applied this run, not the pre-remediation snapshot. Without this, a freshly created or
        # updated alert still reports its old (usually empty) recipients until the next scheduled run,
        # which reads as "nothing changed" immediately after a force run.
        try {
            $CurrentState = New-ExoRequest -TenantId $Tenant -cmdlet 'Get-ProtectionAlert' -Compliance | Where-Object { $_.Name -eq $PolicyName }
            $StateIsCorrect = & $GetStateIsCorrect
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not re-check the QuarantineRequestAlert state after remediation for $Tenant. Error: $ErrorMessage" -Sev Error
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            if ($State -eq 'removed') {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Quarantine Request Alert is not present' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Quarantine Request Alert is enabled' -sev Info
            }
        } else {
            $Message = if ($State -eq 'removed') { 'Quarantine Request Alert is still present but should be removed.' } else { 'Quarantine Request Alert is not enabled.' }
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'QuarantineRequestAlert' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'QuarantineRequestAlert' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant

        # Both sides are normalised the same way and kept as arrays (a bare @() around an if-expression
        # unrolls a single element to a scalar, which would never match the array-shaped Current value).
        # Compliance is then decided by CurrentValue -eq ExpectedValue in Get-CIPPTenantAlignment.
        $CurrentValue = @{
            NotifyUser = @($CurrentState.NotifyUser | Where-Object { $_ } | Sort-Object -Unique)
        }
        $ExpectedValue = @{
            NotifyUser = @($ExpectedNotify)
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.QuarantineRequestAlert' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
