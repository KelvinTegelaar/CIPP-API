function Invoke-CIPPStandardEXODisableAutoForwarding {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EXODisableAutoForwarding
    .SYNOPSIS
        (Label) Disable automatic forwarding to external recipients
    .DESCRIPTION
        (Helptext) Disables the ability for users to automatically forward e-mails to external recipients.
        (DocsDescription) Disables the ability for users to automatically forward e-mails to external recipients. This is to prevent data exfiltration. Please check if there are any legitimate use cases for this feature before implementing, like forwarding invoices and such.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "highimpact"
            "CIS"
            "mdo_autoforwardingmode"
            "mdo_blockmailforward"
        ADDEDCOMPONENT
        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Set-HostedOutboundSpamFilterPolicy -AutoForwardingMode 'Off'
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#high-impact
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EXODisableAutoForwarding'

    $CurrentInfo = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-HostedOutboundSpamFilterPolicy' -cmdparams @{Identity = 'Default' } -useSystemMailbox $true
    $StateIsCorrect = $CurrentInfo.AutoForwardingMode -eq 'Off'

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
