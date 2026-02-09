function Invoke-CIPPStandardEXODirectSend {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EXODirectSend
    .SYNOPSIS
        (Label) Set Direct Send state
    .DESCRIPTION
        (Helptext) Sets the state of Direct Send in Exchange Online. Direct Send allows applications to send emails directly to Exchange Online mailboxes as the tenants domains, without requiring authentication.
        (DocsDescription) Controls whether applications can use Direct Send to send emails directly to Exchange Online mailboxes as the tenants domains, without requiring authentication. A detailed explanation from Microsoft can be found [here.](https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365)
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            Controls whether business applications and devices (like printers or scanners) can send emails through the company's email system without authentication. While this enables convenient features like scan-to-email, it may pose security risks and should be carefully managed.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"label":"Select value","name":"standards.EXODirectSend.state","options":[{"label":"Enabled","value":"enabled"},{"label":"Disabled","value":"disabled"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-05-28
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -RejectDirectSend \$true/\$false
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)

    # Determine desired state. These double negative MS loves are a bit confusing
    $DesiredStateName = $Settings.state.value ?? $Settings.state
    # Input validation
    if ([string]::IsNullOrWhiteSpace($DesiredStateName) -or $DesiredStateName -eq 'Select a value') {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'EXODirectSend: Invalid state parameter set' -sev Error
        return
    }

    # Get current organization config
    try {
        $CurrentConfig = (New-ExoRequest -TenantID $Tenant -cmdlet 'Get-OrganizationConfig' -Select 'RejectDirectSend').RejectDirectSend
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to retrieve current Direct Send configuration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    $DesiredState = $DesiredStateName -eq 'disabled' ? $true : $false
    $StateIsCorrect = $CurrentConfig -eq $DesiredState

    # Remediate if needed
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Direct Send is already set to $DesiredStateName." -sev Info
        } else {
            try {
                $null = New-ExoRequest -TenantID $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ RejectDirectSend = $DesiredState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Direct Send has been set to $DesiredStateName." -sev Info
                $CurrentState = $DesiredState
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set Direct Send state: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    # Alert if needed
    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Direct Send is set to $DesiredStateName as required." -sev Info
        } else {
            $CurrentStateName = $CurrentState ? 'disabled' : 'enabled'
            Write-StandardsAlert -message "Direct Send is $CurrentStateName but should be $DesiredStateName" -object $CurrentConfig -tenant $Tenant -standardName 'EXODirectSend' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Direct Send is $CurrentStateName but should be $DesiredStateName." -sev Info
        }
    }

    # Report if needed
    if ($Settings.report -eq $true) {
        $ExpectedState = @{
            RejectDirectSend = $DesiredState
        }
        $CurrentState = @{
            RejectDirectSend = $CurrentConfig
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.EXODirectSend' -CurrentValue $CurrentState -ExpectedValue $ExpectedState -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'EXODirectSend' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
