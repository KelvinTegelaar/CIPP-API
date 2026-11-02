function Invoke-CIPPBaselineNudgeMFA {
    <#
    .SYNOPSIS
        NudgeMFA executor: writes the authenticator registration campaign.
    .DESCRIPTION
        One call to Set-CIPPRegistrationCampaign - the shared helper the classic and the
        identity UI use - with the hook's carried inputs. Null include/exclude targets mean
        'keep the tenant's current targeting', the deliberate semantics that stop older
        deployments having portal-configured targeting overwritten.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $P = $Current.campaignParams
    if (-not $P) { return }

    $Params = @{
        Tenant                                 = $TenantFilter
        State                                  = "$($P.State)"
        TargetedAuthenticationMethod           = "$($P.TargetedAuthenticationMethod)"
        SnoozeDurationInDays                   = [int]$P.SnoozeDurationInDays
        EnforceRegistrationAfterAllowedSnoozes = [bool]$P.EnforceRegistrationAfterAllowedSnoozes
        IncludeTargets                         = $P.IncludeTargets
        ExcludeTargets                         = $P.ExcludeTargets
        APIName                                = 'Baselines'
    }
    $null = Set-CIPPRegistrationCampaign @Params
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the MFA registration campaign to $($P.State) ($($P.TargetedAuthenticationMethod), snooze $($P.SnoozeDurationInDays)d)." -Sev 'Info'
}
