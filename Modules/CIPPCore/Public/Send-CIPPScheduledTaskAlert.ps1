function Send-CIPPScheduledTaskAlert {
    <#
    .SYNOPSIS
        Send post-execution alerts for scheduled tasks

    .DESCRIPTION
        Handles sending alerts (PSA, Email, Webhook) for scheduled task completion

    .PARAMETER Results
        The results to send in the alert

    .PARAMETER TaskInfo
        The task information from the ScheduledTasks table

    .PARAMETER TenantFilter
        The tenant filter for the task

    .PARAMETER TaskType
        The type of task (default: 'Scheduled Task')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Results,

        [Parameter(Mandatory = $true)]
        $TaskInfo,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$TaskType = 'Scheduled Task',

        [Parameter(Mandatory = $false)]
        $Attachments
    )

    try {
        Write-Information "Sending post-execution alerts for task $($TaskInfo.Name)"

        # Use attachments from parameter, or extract from structured results as fallback
        $TaskAttachments = $Attachments
        if (-not $TaskAttachments) {
            if ($Results -is [hashtable] -and $Results.ContainsKey('TaskAttachments')) {
                $TaskAttachments = $Results.TaskAttachments
                $Results = $Results.Results
            } elseif ($Results -is [PSCustomObject] -and $null -ne $Results.TaskAttachments) {
                $TaskAttachments = $Results.TaskAttachments
                $Results = $Results.Results
            }
        }

        # Get tenant information
        $TenantInfo = Get-Tenants -TenantFilter $TenantFilter

        # Build HTML with adaptive table styling
        $TableDesign = '<style>table.adaptiveTable{border:1px solid currentColor;background-color:transparent;width:100%;text-align:left;border-collapse:collapse;opacity:0.9}table.adaptiveTable td,table.adaptiveTable th{border:1px solid currentColor;padding:8px 6px;opacity:0.8}table.adaptiveTable tbody td{font-size:13px}table.adaptiveTable tr:nth-child(even){background-color:rgba(128,128,128,0.1)}table.adaptiveTable thead{background-color:rgba(128,128,128,0.2);border-bottom:2px solid currentColor}table.adaptiveTable thead th{font-size:15px;font-weight:700;border-left:1px solid currentColor}table.adaptiveTable thead th:first-child{border-left:none}table.adaptiveTable tfoot{font-size:14px;font-weight:700;background-color:rgba(128,128,128,0.1);border-top:2px solid currentColor}table.adaptiveTable tfoot td{font-size:14px}@media (prefers-color-scheme: dark){table.adaptiveTable{opacity:0.95}table.adaptiveTable tr:nth-child(even){background-color:rgba(255,255,255,0.05)}table.adaptiveTable thead{background-color:rgba(255,255,255,0.1)}table.adaptiveTable tfoot{background-color:rgba(255,255,255,0.05)}}</style>'
        $FinalResults = if ($Results -is [array] -and $Results[0] -is [string]) {
            $Results | ConvertTo-Html -Fragment -Property @{ l = 'Text'; e = { $_ } }
        } else {
            $Results | ConvertTo-Html -Fragment
        }
        $HTML = $FinalResults -replace '<table>', "This alert is for tenant $TenantFilter. <br /><br /> $TableDesign<table class=adaptiveTable>" | Out-String

        # For alert tasks, add per-row snooze links to the email
        if ($TaskType -eq 'Alert' -and $Results -is [array] -and $Results.Count -gt 0 -and $Results[0] -isnot [string]) {
            try {
                $CippConfigTable = Get-CippTable -tablename Config
                $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
                $CIPPURL = if ($CippConfig.Value) { 'https://{0}' -f $CippConfig.Value } else { $null }

                if ($CIPPURL) {
                    $CmdletName = $TaskInfo.Command
                    $SnoozeLinksHtml = @'
<div style="margin:20px 0;padding:20px;border-left:4px solid #ff9800;">
<h4 style="margin-top:0;color:#ff9800;">Snooze Individual Alerts</h4>
<p style="margin:0 0 12px;font-size:13px;">Click a button to snooze that specific alert item. You will need to be signed in to CIPP.</p>
'@
                    foreach ($ResultItem in $Results) {
                        $HashResult = Get-AlertContentHash -AlertItem $ResultItem
                        $ItemPreview = [System.Web.HttpUtility]::HtmlEncode($HashResult.ContentPreview)
                        $EncodedData = [System.Web.HttpUtility]::UrlEncode(($ResultItem | ConvertTo-Json -Compress -Depth 5))
                        $EncodedCmdlet = [System.Web.HttpUtility]::UrlEncode($CmdletName)
                        $EncodedTenant = [System.Web.HttpUtility]::UrlEncode($TenantFilter)
                        $BaseLink = "${CIPPURL}/cipp/snooze-alert?cmdlet=${EncodedCmdlet}&tenant=${EncodedTenant}&data=${EncodedData}"
                        $SnoozeLinksHtml += @"
<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;border-bottom:1px solid #e0e0e0;padding-bottom:12px;">
<tr><td style="font-size:13px;padding:0 0 8px 0;font-weight:600;">$ItemPreview</td></tr>
<tr><td>
<table cellpadding="0" cellspacing="0" border="0"><tr>
<td style="padding:0 6px 0 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#0078d4;padding:6px 14px;"><a href="${BaseLink}&duration=7" style="color:#ffffff;font-size:12px;font-weight:600;text-decoration:none;white-space:nowrap;">7 Days</a></td></tr></table></td>
<td style="padding:0 6px 0 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#0078d4;padding:6px 14px;"><a href="${BaseLink}&duration=14" style="color:#ffffff;font-size:12px;font-weight:600;text-decoration:none;white-space:nowrap;">14 Days</a></td></tr></table></td>
<td style="padding:0 6px 0 0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#ff9800;padding:6px 14px;"><a href="${BaseLink}&duration=30" style="color:#ffffff;font-size:12px;font-weight:600;text-decoration:none;white-space:nowrap;">30 Days</a></td></tr></table></td>
<td style="padding:0;"><table cellpadding="0" cellspacing="0" border="0"><tr><td style="background-color:#d32f2f;padding:6px 14px;"><a href="${BaseLink}&duration=90" style="color:#ffffff;font-size:12px;font-weight:600;text-decoration:none;white-space:nowrap;">90 Days</a></td></tr></table></td>
</tr></table>
</td></tr>
</table>
"@
                    }
                    $SnoozeLinksHtml += '</div>'
                    $HTML += $SnoozeLinksHtml
                }
            } catch {
                Write-Information "Failed to generate snooze links for email: $($_.Exception.Message)"
            }
        }

        # Add alert comment if available
        if ($TaskInfo.AlertComment) {
            $AlertComment = $TaskInfo.AlertComment

            # Replace %resultcount% variable
            if ($AlertComment -match '%resultcount%') {
                $resultCount = if ($Results -is [array]) { $Results.Count } else { 1 }
                $AlertComment = $AlertComment -replace '%resultcount%', "$resultCount"
            }

            # Replace other variables
            $AlertComment = Get-CIPPTextReplacement -Text $AlertComment -TenantFilter $TenantFilter
            $HTML += "<div style='background-color: transparent; border-left: 4px solid #007bff; padding: 15px; margin: 15px 0;'><h4 style='margin-top: 0; color: #007bff;'>Alert Information</h4><p style='margin-bottom: 0;'>$AlertComment</p></div>"
        }

        # Build title
        $title = "$TaskType - $TenantFilter - $($TaskInfo.Name)"
        if ($TaskInfo.Reference) {
            $title += " - Reference: $($TaskInfo.Reference)"
        }

        Write-Information 'Scheduler: Sending the results to configured targets.'

        $NotificationTable = Get-CIPPTable -TableName SchedulerConfig
        $NotificationFilter = "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'"
        $NotificationConfig = [pscustomobject](Get-CIPPAzDataTableEntity @NotificationTable -Filter $NotificationFilter)
        $UseStandardizedSchema = [boolean]$NotificationConfig.UseStandardizedSchema

        # Send to configured alert targets
        switch -wildcard ($TaskInfo.PostExecution) {
            '*psa*' {
                Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML -TenantFilter $TenantFilter
            }
            '*email*' {
                $EmailParams = @{
                    Type         = 'email'
                    Title        = $title
                    HTMLContent  = $HTML
                    TenantFilter = $TenantFilter
                }
                if ($TaskAttachments) {
                    $EmailParams.Attachments = $TaskAttachments
                }
                Send-CIPPAlert @EmailParams
            }
            '*webhook*' {
                # Build per-item snooze metadata for alert tasks
                $SnoozeInfo = $null
                if ($TaskType -eq 'Alert' -and $Results -is [array] -and $Results.Count -gt 0 -and $Results[0] -isnot [string]) {
                    try {
                        $SnoozeInfo = [PSCustomObject]@{
                            apiEndpoint = '/api/ExecSnoozeAlert'
                            cmdletName  = $TaskInfo.Command
                            tenant      = $TenantFilter
                            durations   = @(7, 14, 30, -1)
                            items       = @($Results | ForEach-Object {
                                    $HashResult = Get-AlertContentHash -AlertItem $_
                                    [PSCustomObject]@{
                                        contentHash    = $HashResult.ContentHash
                                        contentPreview = $HashResult.ContentPreview
                                        alertItem      = $_
                                    }
                                })
                        }
                    } catch {
                        Write-Information "Failed to generate snooze metadata for webhook: $($_.Exception.Message)"
                    }
                }

                $Webhook = if ($UseStandardizedSchema) {
                    $obj = [PSCustomObject]@{
                        tenantId     = $TenantInfo.customerId
                        tenant       = $TenantFilter
                        taskType     = $TaskType
                        task         = [PSCustomObject]@{
                            id        = $TaskInfo.RowKey
                            name      = $TaskInfo.Name
                            command   = $TaskInfo.Command
                            state     = $TaskInfo.TaskState
                            reference = $TaskInfo.Reference
                            scheduled = $TaskInfo.ScheduledTime
                            executed  = $TaskInfo.ExecutedTime
                            partition = $TaskInfo.PartitionKey
                        }
                        results      = $Results
                        alertComment = $TaskInfo.AlertComment
                    }
                    if ($SnoozeInfo) { $obj | Add-Member -NotePropertyName 'snooze' -NotePropertyValue $SnoozeInfo }
                    $obj
                } else {
                    $obj = [PSCustomObject]@{
                        tenantId     = $TenantInfo.customerId
                        Tenant       = $TenantFilter
                        TaskInfo     = $TaskInfo
                        Results      = $Results
                        AlertComment = $TaskInfo.AlertComment
                    }
                    if ($SnoozeInfo) { $obj | Add-Member -NotePropertyName 'Snooze' -NotePropertyValue $SnoozeInfo }
                    $obj
                }
                Send-CIPPAlert -Type 'webhook' -Title $title -TenantFilter $TenantFilter -JSONContent $($Webhook | ConvertTo-Json -Depth 20) -APIName 'Scheduled Task Alerts' -SchemaSource $TaskType -InvokingCommand $TaskInfo.Command -UseStandardizedSchema:$UseStandardizedSchema
            }
        }

        Write-Information "Successfully sent alerts for task $($TaskInfo.Name)"

    } catch {
        Write-Warning "Failed to send scheduled task alerts: $($_.Exception.Message)"
        Write-LogMessage -API 'Scheduler_Alerts' -tenant $TenantFilter -message "Failed to send alerts for task $($TaskInfo.Name): $($_.Exception.Message)" -sev Error
    }
}
