function Invoke-ListLogs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable

    $TemplatesTable = Get-CIPPTable -tablename 'templates'
    $Templates = Get-CIPPAzDataTableEntity @TemplatesTable

    $ReturnedLog = if ($Request.Query.ListLogs) {
        Get-AzDataTableEntity @Table -Property PartitionKey | Sort-Object -Unique PartitionKey | Select-Object PartitionKey | ForEach-Object {
            @{
                value = $_.PartitionKey
                label = $_.PartitionKey
            }
        }
    } elseif ($Request.Query.logentryid) {
        # Return single log entry by RowKey
        $Filter = "RowKey eq '{0}'" -f $Request.Query.logentryid
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        Write-Host "Getting single log entry for RowKey: $($Request.Query.logentryid)"

        $Row = Get-AzDataTableEntity @Table -Filter $Filter

        if ($Row) {
            if ($AllowedTenants -notcontains 'AllTenants') {
                $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
            }

            if ($AllowedTenants -contains 'AllTenants' -or ($AllowedTenants -notcontains 'AllTenants' -and ($TenantList.defaultDomainName -contains $Row.Tenant -or $Row.Tenant -eq 'CIPP' -or $TenantList.customerId -contains $Row.TenantId)) ) {

                if ($Row.StandardTemplateId) {
                    $Standard = ($Templates | Where-Object { $_.RowKey -eq $Row.StandardTemplateId }).JSON | ConvertFrom-Json

                    $StandardInfo = @{
                        Template = $Standard.templateName
                        Standard = $Row.Standard
                    }

                    if ($Row.IntuneTemplateId) {
                        $IntuneTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.IntuneTemplateId }).JSON | ConvertFrom-Json
                        $StandardInfo.IntunePolicy = $IntuneTemplate.displayName
                    }
                    if ($Row.ConditionalAccessTemplateId) {
                        $ConditionalAccessTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.ConditionalAccessTemplateId }).JSON | ConvertFrom-Json
                        $StandardInfo.ConditionalAccessPolicy = $ConditionalAccessTemplate.displayName
                    }

                } else {
                    $StandardInfo = @{}
                }

                $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                    $Row.LogData | ConvertFrom-Json
                } else { $Row.LogData }
                [PSCustomObject]@{
                    DateTime = $Row.Timestamp
                    Tenant   = $Row.Tenant
                    API      = $Row.API
                    Message  = $Row.Message
                    User     = $Row.Username
                    Severity = $Row.Severity
                    LogData  = $LogData
                    TenantID = if ($Row.TenantID -ne $null) {
                        $Row.TenantID
                    } else {
                        'None'
                    }
                    AppId    = $Row.AppId
                    IP       = $Row.IP
                    RowKey   = $Row.RowKey
                    Standard = $StandardInfo
                }
            }
        }
    } else {
        if ($request.Query.Filter -eq 'True') {
            $LogLevel = if ($Request.Query.Severity) { ($Request.query.Severity).split(',') } else { 'Info', 'Warn', 'Error', 'Critical', 'Alert' }
            $PartitionKey = $Request.Query.DateFilter
            $username = $Request.Query.User ?? '*'
            $TenantFilter = $Request.Query.Tenant
            $ApiFilter = $Request.Query.API
            $StandardFilter = $Request.Query.StandardTemplateId
            $ScheduledTaskFilter = $Request.Query.ScheduledTaskId

            $StartDate = $Request.Query.StartDate ?? $Request.Query.DateFilter
            $EndDate = $Request.Query.EndDate ?? $Request.Query.DateFilter

            if ($StartDate -and $EndDate) {
                # Collect logs for date range
                $Filter = "PartitionKey ge '$StartDate' and PartitionKey le '$EndDate'"
            } elseif ($StartDate) {
                $Filter = "PartitionKey eq '{0}'" -f $StartDate
            } else {
                $Filter = "PartitionKey eq '{0}'" -f (Get-Date -UFormat '%Y%m%d')
            }
        } else {
            $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
            $PartitionKey = Get-Date -UFormat '%Y%m%d'
            $username = '*'
            $TenantFilter = $null
            $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
        }
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        Write-Host "Getting logs for filter: $Filter, LogLevel: $LogLevel, Username: $username"

        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object {
            $_.Severity -in $LogLevel -and
            $_.Username -like $username -and
            ([string]::IsNullOrEmpty($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $_.Tenant -like "*$TenantFilter*" -or $_.TenantID -eq $TenantFilter) -and
            ([string]::IsNullOrEmpty($ApiFilter) -or $_.API -match "$ApiFilter") -and
            ([string]::IsNullOrEmpty($StandardFilter) -or $_.StandardTemplateId -eq $StandardFilter) -and
            ([string]::IsNullOrEmpty($ScheduledTaskFilter) -or $_.ScheduledTaskId -eq $ScheduledTaskFilter)
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            $TenantList = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -in $AllowedTenants }
        }

        foreach ($Row in $Rows) {
            if ($AllowedTenants -contains 'AllTenants' -or ($AllowedTenants -notcontains 'AllTenants' -and ($TenantList.defaultDomainName -contains $Row.Tenant -or $Row.Tenant -eq 'CIPP' -or $TenantList.customerId -contains $Row.TenantId)) ) {
                if ($StandardTaskFilter -and $Row.StandardTemplateId) {
                    $Standard = ($Templates | Where-Object { $_.RowKey -eq $Row.StandardTemplateId }).JSON | ConvertFrom-Json

                    $StandardInfo = @{
                        Template = $Standard.templateName
                        Standard = $Row.Standard
                    }

                    if ($Row.IntuneTemplateId) {
                        $IntuneTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.IntuneTemplateId }).JSON | ConvertFrom-Json
                        $StandardInfo.IntunePolicy = $IntuneTemplate.displayName
                    }
                    if ($Row.ConditionalAccessTemplateId) {
                        $ConditionalAccessTemplate = ($Templates | Where-Object { $_.RowKey -eq $Row.ConditionalAccessTemplateId }).JSON | ConvertFrom-Json
                        $StandardInfo.ConditionalAccessPolicy = $ConditionalAccessTemplate.displayName
                    }
                } else {
                    $StandardInfo = @{}
                }

                $LogData = if ($Row.LogData -and (Test-Json -Json $Row.LogData -ErrorAction SilentlyContinue)) {
                    $Row.LogData | ConvertFrom-Json
                } else { $Row.LogData }
                [PSCustomObject]@{
                    DateTime     = $Row.Timestamp
                    Tenant       = $Row.Tenant
                    API          = $Row.API
                    Message      = $Row.Message
                    User         = $Row.Username
                    Severity     = $Row.Severity
                    LogData      = $LogData
                    TenantID     = if ($Row.TenantID -ne $null) {
                        $Row.TenantID
                    } else {
                        'None'
                    }
                    AppId        = $Row.AppId
                    IP           = $Row.IP
                    RowKey       = $Row.RowKey
                    StandardInfo = $StandardInfo
                }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($ReturnedLog | Sort-Object -Property DateTime -Descending)
    }

}
