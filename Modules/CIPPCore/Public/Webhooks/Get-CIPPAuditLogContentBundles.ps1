function Get-CIPPAuditLogContentBundles {
    <#
    .SYNOPSIS
        Get the available audit log bundles
    .DESCRIPTION
        Query the Office 365 Activity Log API for available content bundles.
    .PARAMETER TenantFilter
        The tenant to filter on.
    .PARAMETER ContentType
        The type of content to get.
    .PARAMETER StartTime
        The start time to filter on.
    .PARAMETER EndTime
        The end time to filter on.
    .PARAMETER ShowAll
        Show all content, default is only show new content
    .EXAMPLE
        Get-CIPPAuditLogContentBundles -TenantFilter 'contoso.com' -ContentType 'Audit.AzureActiveDirectory'
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Audit.AzureActiveDirectory', 'Audit.Exchange')]
        [string]$ContentType,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$ShowAll
    )

    if ($TenantFilter -eq 'AllTenants') {
        throw 'AllTenants is not a valid tenant filter for webhooks'
    }

    if (!($TenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) {
        $DefaultDomainName = $TenantFilter
        $TenantFilter = (Get-Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter }).customerId
    } else {
        $DefaultDomainName = (Get-Tenants | Where-Object { $_.customerId -eq $TenantFilter }).defaultDomainName
    }

    $WebhookTable = Get-CippTable -tablename 'webhookTable'
    $WebhookConfig = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$DefaultDomainName' and Version eq '3' and Resource eq '$ContentType'"

    if (!$WebhookConfig) {
        throw "No webhook config found for $DefaultDomainName - $ContentType"
    }

    $Parameters = @{
        'contentType'         = $ContentType
        'PublisherIdentifier' = $env:TenantId
    }

    if (!$ShowAll.IsPresent) {
        if (!$StartTime) {
            $StartTime = (Get-Date).AddMinutes(-30)
            $EndTime = Get-Date
        }
    }

    if ($StartTime) {
        $Parameters.Add('startTime', $StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        if ($EndTime) {
            $Parameters.Add('endTime', $EndTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        } else {
            $Parameters.Add('endTime', ($StartTime).AddHours(24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        }
    }

    Write-Information "StartTime: $StartTime"
    Write-Information "EndTime: $EndTime"
    $GraphQuery = [System.UriBuilder]('https://manage.office.com/api/v1.0/{0}/activity/feed/subscriptions/content' -f $TenantFilter)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator())) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }
    $GraphQuery.Query = $ParamCollection.ToString()

    Write-Verbose "GET [ $($GraphQuery.ToString()) ]"
    $LogBundles = New-GraphGetRequest -uri $GraphQuery.ToString() -tenantid $TenantFilter -scope 'https://manage.office.com/.default' -IncludeResponseHeaders
    $AuditLogContents = $LogBundles | Select-Object contentId, contentUri, contentCreated, contentExpiration, contentType, @{Name = 'TenantFilter'; Expression = { $TenantFilter } }, @{ Name = 'DefaultDomainName'; Expression = { $DefaultDomainName } }

    return $AuditLogContents
}