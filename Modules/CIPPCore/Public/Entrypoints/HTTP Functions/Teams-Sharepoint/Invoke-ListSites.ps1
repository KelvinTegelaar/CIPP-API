function Invoke-ListSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    $TenantFilter = $Request.Query.TenantFilter
    $Type = $Request.Query.Type
    $UserUPN = $Request.Query.UserUPN

    if (!$TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
    }

    if (!$Type) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Type is required'
            })
    }

    if ($TenantFilter -eq 'AllTenants') {
        if ($Type -eq 'SharePointSiteUsage') {
            $CacheTableName = 'cacheSharePointSites'
            $PartitionKey = 'SharePointSite'
            $DurableName = 'ListSitesSharePointAllTenants'
            $QueueName = 'SharePoint Sites - All Tenants'
            $FrontendLink = '/teams-share/sharepoint?customerId=AllTenants'
            $OrchestratorLabel = 'SharePointSitesOrchestrator'
        } else {
            $CacheTableName = 'cacheOneDriveSites'
            $PartitionKey = 'OneDriveSite'
            $DurableName = 'ListSitesOneDriveAllTenants'
            $QueueName = 'OneDrive Sites - All Tenants'
            $FrontendLink = '/teams-share/onedrive?customerId=AllTenants'
            $OrchestratorLabel = 'OneDriveSitesOrchestrator'
        }

        $Table = Get-CIPPTable -TableName $CacheTableName
        $Filter = "PartitionKey eq '$PartitionKey'"
        $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
        $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
        if ($RunningQueue) {
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                QueueId      = $RunningQueue.RowKey
            }
        } elseif (!$Rows -and !$RunningQueue) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name $QueueName -Link $FrontendLink -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = $OrchestratorLabel
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = $DurableName
                }
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject | Out-Null
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            $GraphRequest = foreach ($policy in $Rows) {
                ($policy.Policy | ConvertFrom-Json)
            }
        }

        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest | Where-Object { $null -ne $_.webId })
            Metadata = $Metadata
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $Body
            })
    }

    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    $TenantId = $Tenant.customerId

    if ($Type -eq 'SharePointSiteUsage') {
        $Filter = 'isPersonalSite eq false'
    } else {
        $Filter = 'isPersonalSite eq true'
    }

    try {
        $BulkRequests = @(
            @{
                id     = 'listAllSites'
                method = 'GET'
                url    = "sites/getAllSites?`$filter=$($Filter)&`$select=id,createdDateTime,description,name,displayName,isPersonalSite,lastModifiedDateTime,webUrl,siteCollection,sharepointIds&`$top=999"
            }
            @{
                id     = 'usage'
                method = 'GET'
                url    = "reports/get$($type)Detail(period='D7')?`$format=application/json&`$top=999"
            }
        )

        $Result = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -asapp $true
        $Sites = ($Result | Where-Object { $_.id -eq 'listAllSites' }).body.value
        $UsageBase64 = ($Result | Where-Object { $_.id -eq 'usage' }).body
        $UsageJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UsageBase64))
        $Usage = ($UsageJson | ConvertFrom-Json).value

        $GraphRequest = foreach ($Site in $Sites) {
            $SiteUsage = $Usage | Where-Object { $_.siteId -eq $Site.sharepointIds.siteId }
            [PSCustomObject]@{
                siteId                      = $Site.sharepointIds.siteId
                webId                       = $Site.sharepointIds.webId
                createdDateTime             = $Site.createdDateTime
                displayName                 = $Site.displayName
                webUrl                      = $Site.webUrl
                ownerDisplayName            = $SiteUsage.ownerDisplayName
                ownerPrincipalName          = $SiteUsage.ownerPrincipalName
                lastActivityDate            = $SiteUsage.lastActivityDate
                fileCount                   = $SiteUsage.fileCount
                storageUsedInGigabytes      = [math]::round($SiteUsage.storageUsedInBytes / 1GB, 2)
                storageAllocatedInGigabytes = [math]::round($SiteUsage.storageAllocatedInBytes / 1GB, 2)
                storageUsedInBytes          = $SiteUsage.storageUsedInBytes
                storageAllocatedInBytes     = $SiteUsage.storageAllocatedInBytes
                rootWebTemplate             = $SiteUsage.rootWebTemplate
                reportRefreshDate           = $SiteUsage.reportRefreshDate
                AutoMapUrl                  = ''
            }
        }

        $int = 0
        if ($Type -eq 'SharePointSiteUsage') {
            $Requests = foreach ($Site in $GraphRequest) {
                @{
                    id     = $int++
                    method = 'GET'
                    url    = "sites/$($Site.siteId)/lists?`$select=id,name,list,parentReference"
                }
            }
            try {
                $Requests = (New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body.value | Where-Object { $_.list.template -eq 'DocumentLibrary' }
            } catch {
                Write-LogMessage -Headers $Headers -Message "Error getting auto map urls: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -API 'ListSites' -LogData (Get-CippException -Exception $_)
            }
            $GraphRequest = foreach ($Site in $GraphRequest) {
                $ListId = ($Requests | Where-Object { $_.parentReference.siteId -like "*$($Site.siteId)*" }).id
                $site.AutoMapUrl = "tenantId=$($TenantId)&webId={$($Site.webId)}&siteid={$($Site.siteId)}&webUrl=$($Site.webUrl)&listId={$($ListId)}"
                $site
            }
        }
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    if ($Request.query.URLOnly -eq 'true') {
        $GraphRequest = $GraphRequest | Where-Object { $null -ne $_.webUrl }
    }

    $Body = [PSCustomObject]@{
        Results  = @($GraphRequest | Where-Object { $null -ne $_.webId } | Sort-Object -Property displayName)
        Metadata = $Metadata
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
