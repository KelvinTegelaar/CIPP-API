function Get-GraphRequestList {
    <#
    .SYNOPSIS
    Execute a Graph query

    .PARAMETER TenantFilter
    Tenant to query (or AllTenants)

    .PARAMETER Endpoint
    Graph API endpoint

    .PARAMETER Parameters
    API Parameters

    .PARAMETER QueueId
    Queue Id

    .PARAMETER CippLink
    Reference link for queueing

    .PARAMETER Version
    API Version - v1.0 or beta

    .PARAMETER QueueNameOverride
    Queue name to set

    .PARAMETER SkipCache
    Skip Caching

    .PARAMETER ClearCache
    Clear cached results

    .PARAMETER NoPagination
    Disable pagination

    .PARAMETER CountOnly
    Only return count of results

    .PARAMETER NoAuthCheck
    Skip auth check

    .PARAMETER ReverseTenantLookup
    Perform reverse tenant lookup

    .PARAMETER ReverseTenantLookupProperty
    Property to perform reverse tenant lookup

    #>
    [CmdletBinding()]
    Param(
        [string]$TenantFilter = $env:TenantId,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [hashtable]$Parameters = @{},
        [string]$QueueId,
        [string]$CippLink,
        [ValidateSet('v1.0', 'beta')]
        [string]$Version = 'beta',
        [string]$QueueNameOverride,
        [switch]$SkipCache,
        [switch]$ClearCache,
        [switch]$NoPagination,
        [switch]$CountOnly,
        [switch]$NoAuthCheck,
        [switch]$ReverseTenantLookup,
        [string]$ReverseTenantLookupProperty = 'tenantId'
    )

    $TableName = ('cache{0}' -f ($Endpoint -replace '[^A-Za-z0-9]'))[0..62] -join ''
    Write-Host "Table: $TableName"
    $Endpoint = $Endpoint -replace '^/', ''
    $DisplayName = ($Endpoint -split '/')[0]

    if ($QueueNameOverride) {
        $QueueName = $QueueNameOverride
    } else {
        $TextInfo = (Get-Culture).TextInfo
        $QueueName = $TextInfo.ToTitleCase($DisplayName -csplit '(?=[A-Z])' -ne '' -join ' ')
    }

    $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }
    $GraphQuery.Query = $ParamCollection.ToString()
    $PartitionKey = Get-StringHash -String (@($Endpoint, $ParamCollection.ToString()) -join '-')
    Write-Host "PK: $PartitionKey"

    Write-Host ( 'GET [ {0} ]' -f $GraphQuery.ToString())

    try {
        if ($QueueId) {
            $Table = Get-CIPPTable -TableName $TableName
            $Filter = "QueueId eq '{0}'" -f $QueueId
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            $Type = 'Queue'
        } elseif ($TenantFilter -eq 'AllTenants' -or (!$SkipCache.IsPresent -and !$ClearCache.IsPresent -and !$CountOnly.IsPresent)) {
            $Table = Get-CIPPTable -TableName $TableName
            if ($TenantFilter -eq 'AllTenants') {
                $Filter = "PartitionKey eq '{0}' and QueueType eq 'AllTenants'" -f $PartitionKey
            } else {
                $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $TenantFilter
            }
            #Write-Host $Filter
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Timestamp.DateTime -gt (Get-Date).ToUniversalTime().AddHours(-1) }
            $Type = 'Cache'
        } else {
            $Type = 'None'
            $Rows = @()
        }
        Write-Host "Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"


        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' }
    } catch {
        Write-Host $_.InvocationInfo.PositionMessage
    }

    if ($TenantFilter -ne 'AllTenants' -and $Endpoint -match '%tenantid%') {
        $TenantId = (Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }).customerId
        $Endpoint = $Endpoint -replace '%tenantid%', $TenantId
        $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
        $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
        foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
            $ParamCollection.Add($Item.Key, $Item.Value)
        }
        $GraphQuery.Query = $ParamCollection.ToString()
    }

    if (!$Rows) {
        switch ($TenantFilter) {
            'AllTenants' {
                if ($SkipCache) {
                    Get-Tenants -IncludeErrors | ForEach-Object -Parallel {
                        Import-Module AzBobbyTables
                        Import-Module CIPPCore

                        $GraphRequestParams = @{
                            TenantFilter                = $_.defaultDomainName
                            Endpoint                    = $using:Endpoint
                            Parameters                  = $using:Parameters
                            NoPagination                = $using:NoPagination.IsPresent
                            ReverseTenantLookupProperty = $using:ReverseTenantLookupProperty
                            ReverseTenantLookup         = $using:ReverseTenantLookup.IsPresent
                            SkipCache                   = $true
                        }

                        try {
                            Get-GraphRequestList @GraphRequestParams | Select-Object *, @{l = 'Tenant'; e = { $_.defaultDomainName } }, @{l = 'CippStatus'; e = { 'Good' } }
                        } catch {
                            [PSCustomObject]@{
                                Tenant     = $_.defaultDomainName
                                CippStatus = "Could not connect to tenant. $($_.Exception.message)"
                            }
                        }
                    }
                } else {
                    if ($RunningQueue) {
                        Write-Host 'Queue currently running'
                        Write-Host ($RunningQueue | ConvertTo-Json)
                        [PSCustomObject]@{
                            QueueMessage = 'Data still processing, please wait'
                            QueueId      = $RunningQueue.RowKey
                            Queued       = $true
                        }
                    } else {
                        $TenantList = Get-Tenants -IncludeErrors
                        $Queue = New-CippQueueEntry -Name "$QueueName (All Tenants)" -Link $CippLink -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                        [PSCustomObject]@{
                            QueueMessage = 'Loading data for all tenants. Please check back after the job completes'
                            Queued       = $true
                            QueueId      = $Queue.RowKey
                        }
                        Write-Host 'Pushing output bindings'
                        try {
                            $Batch = $TenantList | ForEach-Object {
                                $TenantFilter = $_.defaultDomainName
                                [PSCustomObject]@{
                                    FunctionName                = 'ListGraphRequestQueue'
                                    TenantFilter                = $TenantFilter
                                    Endpoint                    = $Endpoint
                                    QueueId                     = $Queue.RowKey
                                    QueueName                   = $TenantFilter
                                    QueueType                   = 'AllTenants'
                                    Parameters                  = $Parameters
                                    PartitionKey                = $PartitionKey
                                    NoPagination                = $NoPagination.IsPresent
                                    NoAuthCheck                 = $NoAuthCheck.IsPresent
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                }

                                #Push-OutputBinding -Name QueueItem -Value $QueueTenant
                            }

                            $InputObject = @{
                                OrchestratorName = 'GraphRequestOrchestrator'
                                Batch            = @($Batch)
                            }
                            #Write-Host ($InputObject | ConvertTo-Json -Depth 5)
                            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                        } catch {
                            Write-Host "QUEUE ERROR: $($_.Exception.Message)"
                        }
                    }
                }
            }
            default {
                $GraphRequest = @{
                    uri           = $GraphQuery.ToString()
                    tenantid      = $TenantFilter
                    ComplexFilter = $true
                }

                if ($NoPagination.IsPresent) {
                    $GraphRequest.noPagination = $NoPagination.IsPresent
                }

                if ($CountOnly.IsPresent) {
                    $GraphRequest.CountOnly = $CountOnly.IsPresent
                }

                if ($NoAuthCheck.IsPresent) {
                    $GraphRequest.noauthcheck = $NoAuthCheck.IsPresent
                }

                try {
                    $QueueThresholdExceeded = $false
                    if ($Parameters.'$count' -and !$SkipCache -and !$NoPagination) {
                        $Count = New-GraphGetRequest @GraphRequest -CountOnly -ErrorAction Stop
                        if ($CountOnly.IsPresent) { return $Count }
                        Write-Host "Total results (`$count): $Count"
                        if ($Count -gt 8000) {
                            $QueueThresholdExceeded = $true
                            if ($RunningQueue) {
                                Write-Host 'Queue currently running'
                                Write-Host ($RunningQueue | ConvertTo-Json)
                                [PSCustomObject]@{
                                    QueueMessage = 'Data still processing, please wait'
                                    QueueId      = $RunningQueue.RowKey
                                    Queued       = $true
                                }
                            } else {
                                $Queue = New-CippQueueEntry -Name $QueueName -Link $CippLink -Reference $QueueReference -TotalTasks 1
                                $QueueTenant = [PSCustomObject]@{
                                    FunctionName                = 'ListGraphRequestQueue'
                                    TenantFilter                = $TenantFilter
                                    Endpoint                    = $Endpoint
                                    QueueId                     = $Queue.RowKey
                                    QueueName                   = $TenantFilter
                                    QueueType                   = 'SingleTenant'
                                    Parameters                  = $Parameters
                                    PartitionKey                = $PartitionKey
                                    NoAuthCheck                 = $NoAuthCheck.IsPresent
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                }

                                $InputObject = @{
                                    OrchestratorName = 'GraphRequestOrchestrator'
                                    Batch            = @($QueueTenant)
                                }
                                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

                                #Push-OutputBinding -Name QueueItem -Value $QueueTenant

                                [PSCustomObject]@{
                                    QueueMessage = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $TenantFilter)
                                    QueueId      = $Queue.RowKey
                                    Queued       = $true
                                }
                            }
                        }
                    }

                    if (!$QueueThresholdExceeded) {
                        $GraphRequestResults = New-GraphGetRequest @GraphRequest -ErrorAction Stop | Select-Object *, @{l = 'Tenant'; e = { $TenantFilter } }, @{l = 'CippStatus'; e = { 'Good' } }
                        if ($ReverseTenantLookup -and $GraphRequestResults) {
                            $TenantInfo = $GraphRequestResults.$ReverseTenantLookupProperty | Sort-Object -Unique | ForEach-Object {
                                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$_')" -noauthcheck $true -asApp:$true -tenant $env:TenantId
                            }
                            foreach ($Result in $GraphRequestResults) {
                                $Result | Select-Object @{n = 'TenantInfo'; e = { $TenantInfo | Where-Object { $Result.$ReverseTenantLookupProperty -eq $_.tenantId } } }, *
                            }
                        } else {
                            $GraphRequestResults
                        }
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