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

    .PARAMETER ManualPagination
    Enable manual pagination using nextLink

    .PARAMETER CountOnly
    Only return count of results

    .PARAMETER NoAuthCheck
    Skip auth check

    .PARAMETER ReverseTenantLookup
    Perform reverse tenant lookup

    .PARAMETER ReverseTenantLookupProperty
    Property to perform reverse tenant lookup

    .PARAMETER AsApp
    Run the request as an application

    .PARAMETER Caller
    Name of the calling function

    .PARAMETER UseBatchExpand
    Perform a batch lookup using the $expand query parameter to avoid 20 item max

    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter = $env:TenantID,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [string]$nextLink,
        [hashtable]$Parameters = @{},
        [string]$QueueId,
        [string]$CippLink,
        [ValidateSet('v1.0', 'beta')]
        [string]$Version = 'beta',
        [string]$QueueNameOverride,
        [switch]$SkipCache,
        [switch]$ClearCache,
        [switch]$NoPagination,
        [switch]$ManualPagination,
        [switch]$CountOnly,
        [switch]$NoAuthCheck,
        [switch]$ReverseTenantLookup,
        [string]$ReverseTenantLookupProperty = 'tenantId',
        [boolean]$AsApp = $false,
        [string]$Caller = 'Get-GraphRequestList',
        [switch]$UseBatchExpand
    )

    $SingleTenantThreshold = 8000
    Write-Information "Tenant: $TenantFilter"
    $TableName = ('cache{0}' -f ($Endpoint -replace '[^A-Za-z0-9]'))[0..62] -join ''
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
        if ($Item.Value -is [System.Boolean]) {
            $Item.Value = $Item.Value.ToString().ToLower()
        }
        if ($Item.Value) {
            if ($Item.Key -eq '$select' -or $Item.Key -eq 'select') {
                $Columns = $Item.Value -split ','
                $ActualCols = foreach ($Col in $Columns) {
                    $Col -split '\.' | Select-Object -First 1
                }
                $Value = ($ActualCols | Sort-Object -Unique) -join ','
            } else {
                $Value = $Item.Value
            }

            if ($UseBatchExpand.IsPresent -and ($Item.Key -eq '$expand' -or $Item.Key -eq 'expand')) {
                $BatchExpandQuery = $Item.Value
            } else {
                $ParamCollection.Add($Item.Key, $Value)
            }
        }
    }
    $GraphQuery.Query = $ParamCollection.ToString()
    $PartitionKey = Get-StringHash -String (@($Endpoint, $ParamCollection.ToString(), 'v2') -join '-')

    # Perform $count check before caching
    $Count = 0
    if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = @{
            uri           = $GraphQuery.ToString()
            tenantid      = $TenantFilter
            ComplexFilter = $true
        }
        if ($NoPagination.IsPresent -or $ManualPagination.IsPresent) {
            $GraphRequest.noPagination = $true
        }
        if ($CountOnly.IsPresent) {
            $GraphRequest.CountOnly = $CountOnly.IsPresent
        }
        if ($NoAuthCheck.IsPresent) {
            $GraphRequest.noauthcheck = $NoAuthCheck.IsPresent
        }
        if ($AsApp) {
            $GraphRequest.asApp = $AsApp
        }

        if ($Endpoint -match '%' -or $Parameters.Values -match '%') {
            $TenantId = (Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }).customerId
            $Endpoint = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Endpoint
            $GraphQuery = [System.UriBuilder]('https://graph.microsoft.com/{0}/{1}' -f $Version, $Endpoint)
            $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
            foreach ($Item in ($Parameters.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
                if ($Item.Key -eq '$select' -or $Item.Key -eq 'select') {
                    $Columns = $Item.Value -split ','
                    $ActualCols = foreach ($Col in $Columns) {
                        $Col -split '\.' | Select-Object -First 1
                    }
                    $Value = ($ActualCols | Sort-Object -Unique) -join ','
                } else {
                    $Value = $Item.Value
                }
                $Value = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Value
                $ParamCollection.Add($Item.Key, $Value)
            }
            $GraphQuery.Query = $ParamCollection.ToString()
            $GraphRequest.uri = $GraphQuery.ToString()
        }

        if ($Parameters.'$count' -and !$SkipCache.IsPresent -and !$NoPagination.IsPresent) {
            $Count = New-GraphGetRequest @GraphRequest -CountOnly -ErrorAction Stop
            if ($CountOnly.IsPresent) { return $Count }
            Write-Information "Total results (`$count): $Count"
        }
    }
    #Write-Information ( 'GET [ {0} ]' -f $GraphQuery.ToString())

    try {
        if ($QueueId) {
            $Table = Get-CIPPTable -TableName $TableName
            $Filter = "QueueId eq '{0}'" -f $QueueId
            $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            $Type = 'Queue'
            Write-Information "Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' }
        } elseif (!$SkipCache.IsPresent -and !$ClearCache.IsPresent -and !$CountOnly.IsPresent) {
            if ($TenantFilter -eq 'AllTenants' -or $Count -gt $SingleTenantThreshold) {
                $Table = Get-CIPPTable -TableName $TableName
                $Timestamp = (Get-Date).AddHours(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffK')
                if ($TenantFilter -eq 'AllTenants') {
                    $Filter = "PartitionKey eq '{0}' and Timestamp ge datetime'{1}'" -f $PartitionKey, $Timestamp
                } else {
                    $Filter = "PartitionKey eq '{0}' and (RowKey eq '{1}' or OriginalEntityId eq '{1}') and Timestamp ge datetime'{2}'" -f $PartitionKey, $TenantFilter, $Timestamp
                }
                $Tenants = Get-Tenants -IncludeErrors
                $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.OriginalEntityId -in $Tenants.defaultDomainName -or $_.RowKey -in $Tenants.defaultDomainName }
                $Type = 'Cache'
                Write-Information "Table: $TableName | PK: $PartitionKey | Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"
                $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
                $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            }
        }
    } catch {
        Write-Information $_.InvocationInfo.PositionMessage
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
                            NoPagination                = $false
                            ReverseTenantLookupProperty = $using:ReverseTenantLookupProperty
                            ReverseTenantLookup         = $using:ReverseTenantLookup.IsPresent
                            NoAuthCheck                 = $using:NoAuthCheck.IsPresent
                            AsApp                       = $using:AsApp
                            SkipCache                   = $true
                        }

                        try {
                            $DefaultDomainName = $_.defaultDomainName
                            Write-Host "Default domain name is $DefaultDomainName"
                            Get-GraphRequestList @GraphRequestParams | Select-Object *, @{l = 'Tenant'; e = { $_.defaultDomainName } }, @{l = 'CippStatus'; e = { 'Good' } }
                        } catch {
                            [PSCustomObject]@{
                                Tenant     = $DefaultDomainName
                                CippStatus = "Could not connect to tenant. $($_.Exception.message)"
                            }
                        }
                    }
                } else {
                    if ($RunningQueue) {
                        Write-Information 'Queue currently running'
                        Write-Information ($RunningQueue | ConvertTo-Json)
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
                        Write-Information 'Pushing output bindings'
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
                                    AsApp                       = $AsApp
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                }

                            }

                            $InputObject = @{
                                OrchestratorName = 'GraphRequestOrchestrator'
                                Batch            = @($Batch)
                            }
                            #Write-Information  ($InputObject | ConvertTo-Json -Depth 5)
                            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                        } catch {
                            Write-Information "QUEUE ERROR: $($_.Exception.Message)"
                        }
                    }
                }
            }
            default {
                try {
                    $QueueThresholdExceeded = $false

                    if ($Parameters.'$count' -and !$SkipCache -and !$NoPagination.IsPresent -and !$ManualPagination.IsPresent) {
                        if ($Count -gt $singleTenantThreshold) {
                            $QueueThresholdExceeded = $true
                            if ($RunningQueue) {
                                Write-Information 'Queue currently running'
                                Write-Information ($RunningQueue | ConvertTo-Json)
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

                                [PSCustomObject]@{
                                    QueueMessage = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $TenantFilter)
                                    QueueId      = $Queue.RowKey
                                    Queued       = $true
                                }
                            }
                        }
                    }

                    if (!$QueueThresholdExceeded) {
                        #nextLink should ONLY be used in direct calls with manual pagination. It should not be used in queueing
                        if ($ManualPagination.IsPresent -and $nextLink -match '^https://.+') { $GraphRequest.uri = $nextLink }

                        $GraphRequestResults = New-GraphGetRequest @GraphRequest -Caller $Caller -ErrorAction Stop
                        $GraphRequestResults = $GraphRequestResults | Select-Object *, @{n = 'Tenant'; e = { $TenantFilter } }, @{n = 'CippStatus'; e = { 'Good' } }

                        if ($UseBatchExpand.IsPresent -and ![string]::IsNullOrEmpty($BatchExpandQuery)) {
                            if ($BatchExpandQuery -match '' -and ![string]::IsNullOrEmpty($GraphRequestResults.id)) {
                                # Convert $expand format to actual batch query e.g. members($select=id,displayName) to members?$select=id,displayName
                                $BatchExpandQuery = $BatchExpandQuery -replace '\(\$?([^=]+)=([^)]+)\)', '?$$$1=$2' -replace ';', '&'

                                # Extract property name from expand
                                $Property = $BatchExpandQuery -replace '\?.*$', '' -replace '^.*\/', ''
                                Write-Information "Performing batch expansion for property '$Property'..."

                                if ($Property -eq 'assignedLicenses') {
                                    $LicenseDetails = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
                                    $GraphRequestResults = foreach ($GraphRequestResult in $GraphRequestResults) {
                                        $NewLicenses = [system.collections.generic.list[string]]::new()
                                        foreach ($License in $GraphRequestResult.assignedLicenses) {
                                            $LicenseInfo = $LicenseDetails | Where-Object { $_.skuId -eq $License.skuId } | Select-Object -First 1
                                            if ($LicenseInfo) {
                                                $NewLicenses.Add($LicenseInfo.License)
                                            }
                                        }
                                        $GraphRequestResult | Add-Member -MemberType NoteProperty -Name $Property -Value @($NewLicenses) -Force
                                        $GraphRequestResult
                                    }
                                } else {

                                    $Uri = "$Endpoint/{0}/$BatchExpandQuery"

                                    $Requests = foreach ($Result in $GraphRequestResults) {
                                        @{
                                            id     = $Result.id
                                            url    = $Uri -f $Result.id
                                            method = 'GET'
                                        }
                                    }
                                    $BatchResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -NoAuthCheck $NoAuthCheck.IsPresent -asapp $AsApp

                                    $GraphRequestResults = foreach ($Result in $GraphRequestResults) {
                                        $PropValue = $BatchResults | Where-Object { $_.id -eq $Result.id } | Select-Object -ExpandProperty body
                                        $Result | Add-Member -MemberType NoteProperty -Name $Property -Value ($PropValue.value ?? $PropValue)
                                        $Result
                                    }
                                }
                            }
                        }

                        if ($ReverseTenantLookup -and $GraphRequestResults) {
                            $ReverseLookupRequests = $GraphRequestResults.$ReverseTenantLookupProperty | Sort-Object -Unique | ForEach-Object {
                                @{
                                    id     = $_
                                    url    = "tenantRelationships/findTenantInformationByTenantId(tenantId='$_')"
                                    method = 'GET'
                                }
                            }
                            $TenantInfo = New-GraphBulkRequest -Requests @($ReverseLookupRequests) -tenantid $env:TenantID -NoAuthCheck $true -asapp $true

                            $GraphRequestResults | Select-Object @{n = 'TenantInfo'; e = { Get-GraphBulkResultByID -Results @($TenantInfo) -ID $_.$ReverseTenantLookupProperty } }, *

                        } else {
                            $GraphRequestResults
                        }
                    }

                } catch {
                    $Message = ('Exception at {0}:{1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
                    throw $Message
                }
            }
        }
    } else {
        foreach ($Row in $Rows) {
            if ($Row.Data) {
                try {
                    $Row.Data | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Warning "Could not convert data to JSON: $($_.Exception.Message)"
                    #Write-Information ($Row | ConvertTo-Json)
                    continue
                }
            }
        }
    }
}
