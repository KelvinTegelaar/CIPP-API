function Send-CIPPBaselineAlert {
    <#
    .SYNOPSIS
        Delivers a baseline deviation/remediation alert.
    .DESCRIPTION
        Fires on the transition into Drift (alertEnabled) and on auto-remediation
        (alertOnRemediate). When the baseline configures its own alertEmails/alertWebhookUrl
        those destinations OVERRIDE the instance-wide channels; otherwise the alert goes through
        the standard CippNotifications config (email + webhook + PSA each no-op when unset).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Result)

    $Item = $Result.Item
    $AlertEvent = $Result.AlertEvent
    $Title = if ($AlertEvent -eq 'Remediated') {
        "Baseline standard auto-remediated: $($Item.Standard) on $($Item.TenantFilter)"
    } else {
        "Baseline drift detected: $($Item.Standard) on $($Item.TenantFilter)"
    }
    $DiffLines = @($Result.Diff | ForEach-Object {
            "<li><b>$($_.Property)</b>: expected '$($_.ExpectedValue)', found '$($_.ReceivedValue)'</li>"
        }) -join ''
    $HTMLContent = "<p>$Title (baseline: $($Item.SourceTemplate), stage $($Item.Stage)).</p>" + $(if ($DiffLines) { "<ul>$DiffLines</ul>" } else { '' })
    $JSONContent = ConvertTo-Json -Compress -Depth 100 -InputObject ([PSCustomObject]@{
            Event        = $AlertEvent
            Tenant       = $Item.TenantFilter
            Standard     = $Item.Standard
            Baseline     = $Item.SourceTemplate
            Stage        = $Item.Stage
            Differences  = @($Result.Diff)
        })

    try {
        if ($Item.AlertEmails -or $Item.AlertWebhookUrl) {
            # Baseline-level destinations override the instance-wide channels.
            if ($Item.AlertEmails) {
                Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $HTMLContent -TenantFilter $Item.TenantFilter -altEmail $Item.AlertEmails -APIName 'Baselines'
            }
            if ($Item.AlertWebhookUrl) {
                Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $JSONContent -TenantFilter $Item.TenantFilter -altWebhook $Item.AlertWebhookUrl -APIName 'Baselines'
            }
        } else {
            Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $HTMLContent -TenantFilter $Item.TenantFilter -APIName 'Baselines'
            Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $JSONContent -TenantFilter $Item.TenantFilter -APIName 'Baselines'
            Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $HTMLContent -TenantFilter $Item.TenantFilter -APIName 'Baselines'
        }
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $Item.TenantFilter -message "Failed to send baseline alert for $($Item.Standard): $($_.Exception.Message)" -Sev 'Error'
    }
}
