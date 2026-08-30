function Invoke-CIPPBaselineUserSubmissions {
    <#
    .SYNOPSIS
        UserSubmissions executor: sets the report submission policy and rule posture.
    .DESCRIPTION
        The classic's write, whole: the policy is New-ed or Set- with the full parameter set
        for the chosen posture (reporting to Microsoft, to a custom address, or off), and
        the rule follows - created or updated to route to the address when one is
        configured, REMOVED when reporting is being turned off while an enabled rule
        remains. The fixed names are Exchange's own defaults.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $State = "$($Remediate.state)"
    if ($State -notin @('enable', 'disable')) { return }
    $Email = "$($Current.resolvedEmail)"

    if ($State -eq 'enable' -and -not [string]::IsNullOrWhiteSpace($Email)) {
        # 'Mailbox' routes reports to the reporting mailbox only (third-party phishing
        # services); anything else keeps the original Microsoft-as-well posture.
        $PolicyParams = @{
            EnableReportToMicrosoft = "$($Current.reportDestination)" -ne 'Mailbox'
            ReportJunkToCustomizedAddress = $true; ReportJunkAddresses = $Email
            ReportNotJunkToCustomizedAddress = $true; ReportNotJunkAddresses = $Email
            ReportPhishToCustomizedAddress = $true; ReportPhishAddresses = $Email
        }
        $RuleParams = @{ SentTo = $Email }
    } elseif ($State -eq 'enable') {
        $PolicyParams = @{
            EnableReportToMicrosoft = $true
            ReportJunkToCustomizedAddress = $false; ReportJunkAddresses = $null
            ReportNotJunkToCustomizedAddress = $false; ReportNotJunkAddresses = $null
            ReportPhishToCustomizedAddress = $false; ReportPhishAddresses = $null
        }
        $RuleParams = $null
    } else {
        $PolicyParams = @{
            EnableReportToMicrosoft = $false
            ReportJunkToCustomizedAddress = $false; ReportJunkAddresses = $null
            ReportNotJunkToCustomizedAddress = $false; ReportNotJunkAddresses = $null
            ReportPhishToCustomizedAddress = $false; ReportPhishAddresses = $null
        }
        $RuleParams = $null
    }

    if ($Current.policyExists -eq $true) {
        $PolicyParams['Identity'] = 'DefaultReportSubmissionPolicy'
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ReportSubmissionPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
    } else {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ReportSubmissionPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
    }

    if ($RuleParams) {
        if ($Current.ruleExists -eq $true) {
            $RuleParams['Identity'] = 'DefaultReportSubmissionRule'
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ReportSubmissionRule' -cmdParams $RuleParams -useSystemMailbox $true
        } else {
            $RuleParams['Name'] = 'DefaultReportSubmissionRule'
            $RuleParams['ReportSubmissionPolicy'] = 'DefaultReportSubmissionPolicy'
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ReportSubmissionRule' -cmdParams $RuleParams -useSystemMailbox $true
        }
    } elseif ($Current.ruleEnabled -eq $true) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ReportSubmissionRule' -cmdParams @{ Identity = 'DefaultReportSubmissionRule' } -useSystemMailbox $true
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied the user submissions posture ($State$(if ($Email) { ", $Email" }))." -Sev 'Info'
}
