function Invoke-CIPPBaselineDisableBasicAuthSMTP {
    <#
    .SYNOPSIS
        Custom baseline standard: Disable SMTP Basic Authentication.
    .DESCRIPTION
        Two dimensions, which is why this standard is custom: the tenant-wide
        TransportConfig SmtpClientAuthenticationDisabled flag AND the per-user CAS mailbox
        overrides (SmtpClientAuthenticationDisabled -eq $false = SMTP AUTH explicitly
        enabled for that user, alive regardless of the tenant switch). Compliant = flag
        matches the expectation and, when disabling, no user overrides remain. Remediation
        sets the transport flag and clears each override back to $null (inherit), exactly
        like the classic standard, then re-collects the override cache so the next run
        reads the cleared state. Persists through the shared writer like every engine
        result.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        [ValidateSet('run', 'compare', 'oneoff')]$Mode = 'run',
        $TriggeredBy = 'schedule',
        [switch]$Force,
        $RunId
    )
    if (-not $RunId) { $RunId = [string](New-Guid).Guid }

    $TenantFilter = $Item.TenantFilter
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $ExpectedDisabled = "$($Item.Variables.disabled)" -in @('True', 'true', '1')

    $Result = [PSCustomObject]@{
        Item                = $Item
        Mode                = $Mode
        TriggeredBy         = $TriggeredBy
        ExpectedValue       = [PSCustomObject]@{ SmtpClientAuthenticationDisabled = $ExpectedDisabled; UsersWithSmtpAuthEnabled = @() }
        CurrentValue        = $null
        Compliant           = $false
        PendingVerification = $false
        LicenseAvailable    = $true
        Status              = $null
        Remediated          = $false
        Outcome             = 'Error'
        Diff                = $null
        Inheritance         = @($Item.Tiers)
        AlertEvent          = $null
        CacheType           = 'ExoTransportConfig'
    }

    try {
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Item.Standard
        $Prior = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'" | Select-Object -First 1
        $PriorStatus = $Prior.Status
        $Result.Status = $PriorStatus

        $TransportConfig = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoTransportConfig' | Where-Object { $_ }) | Select-Object -First 1
        if ($null -eq $TransportConfig) {
            $Collector = Get-Command -Name 'Set-CIPPDBCacheExoTransportConfig' -ErrorAction SilentlyContinue
            if ($Collector) {
                try {
                    $null = & $Collector -TenantFilter $TenantFilter
                    $TransportConfig = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoTransportConfig' | Where-Object { $_ }) | Select-Object -First 1
                } catch {
                    Write-Information "Baselines: TransportConfig cache collection on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
        }
        if ($null -eq $TransportConfig) {
            # No cache and no way to grade honestly: nothing is written - the row stays
            # 'No Data' and retries next run.
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$($Item.Standard): no ExoTransportConfig data in CIPPDb after collection - skipped, nothing written." -Sev 'Info'
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        }

        # The override set: an empty read is ambiguous (never collected vs genuinely
        # none), so an empty read always re-collects once - the collector's ClearOnEmpty
        # makes the collected-empty state authoritative and the recollect cheap.
        $CollectOverrides = {
            $Collector = Get-Command -Name 'Set-CIPPDBCacheExoCASMailboxSmtpAuth' -ErrorAction SilentlyContinue
            if ($Collector) {
                try { $null = & $Collector -TenantFilter $TenantFilter } catch {
                    Write-Information "Baselines: SMTP AUTH override cache collection on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
        }
        $Overrides = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoCASMailboxSmtpAuth' | Where-Object { $_ })
        if ($Overrides.Count -eq 0) {
            & $CollectOverrides
            $Overrides = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoCASMailboxSmtpAuth' | Where-Object { $_ })
        }
        $EnabledUsers = @($Overrides | ForEach-Object { "$($_.PrimarySmtpAddress ?? $_.Identity)" } | Where-Object { $_ } | Sort-Object)

        $CurrentDisabled = [bool]$TransportConfig.SmtpClientAuthenticationDisabled
        $Result.CurrentValue = [PSCustomObject]@{
            SmtpClientAuthenticationDisabled = $CurrentDisabled
            UsersWithSmtpAuthEnabled         = $EnabledUsers
        }

        $FlagCompliant = $CurrentDisabled -eq $ExpectedDisabled
        # Per-user overrides only matter when the point is disabling SMTP AUTH.
        $UsersCompliant = (-not $ExpectedDisabled) -or ($EnabledUsers.Count -eq 0)
        $Compliant = $FlagCompliant -and $UsersCompliant
        if (-not $Compliant) {
            $Diff = [System.Collections.Generic.List[object]]::new()
            if (-not $FlagCompliant) {
                $Diff.Add([PSCustomObject]@{ Property = 'SmtpClientAuthenticationDisabled'; ExpectedValue = $ExpectedDisabled; ReceivedValue = $CurrentDisabled })
            }
            if (-not $UsersCompliant) {
                $Diff.Add([PSCustomObject]@{ Property = 'UsersWithSmtpAuthEnabled'; ExpectedValue = @(); ReceivedValue = $EnabledUsers })
            }
            $Result.Diff = @($Diff)
        }

        $Expires = if ("$($Prior.DeviationExpires)" -match '^\d+$') { [int64]$Prior.DeviationExpires } else { 0 }
        $AcceptActive = $PriorStatus -eq 'Accepted' -and ($Expires -eq 0 -or $Now -lt $Expires)
        if (-not $Compliant -and $AcceptActive) {
            $Result.Outcome = 'Drift'
            $Result.Status = 'Accepted'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
            return $Result
        }

        $DeniedRemediate = $PriorStatus -eq 'Denied - Remediate Pending'
        $RemediationAllowed = (($Mode -eq 'oneoff') -or ($Mode -eq 'run' -and ($Item.RemediateEnabled -or $DeniedRemediate))) -and -not $AcceptActive
        $WriteNeeded = (-not $Compliant) -or $Force.IsPresent

        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded) {
            try {
                if (-not $FlagCompliant -or $Force.IsPresent) {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-TransportConfig' -cmdParams @{ SmtpClientAuthenticationDisabled = $ExpectedDisabled }
                }
                # Clear each explicit enablement back to inherit ($null) - never $true, so
                # a later tenant-level policy change applies to these users again.
                if ($ExpectedDisabled) {
                    foreach ($User in $EnabledUsers) {
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams @{ Identity = $User; SmtpClientAuthenticationDisabled = $null }
                    }
                }
            } catch {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to change `"Disable SMTP Basic Authentication`": $($_.Exception.Message) - Run $RunId" -Sev 'Error'
                $Result.Outcome = 'Error'
                Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
                return $Result
            }
            if ($EnabledUsers.Count -gt 0) {
                # Refresh the override cache now: the cleared users must not read back as
                # drift on the next run (ClearOnEmpty makes the emptied state stick).
                & $CollectOverrides
            }
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Successfully changed `"Disable SMTP Basic Authentication`" ($($EnabledUsers.Count) user override$(if ($EnabledUsers.Count -eq 1) { '' } else { 's' }) cleared) - Run $RunId" -Sev 'Info'
            $Result.CurrentValue = $Result.ExpectedValue
            $Result.Compliant = $true
            $Result.PendingVerification = $true
            $Result.Remediated = $true
            $Result.Outcome = 'Remediated'
            $Result.Status = 'Compliant'
            if ($Item.AlertOnRemediate) { $Result.AlertEvent = 'Remediated' }
        } elseif ($Compliant) {
            $Result.Compliant = $true
            $Result.Outcome = 'Compliant'
            $Result.Status = 'Compliant'
        } else {
            $Result.Outcome = 'Drift'
            $Result.Status = if ("$PriorStatus".StartsWith('Denied')) { $PriorStatus } else { 'Drift' }
            if ($Result.Status -eq 'Drift' -and $PriorStatus -ne 'Drift' -and $Item.AlertEnabled) { $Result.AlertEvent = 'Drift' }
        }

        Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId
        if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
        return $Result
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Disable SMTP Basic Authentication baseline failed on ${TenantFilter}: $($_.Exception.Message)" -Sev 'Error'
        $Result.Outcome = 'Error'
        try { Set-CIPPBaselineResult -Result $Result -Prior $Prior -RunId $RunId } catch { Write-Information "Set-CIPPBaselineResult failed: $($_.Exception.Message)" }
        return $Result
    }
}
