function Send-CIPPJITAdminApprovalNotification {
    <#
    .SYNOPSIS
        Sends a JIT admin approval request event through the configured notification methods and to push subscribers
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $ApprovalRequest,
        [ValidateSet('Requested', 'Approved', 'Rejected')]
        [string]$Status,
        [string]$Note,
        [string[]]$Results
    )

    try {
        $Tenant = $ApprovalRequest.Tenant
        $Title = switch ($Status) {
            'Requested' { "JIT Admin approval requested: $($ApprovalRequest.TargetUser) ($Tenant)" }
            'Approved' { "JIT Admin request approved: $($ApprovalRequest.TargetUser) ($Tenant)" }
            'Rejected' { "JIT Admin request rejected: $($ApprovalRequest.TargetUser) ($Tenant)" }
        }
        $Path = '/identity/administration/jit-admin/requests'
        $ConfigTable = Get-CIPPTable -TableName Config
        $CippUrl = (Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'").Value

        $Details = [ordered]@{
            Event          = $Status
            'Request ID'   = $ApprovalRequest.RowKey
            Tenant         = $Tenant
            User           = $ApprovalRequest.TargetUser
            Roles          = $ApprovalRequest.RoleNames
            Groups         = $ApprovalRequest.GroupNames
            Start          = [DateTimeOffset]::FromUnixTimeSeconds([int64]$ApprovalRequest.StartDate).UtcDateTime.ToString('u')
            End            = [DateTimeOffset]::FromUnixTimeSeconds([int64]$ApprovalRequest.EndDate).UtcDateTime.ToString('u')
            Reason         = $ApprovalRequest.Reason
            'Requested by' = $ApprovalRequest.RequestedBy
            Note           = $Note
            Results        = $Results -join '; '
        }
        $Rows = foreach ($Key in $Details.Keys) {
            if ($Details[$Key]) { '<tr><th align="left">{0}</th><td>{1}</td></tr>' -f $Key, [System.Net.WebUtility]::HtmlEncode([string]$Details[$Key]) }
        }
        $Link = if ($CippUrl) { '<p><a href="https://{0}{1}">Open JIT Admin requests in CIPP</a></p>' -f $CippUrl, $Path }
        $Html = "<h3>$([System.Net.WebUtility]::HtmlEncode($Title))</h3><table>$($Rows -join '')</table>$Link"

        $NotifyTable = Get-CIPPTable -TableName SchedulerConfig
        $Config = Get-CIPPAzDataTableEntity @NotifyTable -Filter "PartitionKey eq 'CippNotifications' and RowKey eq 'CippNotifications'"
        if ($Config.email) { $null = Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $Html -TenantFilter $Tenant -APIName 'JITAdminApproval' }
        if ($Config.webhook) { $null = Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent ([pscustomobject]$Details) -TenantFilter $Tenant -APIName 'JITAdminApproval' }
        if ($Config.sendtoIntegration) { $null = Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $Html -TenantFilter $Tenant -APIName 'JITAdminApproval' }

        # Push is CIPP-NG only: approvers come from allowedUsers, which only CIPP-NG populates
        if ($env:CIPPNG -ne 'true') { return }
        $PushTargets = if ($Status -eq 'Requested') {
            $ApproverRoles = @($ApprovalRequest.ApproverRoles | ConvertFrom-Json)
            $UsersTable = Get-CIPPTable -TableName 'allowedUsers'
            foreach ($CippUser in (Get-CIPPAzDataTableEntity @UsersTable -Filter "PartitionKey eq 'User'")) {
                if ($CippUser.RowKey -eq $ApprovalRequest.RequestedBy -or -not $CippUser.Roles) { continue }
                if (@($CippUser.Roles | ConvertFrom-Json).Where({ $_ -in $ApproverRoles }).Count -gt 0) { $CippUser.RowKey }
            }
        } else {
            $ApprovalRequest.RequestedBy
        }
        foreach ($Target in $PushTargets) {
            $null = Send-CIPPAlert -Type 'push' -Title $Title -TargetUser $Target -PushMessage "$($ApprovalRequest.RoleNames) $($ApprovalRequest.GroupNames)".Trim() -Url $Path -APIName 'JITAdminApproval'
        }
    } catch {
        Write-LogMessage -API 'JITAdminApproval' -tenant $ApprovalRequest.Tenant -message "Failed to send JIT admin approval notification: $($_.Exception.Message)" -Sev 'Warning'
    }
}
