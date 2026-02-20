function Get-CIPPAlertNewMFADevice {
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
        $OneHourAgo = (Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')

        $AuditLogs = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $OneHourAgo and (activityDisplayName eq 'User registered security info' or activityDisplayName eq 'User deleted security info')" -tenantid $TenantFilter
        $AlertData = foreach ($Log in $AuditLogs) {
            if ($Log.activityDisplayName -eq 'User registered security info') {
                $User = $Log.targetResources[0].userPrincipalName
                if (-not $User) { $User = $Log.initiatedBy.user.userPrincipalName }

                [PSCustomObject]@{
                    Message      = "New MFA method registered: $User"
                    User         = $User
                    DisplayName  = $Log.targetResources[0].displayName
                    Activity     = $Log.activityDisplayName
                    ActivityTime = $Log.activityDateTime
                    Tenant       = $TenantFilter
                }
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Could not check for new MFA devices for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
