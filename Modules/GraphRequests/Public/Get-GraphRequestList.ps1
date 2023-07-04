function Get-GraphRequestList {
    [CmdletBinding()]
    Param(
        $Tenant = $env:TenantId,
        [Parameter(Mandatory = $true)]
        $Endpoint,
        $Parameters = @(),
        $QueueId,
        $CippLink,
        [ValidateSet('v1.0', 'beta')]
        $Version = 'beta',
        $QueueNameOverride,
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

    if ($QueueId) {
        $Table = Get-CIPPTable -TableName $TableName
        $Filter = "QueueId eq '{0}'" -f $QueueId
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter
        $Type = 'Queue'
    } elseif ($Tenant -eq 'AllTenants' -or (!$SkipCache.IsPresent -and !$ClearCache.IsPresent -and !$CountOnly.IsPresent)) {
        $Table = Get-CIPPTable -TableName $TableName
        if ($Tenant -eq 'AllTenants') {
            $Filter = "PartitionKey eq '{0}' and QueueType eq 'AllTenants'" -f $PartitionKey
        } else {
            $Filter = "PartitionKey eq '{0}' and Tenant eq '{1}'" -f $PartitionKey, $Tenant
        }
        #Write-Host $Filter
        $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Timestamp.DateTime -gt (Get-Date).ToUniversalTime().AddHours(-1) }
        $Type = 'Cache'
    } else {
        $Type = 'None'
        $Rows = @()
    }
    Write-Host "Cached: $(($Rows | Measure-Object).Count) rows (Type: $($Type))"

    $QueueReference = '{0}-{1}' -f $Tenant, $PartitionKey
    $RunningQueue = Get-CippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' }

    if (!$Rows) {
        switch ($Tenant) {
            'AllTenants' {
                if ($SkipCache) {
                    Get-Tenants -IncludeErrors | ForEach-Object -Parallel {
                        Import-Module .\GraphHelper.psm1
                        $GraphRequestParams = @{
                            Tenant                      = $_.defaultDomainName
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
                            Tenant  = 'Data still processing, please wait'
                            QueueId = $RunningQueue.RowKey
                        }
                    } else {
                        $Queue = New-CippQueueEntry -Name "$QueueName (All Tenants)" -Link $CippLink -Reference $QueueReference
                        [PSCustomObject]@{
                            QueueMessage = 'Loading data for all tenants. Please check back after the job completes'
                            Queued       = $true
                            QueueId      = $Queue.RowKey
                        }
                        Write-Host 'Pushing output bindings'
                        try {
                            Get-Tenants -IncludeErrors | ForEach-Object {
                                $Tenant = $_.defaultDomainName
                                $QueueTenant = @{
                                    Tenant                      = $Tenant
                                    Endpoint                    = $Endpoint
                                    QueueId                     = $Queue.RowKey
                                    QueueName                   = $QueueName
                                    QueueType                   = 'AllTenants'
                                    Parameters                  = $Parameters
                                    PartitionKey                = $PartitionKey
                                    NoPagination                = $NoPagination.IsPresent
                                    NoAuthCheck                 = $NoAuthCheck.IsPresent
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                } | ConvertTo-Json -Depth 5 -Compress

                                Push-OutputBinding -Name QueueItem -Value $QueueTenant
                            }
                        } catch {
                            Write-Host "QUEUE ERROR: $($_.Exception.Message)"
                        }
                    }
                }
            }
            default {
                $GraphRequest = @{
                    uri           = $GraphQuery.ToString()
                    tenantid      = $Tenant
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
                                $Queue = New-CippQueueEntry -Name $QueueName -Link $CippLink -Reference $QueueReference
                                $QueueTenant = @{
                                    Tenant                      = $Tenant
                                    Endpoint                    = $Endpoint
                                    QueueId                     = $Queue.RowKey
                                    QueueName                   = $QueueName
                                    QueueType                   = 'SingleTenant'
                                    Parameters                  = $Parameters
                                    PartitionKey                = $PartitionKey
                                    NoAuthCheck                 = $NoAuthCheck.IsPresent
                                    ReverseTenantLookupProperty = $ReverseTenantLookupProperty
                                    ReverseTenantLookup         = $ReverseTenantLookup.IsPresent
                                } | ConvertTo-Json -Depth 5 -Compress

                                Push-OutputBinding -Name QueueItem -Value $QueueTenant
                                [PSCustomObject]@{
                                    QueueMessage = ('Loading {0} rows for {1}. Please check back after the job completes' -f $Count, $Tenant)
                                    QueueId      = $Queue.RowKey
                                    Queued       = $true
                                }
                            }
                        }
                    }

                    if (!$QueueThresholdExceeded) {
                        $GraphRequestResults = New-GraphGetRequest @GraphRequest -ErrorAction Stop
                        if ($ReverseTenantLookup -and $GraphRequestResults) {
                            $TenantInfo = $GraphRequestResults.$ReverseTenantLookupProperty | Sort-Object -Unique | ForEach-Object {
                                New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$_')" -noauthcheck $true -asApp:$true
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