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
        [string]$TaskType = 'Scheduled Task'
    )

    try {
        Write-Information "Sending post-execution alerts for task $($TaskInfo.Name)"

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

        # Send to configured alert targets
        switch -wildcard ($TaskInfo.PostExecution) {
            '*psa*' {
                Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML -TenantFilter $TenantFilter
            }
            '*email*' {
                Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML -TenantFilter $TenantFilter
            }
            '*webhook*' {
                $Webhook = [PSCustomObject]@{
                    'tenantId'     = $TenantInfo.customerId
                    'Tenant'       = $TenantFilter
                    'TaskInfo'     = $TaskInfo
                    'Results'      = $Results
                    'AlertComment' = $TaskInfo.AlertComment
                }
                Send-CIPPAlert -Type 'webhook' -Title $title -TenantFilter $TenantFilter -JSONContent $($Webhook | ConvertTo-Json -Depth 20)
            }
        }

        Write-Information "Successfully sent alerts for task $($TaskInfo.Name)"

    } catch {
        Write-Warning "Failed to send scheduled task alerts: $($_.Exception.Message)"
        Write-LogMessage -API 'Scheduler_Alerts' -tenant $TenantFilter -message "Failed to send alerts for task $($TaskInfo.Name): $($_.Exception.Message)" -sev Error
    }
}
