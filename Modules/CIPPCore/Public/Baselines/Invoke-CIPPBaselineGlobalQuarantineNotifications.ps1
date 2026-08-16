function Invoke-CIPPBaselineGlobalQuarantineNotifications {
    <#
    .SYNOPSIS
        GlobalQuarantineNotifications executor: sets the end-user notification interval.
    .DESCRIPTION
        The Microsoft default policy (DefaultGlobalPolicy) cannot be modified - meeting it
        means CREATING the custom DefaultGlobalTag with the interval; anything else is Set-
        in place. The classic's exact branch.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Interval = "$($Remediate.notificationInterval)"
    if ([string]::IsNullOrWhiteSpace($Interval)) { return }

    if ("$($Current.policyName)" -eq 'DefaultGlobalPolicy') {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-QuarantinePolicy' -cmdParams @{
            Name = 'DefaultGlobalTag'; QuarantinePolicyType = 'GlobalQuarantinePolicy'; EndUserSpamNotificationFrequency = $Interval
        }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Created the custom global quarantine policy with a $Interval notification interval." -Sev 'Info'
    } else {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-QuarantinePolicy' -cmdParams @{
            Identity = "$($Current.policyIdentity)"; EndUserSpamNotificationFrequency = $Interval
        }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the global quarantine notification interval to $Interval." -Sev 'Info'
    }
}
