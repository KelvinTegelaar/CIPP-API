function Get-CIPPAlertGroupMembershipChange {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $MonitoredGroups = $InputValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if (!$MonitoredGroups) { return $true }

        $OneHourAgo = (Get-Date).AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $AuditLogs = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $OneHourAgo and (activityDisplayName eq 'Add member to group' or activityDisplayName eq 'Remove member from group')" -tenantid $TenantFilter

        $AlertData = foreach ($Log in $AuditLogs) {
            $Member = ($Log.targetResources | Where-Object { $_.type -in @('User', 'ServicePrincipal') })[0]
            $GroupProp = ($Member.modifiedProperties | Where-Object { $_.displayName -eq 'Group.DisplayName' })
            $GroupDisplayName = (($GroupProp.newValue ?? $GroupProp.oldValue) -replace '"', '')
            if (!$GroupDisplayName -or !($MonitoredGroups | Where-Object { $GroupDisplayName -like $_ })) { continue }

            $InitiatedBy = if ($Log.initiatedBy.user) { $Log.initiatedBy.user.userPrincipalName } else { $Log.initiatedBy.app.displayName }
            $Action = if ($Log.activityDisplayName -eq 'Add member to group') { 'added to' } else { 'removed from' }

            [PSCustomObject]@{
                Message      = "$($Member.userPrincipalName ?? $Member.displayName) was $Action group '$GroupDisplayName' by $InitiatedBy"
                GroupName    = $GroupDisplayName
                MemberName   = $Member.userPrincipalName ?? $Member.displayName
                Action       = $Log.activityDisplayName
                InitiatedBy  = $InitiatedBy
                ActivityTime = $Log.activityDateTime
                Tenant       = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not check group membership changes for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
