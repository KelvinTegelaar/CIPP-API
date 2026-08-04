function Invoke-CIPPBaselineActivityBasedTimeout {
    <#
    .SYNOPSIS
        Custom baseline standard: Activity Based Timeout.
    .DESCRIPTION
        The ABT policy stores its configuration JSON-encoded INSIDE the policy JSON
        (definition[0] -> {"ActivityBasedTimeoutPolicy":{"WebSessionIdleTimeout":...}}), which
        the declarative read spec cannot express - the reason this standard is custom. Reads
        the ActivityBasedTimeoutPolicy cache (triggering the collector once on a miss; a miss
        after that writes NOTHING so the row stays 'No Data'), compares the web session idle
        timeout, and remediates by PATCHing the existing policy or POSTing a new
        organization-default one. Persists through the shared writer like every engine result.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        [ValidateSet('run', 'compare', 'oneoff')]$Mode = 'run',
        $TriggeredBy = 'schedule',
        [switch]$Force
    )

    $TenantFilter = $Item.TenantFilter
    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $ExpectedTimeout = "$($Item.Variables.timeout)"

    $Result = [PSCustomObject]@{
        Item                = $Item
        Mode                = $Mode
        TriggeredBy         = $TriggeredBy
        ExpectedValue       = [PSCustomObject]@{ timeout = $ExpectedTimeout }
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
    }

    try {
        $ResolvedTable = Get-CippTable -tablename 'BaselineAlignment'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter
        $SafeStandard = ConvertTo-CIPPODataFilterValue -Value $Item.Standard
        $Prior = Get-CIPPAzDataTableEntity @ResolvedTable -Filter "PartitionKey eq '$SafeTenant' and StandardName eq '$SafeStandard'" | Select-Object -First 1
        $PriorStatus = $Prior.Status
        $Result.Status = $PriorStatus

        $Policy = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ActivityBasedTimeoutPolicy' | Where-Object { $_ }) | Select-Object -First 1
        if ($null -eq $Policy) {
            $Collector = Get-Command -Name 'Set-CIPPDBCacheActivityBasedTimeoutPolicy' -ErrorAction SilentlyContinue
            if ($Collector) {
                try {
                    $null = & $Collector -TenantFilter $TenantFilter
                    $Policy = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ActivityBasedTimeoutPolicy' | Where-Object { $_ }) | Select-Object -First 1
                } catch {
                    Write-Information "Baselines: ABT cache collection on $TenantFilter failed: $($_.Exception.Message)"
                }
            }
        }
        if ($null -eq $Policy) {
            # Deliberately writes NOTHING: the row stays 'No Data' and retries next run.
            $Result.Outcome = 'Skipped-NoCache'
            $Result.Status = $PriorStatus ?? 'No Data'
            return $Result
        }

        # The governed value sits in a JSON string inside the policy's definition array.
        $CurrentTimeout = $(try { (@($Policy.definition)[0] | ConvertFrom-Json).ActivityBasedTimeoutPolicy.WebSessionIdleTimeout } catch { $null })
        $Result.CurrentValue = [PSCustomObject]@{ timeout = $CurrentTimeout }
        $Compliant = $CurrentTimeout -eq $ExpectedTimeout
        if (-not $Compliant) {
            $Result.Diff = @([PSCustomObject]@{ Property = 'timeout'; ExpectedValue = $ExpectedTimeout; ReceivedValue = $CurrentTimeout })
        }

        $Expires = if ("$($Prior.DeviationExpires)" -match '^\d+$') { [int64]$Prior.DeviationExpires } else { 0 }
        $AcceptActive = $PriorStatus -eq 'Accepted' -and ($Expires -eq 0 -or $Now -lt $Expires)
        if (-not $Compliant -and $AcceptActive) {
            $Result.Outcome = 'Drift'
            $Result.Status = 'Accepted'
            Set-CIPPBaselineResult -Result $Result -Prior $Prior
            return $Result
        }

        $DeniedRemediate = $PriorStatus -eq 'Denied - Remediate Pending'
        $RemediationAllowed = ($Mode -eq 'oneoff') -or ($Mode -eq 'run' -and ($Item.RemediateEnabled -or $DeniedRemediate))
        $WriteNeeded = (-not $Compliant) -or $Force.IsPresent

        if ($Mode -ne 'compare' -and $RemediationAllowed -and $WriteNeeded) {
            $PolicyDefinition = ConvertTo-Json -Compress -Depth 10 -InputObject ([PSCustomObject]@{
                    ActivityBasedTimeoutPolicy = [PSCustomObject]@{ Version = 1; WebSessionIdleTimeout = $ExpectedTimeout }
                })
            $Body = ConvertTo-Json -Compress -Depth 10 -InputObject ([PSCustomObject]@{
                    definition            = @($PolicyDefinition)
                    isOrganizationDefault = $true
                    displayName           = 'DefaultTimeoutPolicy'
                })
            if ($Policy.id) {
                $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies/$($Policy.id)" -type PATCH -body $Body -AsApp $true
            } else {
                $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/activityBasedTimeoutPolicies' -type POST -body $Body -AsApp $true
            }
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
            $Result.Status = 'Drift'
            if ($PriorStatus -ne 'Drift' -and $Item.AlertEnabled) { $Result.AlertEvent = 'Drift' }
        }

        Set-CIPPBaselineResult -Result $Result -Prior $Prior
        if ($Result.AlertEvent) { Send-CIPPBaselineAlert -Result $Result }
        return $Result
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Activity Based Timeout baseline failed on ${TenantFilter}: $($_.Exception.Message)" -Sev 'Error'
        $Result.Outcome = 'Error'
        try { Set-CIPPBaselineResult -Result $Result -Prior $Prior } catch { Write-Information "Set-CIPPBaselineResult failed: $($_.Exception.Message)" }
        return $Result
    }
}
