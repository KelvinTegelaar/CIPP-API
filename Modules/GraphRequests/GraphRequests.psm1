using namespace System.Net

function Get-StringHash {
    Param($String)
    $StringBuilder = New-Object System.Text.StringBuilder
    [System.Security.Cryptography.HashAlgorithm]::Create('SHA1').ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String)) | ForEach-Object {
        [Void]$StringBuilder.Append($_.ToString('x2'))
    }
    $StringBuilder.ToString()
}
function Get-GraphRequestList {
    [CmdletBinding()]
    Param(
        $Tenant = $env:TenantId,
        [Parameter(Mandatory = $true)]
        $Endpoint,
        $Parameters,
        $QueueId,
        $CippLink,
        [ValidateSet('v1.0', 'beta')]
        $Version = 'beta',
        [switch]$SkipCache,
        [switch]$ClearCache
    )

    $TableName = 'cache{0}' -f ($Endpoint -replace '/')
    $Table = Get-CIPPTable -TableName $TableName
    $TextInfo = (Get-Culture).TextInfo
    $QueueName = $TextInfo.ToTitleCase($Endpoint -csplit '(?=[A-Z])' -ne '' -join ' ')

    $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }
    $GraphQuery.Query = $ParamCollection.ToString()
    $PartitionKey = Get-StringHash -String (@($QueueTenant.Endpoint, $ParamCollection.ToString()) -join '-')

    Write-Host $GraphQuery.ToString()

    if ($QueueId) {
        $Filter = "QueueId = '{0}'" -f $QueueId
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter
        $Type = 'Queue'
    } elseif (!$SkipCache.IsPresent -and !$ClearCache.IsPresent) {
        if ($Tenant -eq 'AllTenants') {
            $Filter = "PartitionKey eq '{0}' and QueueType eq 'AllTenants'" -f $PartitionKey
        } else {
            $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $Tenant
        }
        Write-Host $Filter
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Timestamp.DateTime -gt (Get-Date).ToUniversalTime().AddHours(-1) }
        $Type = 'Cache'
    } else {
        $Type = 'None'
        $Rows = @()
    }

    Write-Host "Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"

    <#############

    return [PSCustomObject]@{
        Tenant  = 'Data still processing, please wait'
        QueueId = $RunningQueue.RowKey
    }
    #############>

    $QueueReference = '{0}-{1}' -f $Tenant, $PartitionKey
    $RunningQueue = Get-CippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' }

    if (!$Rows) {
        switch ($Tenant) {
            'AllTenants' {
                if ($RunningQueue) {
                    Write-Host 'Queue currently running'
                    Write-Host ($RunningQueue | ConvertTo-Json)
                    [PSCustomObject]@{
                        Tenant  = 'Data still processing, please wait'
                        QueueId = $RunningQueue.RowKey
                    }
                } else {
                    $Queue = New-CippQueueEntry -Name "$QueueName (All Tenants)" -Link $CippLink -Reference $QueueReference
                    [PSCustomObject]@{
                        Tenant  = 'Loading data for all tenants. Please check back after the job completes'
                        QueueId = $Queue.RowKey
                    }

                    Get-Tenants | ForEach-Object {
                        $Tenant = $_.defaultDomainName
                        $QueueTenant = @{
                            Tenant       = $Tenant
                            Endpoint     = $Endpoint
                            QueueId      = $Queue.RowKey
                            QueueName    = $QueueName
                            QueueType    = 'AllTenants'
                            Parameters   = $Parameters
                            PartitionKey = $PartitionKey
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
                        if ($Count -gt 8000) {
                            Write-Host "Query results: $Count"
                            $QueueThresholdExceeded = $true
                            if ($RunningQueue) {
                                Write-Host 'Queue currently running'
                                Write-Host ($RunningQueue | ConvertTo-Json)
                                [PSCustomObject]@{
                                    Tenant  = 'Data still processing, please wait'
                                    QueueId = $RunningQueue.RowKey
                                }
                            } else {
                                $Queue = New-CippQueueEntry -Name $QueueName -Link $CippLink -Reference $QueueReference
                                $QueueTenant = @{
                                    Tenant       = $Tenant
                                    Endpoint     = $Endpoint
                                    QueueId      = $Queue.RowKey
                                    QueueName    = $QueueName
                                    QueueType    = 'SingleTenant'
                                    Parameters   = $Parameters
                                    PartitionKey = $PartitionKey
                                } | ConvertTo-Json -Depth 5 -Compress

                                Push-OutputBinding -Name QueueTenant -Value $QueueTenant
                                [PSCustomObject]@{
                                    Tenant  = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $Tenant)
                                    QueueId = $Queue.RowKey
                                }
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
    Write-Host ($QueueTenant | ConvertTo-Json -Depth 5)

    $TenantQueueName = '{0} - {1}' -f $QueueTenant.QueueName, $QueueTenant.Tenant
    Update-CippQueueEntry -RowKey $QueueTenant.QueueId -Status 'Processing' -Name $TenantQueueName

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($QueueTenant.Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    $PartitionKey = $QueueTenant.PartitionKey

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

    $GraphResults = foreach ($Request in $RawGraphRequest) {
        $Json = ConvertTo-Json -Depth 5 -Compress -InputObject $Request
        [PSCustomObject]@{
            Tenant       = [string]$QueueTenant.Tenant
            QueueId      = [string]$QueueTenant.QueueId
            QueueType    = [string]$QueueTenant.QueueType
            RowKey       = [string](New-Guid)
            PartitionKey = [string]$PartitionKey
            Data         = [string]$Json
        }
    }
    try {
        Add-AzDataTableEntity @Table -Entity $GraphResults -Force | Out-Null
        Update-CippQueueEntry -RowKey $QueueTenant.QueueId -Status 'Completed'
    } catch {
        Write-Host "Queue Error: $($_.Exception.Message)"
        Update-CippQueueEntry -RowKey $QueueTenant.QueueId -Status 'Failed'
    }
}

function Get-GraphRequestListHttp {
    # Input bindings are passed in via param block.
    param($Request, $TriggerMetadata)

    $CippLink = ([System.Uri]$TriggerMetadata.Headers.referer).PathAndQuery

    $Parameters = @{}
    if ($Request.Query.'$filter') {
        $Parameters.'$filter' = $Request.Query.'$filter'
    }

    if (!$Request.Query.'$filter' -and $Request.Query.graphFilter) {
        $Parameters.'$filter' = $Request.Query.graphFilter
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

    if ($Request.Query.'$orderby') {
        $Parameters.'$orderby' = $Request.Query.'$orderby'
    }

    $GraphRequestParams = @{
        Endpoint   = $Request.Query.Endpoint
        Parameters = $Parameters
        CippLink   = $CippLink
    }

    if ($Request.Query.TenantFilter) {
        $GraphRequestParams.Tenant = $Request.Query.TenantFilter
    }

    if ($Request.Query.QueueId) {
        $GraphRequestParams.QueueId = $Request.Query.QueueId
    }

    if ($Request.Query.Version) {
        $GraphRequestParams.Version = $Request.Query.Version
    }

    Write-Host ($GraphRequestParams | ConvertTo-Json)
    try {
        $GraphRequestData = Get-GraphRequestList @GraphRequestParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $GraphRequestData = "Graph Error: $($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequestData)
        })
}


Export-ModuleMember -Function @('Get-GraphRequestList', 'Get-GraphRequestListHttp', 'Push-GraphRequestListQueue')
