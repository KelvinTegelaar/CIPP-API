function Set-CIPPRegistrationCampaign {
    <#
    .SYNOPSIS
        Updates the authentication methods registration campaign (nudge) for a tenant.
    .DESCRIPTION
        Single writer for the registration campaign, shared by the ExecRegistrationCampaign
        endpoint and the NudgeMFA standard. Any parameter left as $null keeps the value
        currently configured in the tenant, so callers can update settings independently.
    .PARAMETER IncludeTargets
        Array of @{ id; targetType } targets. $null keeps the current include targets. The
        targeted authentication method is applied to every include target, and a campaign
        always ends up with at least one include target (falls back to all_users).
    .PARAMETER ExcludeTargets
        Array of @{ id; targetType } targets. $null keeps the current exclusions, an empty
        array clears them.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Tenant,
        $State,
        $TargetedAuthenticationMethod,
        $SnoozeDurationInDays,
        $EnforceRegistrationAfterAllowedSnoozes,
        $IncludeTargets,
        $ExcludeTargets,
        $APIName = 'Set Registration Campaign',
        $Headers
    )

    try {
        $CurrentPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -tenantid $Tenant
        $CurrentCampaign = $CurrentPolicy.registrationEnforcement.authenticationMethodsRegistrationCampaign
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Could not get the current registration campaign. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw "Could not get the current registration campaign. Error: $($ErrorMessage.NormalizedError)"
    }

    $DesiredState = $State ?? $CurrentCampaign.state
    $DesiredMethod = $TargetedAuthenticationMethod ?? (@($CurrentCampaign.includeTargets).targetedAuthenticationMethod | Select-Object -First 1) ?? 'microsoftAuthenticator'
    $DesiredSnooze = if ($null -ne $SnoozeDurationInDays) { [int]$SnoozeDurationInDays } else { [int]($CurrentCampaign.snoozeDurationInDays ?? 1) }
    $DesiredEnforce = if ($null -ne $EnforceRegistrationAfterAllowedSnoozes) { [bool]$EnforceRegistrationAfterAllowedSnoozes } else { [bool]$CurrentCampaign.enforceRegistrationAfterAllowedSnoozes }

    if ($DesiredState -notin @('default', 'enabled', 'disabled')) {
        throw "State must be one of 'default', 'enabled' or 'disabled'"
    }
    if ($DesiredMethod -notin @('microsoftAuthenticator', 'fido2')) {
        throw "TargetedAuthenticationMethod must be 'microsoftAuthenticator' or 'fido2'"
    }
    if ($DesiredSnooze -lt 0 -or $DesiredSnooze -gt 14) {
        throw 'SnoozeDurationInDays must be between 0 and 14'
    }

    $DesiredIncludeTargets = if ($null -ne $IncludeTargets) {
        @($IncludeTargets | ForEach-Object { @{ id = "$($_.id)"; targetType = "$($_.targetType)"; targetedAuthenticationMethod = $DesiredMethod } })
    } else {
        @($CurrentCampaign.includeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType; targetedAuthenticationMethod = $DesiredMethod } })
    }
    if ($DesiredIncludeTargets.Count -eq 0) {
        $DesiredIncludeTargets = @(@{ id = 'all_users'; targetType = 'group'; targetedAuthenticationMethod = $DesiredMethod })
    }

    $DesiredExcludeTargets = if ($null -ne $ExcludeTargets) {
        @($ExcludeTargets | ForEach-Object { @{ id = "$($_.id)"; targetType = "$($_.targetType)" } })
    } else {
        @($CurrentCampaign.excludeTargets | ForEach-Object { @{ id = $_.id; targetType = $_.targetType } })
    }

    $Body = @{
        registrationEnforcement = @{
            authenticationMethodsRegistrationCampaign = @{
                state                                  = $DesiredState
                snoozeDurationInDays                   = $DesiredSnooze
                enforceRegistrationAfterAllowedSnoozes = $DesiredEnforce
                includeTargets                         = @($DesiredIncludeTargets)
                excludeTargets                         = @($DesiredExcludeTargets)
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $Result = "Set the registration campaign state to $DesiredState targeting $DesiredMethod with a snooze duration of $DesiredSnooze day(s), $($DesiredIncludeTargets.Count) include target(s) and $($DesiredExcludeTargets.Count) exclude target(s)"
        if ($PSCmdlet.ShouldProcess('Registration campaign', "Set state to $DesiredState")) {
            $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy' -Type PATCH -Body $Body -ContentType 'application/json' -AsApp $false
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message $Result -sev Info
        }
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to update the registration campaign. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw "Failed to update the registration campaign. Error: $($ErrorMessage.NormalizedError)"
    }
}
