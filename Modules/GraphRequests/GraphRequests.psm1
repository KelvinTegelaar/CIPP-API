using namespace System.Net
function Get-GraphRequestList {
    [CmdletBinding()]
    Param(
        $Tenant = $env:TenantId,
        [Parameter(Mandatory = $true)]
        $Endpoint,
        $Parameters,
        $QueueId,
        $CippLink,
        [switch]$SkipCache,
        [switch]$ClearCache
    )

    $TableName = 'cache{0}' -f ($Endpoint -replace '/')
    $Table = Get-CIPPTable -TableName $TableName
    $TextInfo = (Get-Culture).TextInfo
    $QueueName = $TextInfo.ToTitleCase($Endpoint -csplit '(?=[A-Z])' -ne '' -join ' ')

    $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/beta/{0}' -f $Endpoint)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }
    $GraphQuery.Query = $ParamCollection.ToString()

    Write-Host $GraphQuery.ToString()

    if (!$SkipCache -and !$ClearCache) {
        $PartitionKey = '{0}-{1}' -f $Endpoint, $ParamCollection.ToString()
        if ($Tenant -eq 'AllTenants') {
            $Filter = "PartitionKey eq '{0}' and QueueType eq 'AllTenants'" -f $PartitionKey
        } else {
            $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $Tenant
        }
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
    } else {
        $Rows = @()
    }

    Write-Host "$(($Rows | Measure-Object).Count) rows"

    if (!$Rows) {
        switch ($Tenant) {
            'AllTenants' {
                $Rows = Get-AzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
                if (!$Rows) {
                    $Queue = New-CippQueueEntry -Name "$QueueName (All Tenants)" -Link $CippLink

                    [PSCustomObject]@{
                        Tenant  = 'Loading data for all tenants. Please check back after the job completes'
                        QueueId = $Queue.RowKey
                    }

                    Get-Tenants | ForEach-Object {
                        $Tenant = $_.defaultDomainName
                        $QueueTenant = @{
                            Tenant     = $Tenant
                            Endpoint   = $Endpoint
                            QueueId    = $Queue.RowKey
                            QueueName  = $QueueName
                            QueueType  = 'AllTenants'
                            Parameters = $Parameters
                        } | ConvertTo-Json -Depth 5 -Compress

                        Push-OutputBinding -Name QueueTenant -Value $QueueTenant
                    }
                }
            }
            default {
                $GraphRequest = @{
                    uri           = $GraphQuery.ToString()
                    tenantid      = $Tenant
                    ComplexFilter = $true
                }
                try {
                    $QueueThresholdExceeded = $false
                    if ($Parameters.'$count' -and !$SkipCache) {
                        $Count = New-GraphGetRequest @GraphRequest -CountOnly -ErrorAction Stop
                        if ($Count -gt 5000) {
                            $QueueThresholdExceeded = $true
                            $Queue = New-CippQueueEntry -Name $QueueName -Link $CippLink
                            $QueueTenant = @{
                                Tenant     = $Tenant
                                Endpoint   = $Endpoint
                                QueueId    = $Queue.RowKey
                                QueueName  = $QueueName
                                QueueType  = 'SingleTenant'
                                Parameters = $Parameters
                            } | ConvertTo-Json -Depth 5 -Compress

                            Push-OutputBinding -Name QueueTenant -Value $QueueTenant
                            [PSCustomObject]@{
                                Tenant  = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $Tenant)
                                QueueId = $Queue.RowKey
                            }
                        }
                    }

                    if (!$QueueThresholdExceeded) {
                        New-GraphGetRequest @GraphRequest -ErrorAction Stop
                    }

                } catch {
                    throw $_.Exception
                }
            }
        }
    } else {
        $Rows | ForEach-Object {
            $_.Data | ConvertFrom-Json
        }
    }
}

function Push-GraphRequestListQueue {
    # Input bindings are passed in via param block.
    param($QueueTenant, $TriggerMetadata)

    # Write out the queue message and metadata to the information log.
    Write-Host "PowerShell queue trigger function processed work item $QueueTenant"

    #$QueueTenant = $QueueTenant | ConvertFrom-Json
    Write-Host ($QueueTenant | ConvertTo-Json)

    $TenantQueueName = '{0} - {1}' -f $QueueTenant.QueueName, $QueueTenant.Tenant
    Update-CippQueueEntry -RowKey $QueueTenant.QueueId -Status 'Processing' -Name $TenantQueueName

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($QueueTenant.Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    $PartitionKey = @($QueueTenant.Endpoint, $ParamCollection.ToString()) -join '-'

    $TableName = 'cache{0}' -f ($QueueTenant.Endpoint -replace '/')
    $Table = Get-CIPPTable -TableName $TableName

    $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $QueueTenant.Tenant
    Write-Host $Filter
    Get-AzDataTableEntity @Table -Filter $Filter | Remove-AzDataTableEntity @table

    $GraphRequestParams = @{
        Tenant     = $QueueTenant.Tenant
        Endpoint   = $QueueTenant.Endpoint
        Parameters = $QueueTenant.Parameters
        SkipCache  = $true
    }

    $RawGraphRequest = try {
        Get-GraphRequestList @GraphRequestParams | Select-Object *, @{l = 'Tenant'; e = { $QueueTenant.Tenant } }, @{l = 'CippStatus'; e = { 'Good' } }
    } catch {
        [PSCustomObject]@{
            Tenant     = $QueueTenant.Tenant
            CippStatus = "Could not connect to tenant. $($_.Exception.message)"
        }
    }

    foreach ($Request in $RawGraphRequest) {
        $Json = ConvertTo-Json -Compress -InputObject $Request
        $GraphResults = [PSCustomObject]@{
            Tenant       = [string]$QueueTenant.Tenant
            QueueId      = [string]$QueueTenant.QueueId
            QueueType    = [string]$QueueTenant.QueueType
            RowKey       = [string](New-Guid)
            PartitionKey = [string]$PartitionKey
            Data         = [string]$Json
        }
        Add-AzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
    }

    Update-CippQueueEntry -RowKey $QueueTenant.QueueId -Status 'Completed'
}

function Get-GraphRequestListHttp {
    # Input bindings are passed in via param block.
    param($Request, $TriggerMetadata)

    Write-Host ($TriggerMetadata | ConvertTo-Json)

    $Parameters = @{}
    if ($Request.Query.'$filter') {
        $Parameters.'$filter' = $Request.Query.'$filter'
    }

    if ($Request.Query.'$select') {
        $Parameters.'$select' = $Request.Query.'$select'
    }

    if ($Request.Query.'$expand') {
        $Parameters.'$expand' = $Request.Query.'$expand'
    }

    if ($Request.Query.'$top') {
        $Parameters.'$top' = $Request.Query.'$top'
    }

    if ($Request.Query.'$count') {
        $Parameters.'$count' = $Request.Query.'$count'
    }

    $GraphRequestParams = @{
        Endpoint   = $Request.Query.Endpoint
        Parameters = $Parameters
        CippLink   = ''
    }

    if ($Request.Query.TenantFilter) {
        $GraphRequestParams.Tenant = $Request.Query.TenantFilter
    }

    if ($Request.Query.QueueId) {
        $GraphRequestParams.QueueId = $Request.Query.QueueId
    }

    Write-Host ($GraphRequestParams | ConvertTo-Json)
    $GraphRequestData = Get-GraphRequestList @GraphRequestParams

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequestData)
        })
}


Export-ModuleMember -Function @('Get-GraphRequestList', 'Get-GraphRequestListHttp', 'Push-GraphRequestListQueue')
