function Invoke-GetCippAlerts {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Returns the CIPP dashboard banner notifications: any hosted maintenance notice, today's most recent entries from the alert log, and warnings for an out-of-date or misconfigured deployment.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Alerts = [System.Collections.Generic.List[object]]::new()

    # Hosted maintenance notice, set as a JSON blob in CIPP_MAINTENANCE_NOTICE. Added first so it
    # sorts to the top of the banner stack. Self-suppresses once its end time has passed.
    $MaintenanceNotice = Get-CIPPMaintenanceNotice
    if ($MaintenanceNotice) { $Alerts.Add($MaintenanceNotice) }

    $Table = Get-CippTable -tablename CippAlerts
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
    $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object TableTimestamp -Descending | Select-Object -First 10
    $Role = Get-CippAccessRole -Request $Request

    $CIPPVersion = $Request.Query.localversion
    $Version = Assert-CippVersion -CIPPVersion $CIPPVersion
    if ($Version.OutOfDateCIPP) {
        $Alerts.Add(@{
                title = 'CIPP Frontend Out of Date'
                Alert = 'Your CIPP Frontend is out of date. Please update to the latest version. Find more on the following '
                link  = 'https://docs.cipp.app/setup/self-hosting-guide/updating'
                type  = 'warning'
            })
        Write-LogMessage -message 'Your CIPP Frontend is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert

    }
    if ($Version.OutOfDateCIPPAPI) {
        $Alerts.Add(@{
                title = 'CIPP API Out of Date'
                Alert = 'Your CIPP API is out of date. Please update to the latest version. Find more on the following'
                link  = 'https://docs.cipp.app/setup/self-hosting-guide/updating'
                type  = 'warning'
            })
        Write-LogMessage -message 'Your CIPP API is out of date. Please update to the latest version' -API 'Updates' -tenant 'All Tenants' -sev Alert
    }

    if ($env:ApplicationID -eq 'LongApplicationID' -or $null -eq $env:ApplicationID) {
        $Alerts.Add(@{
                title          = 'SAM Setup Incomplete'
                Alert          = 'You have not yet completed your setup. Please go to the Setup Wizard in Application Settings to connect CIPP to your tenants.'
                link           = '/cipp/setup'
                type           = 'warning'
                setupCompleted = $false
            })
    }
    if ($role -like '*superadmin*') {
        $Alerts.Add(@{
                title = 'Superadmin Account Warning'
                Alert = 'You are logged in under a superadmin account. This account should not be used for normal usage.'
                link  = 'https://docs.cipp.app/setup/installation/owntenant'
                type  = 'error'
            })
    }

    # Outstanding SAM permissions are only visible by opening the permissions page, so an
    # instance can sit needing consent without anyone noticing. Surface it here like the other
    # instance health warnings. Only shown to roles that can actually grant the consent.
    if ($Role | Where-Object { $_ -in @('admin', 'superadmin') }) {
        try {
            # Cached result only - this endpoint runs on every page load, and running the
            # permissions check itself makes a Graph call per service principal.
            $AccessTable = Get-CIPPTable -TableName 'AccessChecks'
            $PermissionCache = Get-CIPPAzDataTableEntity @AccessTable -Filter "PartitionKey eq 'AccessCheck' and RowKey eq 'AccessPermissions'"
            if ($PermissionCache.Data) {
                $MissingPermissions = ($PermissionCache.Data | ConvertFrom-Json -ErrorAction Stop).MissingPermissions
                $MissingCount = ($MissingPermissions | Measure-Object).Count
                if ($MissingCount -gt 0) {
                    $Alerts.Add(@{
                            title = 'Permissions to Apply'
                            Alert = ('CIPP has {0} new permission(s) to apply. Review and apply them on the permissions page: ' -f $MissingCount)
                            link  = '/cipp/settings/permissions'
                            type  = 'warning'
                        })
                }
            }
        } catch {
            # A missing or unreadable cache just means no banner - never break the alert list.
            Write-Information "Could not read the cached permissions check: $($_.Exception.Message)"
        }
    }
    $PSMinVersion = [Version]'7.4.0'
    if ($PSVersionTable.PSVersion -lt $PSMinVersion) {
        $Alerts.Add(@{
                title = 'PowerShell Version Out of Date'
                Alert = ('Your CIPP API is running PowerShell {0}. PowerShell 7.4 or later is required for full compatibility. Please update your Function App to use PowerShell 7.4. For hosted customers, please contact the helpdesk.' -f $PSVersionTable.PSVersion)
                link  = 'https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell#powershell-versions'
                type  = 'warning'
            })
        Write-LogMessage -message ('CIPP API is running PowerShell {0}. PowerShell 7.4 or later is required.' -f $PSVersionTable.PSVersion) -API 'Updates' -tenant 'All Tenants' -sev Alert
    }
    if (${env:CIPPNG} -ne 'true' -and !(![string]::IsNullOrEmpty($env:WEBSITE_RUN_FROM_PACKAGE) -or ![string]::IsNullOrEmpty($env:DEPLOYMENT_STORAGE_CONNECTION_STRING)) -and $env:AzureWebJobsStorage -ne 'UseDevelopmentStorage=true' -and $env:NonLocalHostAzurite -ne 'true') {
        $Alerts.Add(
            @{
                title = 'Function App in Write Mode'
                Alert = 'Your Function App is running in write mode. This will cause performance issues and increase cost. Please check this '
                link  = 'https://docs.cipp.app/setup/installation/runfrompackage'
                type  = 'warning'
            })
    }
    if ($Rows) { $Rows | ForEach-Object { $Alerts.Add($_) } }
    $Alerts = @($Alerts)

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Alerts
        })

}
