function Send-CIPPBaselineAlertDigest {
    <#
    .SYNOPSIS
        Ships all queued baseline alerts as one notification per tenant.
    .DESCRIPTION
       
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    try {
        $Table = Get-CippTable -tablename 'BaselineAlertQueue'
        $Queued = @(Get-CIPPAzDataTableEntity @Table)
        if ($Queued.Count -eq 0) { return }

        $ConfigTable = Get-CIPPTable -TableName SchedulerConfig
        $Config = [pscustomobject](Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'")

        $CippConfigTable = Get-CippTable -tablename Config
        $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $CIPPURL = 'https://{0}' -f $CippConfig.Value

        foreach ($TenantGroup in ($Queued | Group-Object -Property PartitionKey)) {
            $TenantFilter = $TenantGroup.Name

            # Newest event wins when the same (standard, event) queued twice across runs.
            $Rows = @($TenantGroup.Group | Sort-Object -Property Timestamp -Descending |
                Group-Object -Property { '{0}|{1}' -f $_.Standard, $_.Event } |
                ForEach-Object { $_.Group[0] })

            # A baseline with its own destinations ships separately from the default
            # channels, so one digest per destination set.
            foreach ($DestinationGroup in ($Rows | Group-Object -Property { '{0}|{1}' -f $_.AlertEmails, $_.AlertWebhookUrl })) {
                $GroupRows = @($DestinationGroup.Group)
                $AlertEmails = "$($GroupRows[0].AlertEmails)"
                $AlertWebhookUrl = "$($GroupRows[0].AlertWebhookUrl)"
                $HasOverride = -not ([string]::IsNullOrWhiteSpace($AlertEmails) -and [string]::IsNullOrWhiteSpace($AlertWebhookUrl))

                $Alerts = @($GroupRows | ForEach-Object {
                        [PSCustomObject]@{
                            Event        = $_.Event
                            Standard     = $_.Standard
                            Label        = $_.Label
                            Description  = $_.Description
                            Category     = $_.Category
                            Baseline     = $_.Baseline
                            Stage        = $_.Stage
                            Differences  = @($_.Differences | ConvertFrom-Json -ErrorAction SilentlyContinue)
                            ConflictWith = @("$($_.ConflictWith)" -split ', ' | Where-Object { $_ })
                            RunId        = $_.RunId
                        }
                    })

                $EmailTemplate = New-CIPPAlertTemplate -Format 'html' -InputObject 'baseline' -Data $Alerts -CIPPURL $CIPPURL -Tenant $TenantFilter
                $Title = $EmailTemplate.title

                $WebhookData = [PSCustomObject]@{
                    Title           = $Title
                    Tenant          = $TenantFilter
                    DriftCount      = @($Alerts | Where-Object { $_.Event -eq 'Drift' }).Count
                    RemediatedCount = @($Alerts | Where-Object { $_.Event -eq 'Remediated' }).Count
                    ConflictCount   = @($Alerts | Where-Object { $_.Event -eq 'Conflict' }).Count
                    Standards       = @($Alerts | Select-Object Event, Standard, Label, Category, Baseline, Stage, Differences, ConflictWith, RunId)
                } | ConvertTo-Json -Depth 10 -Compress

                if ($HasOverride) {
                    if (![string]::IsNullOrWhiteSpace($AlertEmails)) {
                        $null = Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $EmailTemplate.htmlcontent -TenantFilter $TenantFilter -altEmail $AlertEmails -APIName 'Baselines'
                    }
                    if (![string]::IsNullOrWhiteSpace($AlertWebhookUrl)) {
                        $null = Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $WebhookData -TenantFilter $TenantFilter -altWebhook $AlertWebhookUrl `
                            -APIName 'Baselines' -SchemaSource 'Baseline Alert' -InvokingCommand 'Invoke-CIPPBaselineStandard' `
                            -UseStandardizedSchema:$([boolean]$Config.UseStandardizedSchema)
                    }
                } else {
                    $null = Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $EmailTemplate.htmlcontent -TenantFilter $TenantFilter -APIName 'Baselines'
                    $null = Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $WebhookData -TenantFilter $TenantFilter `
                        -APIName 'Baselines' -SchemaSource 'Baseline Alert' -InvokingCommand 'Invoke-CIPPBaselineStandard' `
                        -UseStandardizedSchema:$([boolean]$Config.UseStandardizedSchema)
                    # Gate here so Send-CIPPAlert's skip warning only fires for deliveries someone asked for.
                    if ($Config.sendtoIntegration) {
                        # PSA tickets get the style-free fragment: Halo stores the full email's
                        # <style> block but never applies it, which strips the tables bare.
                        $PsaTemplate = New-CIPPAlertTemplate -Format 'psa' -InputObject 'baseline' -Data $Alerts -CIPPURL $CIPPURL -Tenant $TenantFilter
                        $null = Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $PsaTemplate.htmlcontent -TenantFilter $TenantFilter -APIName 'Baselines'
                    }
                }
            }

            # Processed - drained whether or not every channel accepted it, so a failing
            # channel cannot replay the same digest at every following run.
            Remove-CIPPAzDataTableEntity -Force @Table -Entity @($TenantGroup.Group)
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Sent baseline alert digest: $($Rows.Count) event$(if ($Rows.Count -ne 1) { 's' })" -Sev 'Info'
        }
    } catch {
        Write-LogMessage -API 'Baselines' -message "Baseline alert digest failed: $($_.Exception.Message)" -Sev 'Error'
    }
}
