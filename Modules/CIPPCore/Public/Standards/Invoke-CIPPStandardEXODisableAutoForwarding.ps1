function Invoke-CIPPStandardEXODisableAutoForwarding {
    <#
    .FUNCTIONALITY
        Internal
    #>

    param($Tenant, $Settings)
    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -cmdparams @{Identity = 'Default' } -useSystemMailbox $true
    $StateIsCorrect = $CurrentInfo.AutoForwardingMode -eq 'Off' -or $CurrentInfo.AutoForwardingMode -eq 'Automatic'

    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate!'

        if ($StateIsCorrect -eq $false) {
            try {
                New-ExoRequest -tenantid $tenant -cmdlet 'Set-HostedOutboundSpamFilterPolicy' -cmdparams @{ Identity = 'Default'; AutoForwardingMode = 'Off' } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled auto forwarding' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not disable auto forwarding. $($ErrorMessage.NormalizedError)" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto forwarding is already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto forwarding is disabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Auto forwarding is not disabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'AutoForwardingDisabled' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}
