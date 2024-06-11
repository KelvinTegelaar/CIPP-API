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

    $WebhookTable = Get-CippTable -TableName 'webhookTable'
    $WebhookConfig = Get-CIPPAzDataTableEntity @WebhookTable -Filter "PartitionKey eq '$DefaultDomainName' and Version eq '3' and Resource eq '$ContentType'"
    if (!$WebhookConfig) {
        throw "No webhook config found for $DefaultDomainName - $ContentType"
    }

    $Parameters = @{
        'contentType'         = $ContentType
        'PublisherIdentifier' = $env:TenantId
    }

    if (!$ShowAll.IsPresent) {
        if ($WebhookConfig.LastContentCreated) {
            $StartTime = $WebhookConfig.LastContentCreated.DateTime.ToLocalTime()
            $EndTime = Get-Date
        }
    }

    if ($StartTime) {
        $Parameters.Add('startTime', $StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        if ($EndTime) {
            $Parameters.Add('endTime', $EndTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        } else {
            $Parameters.Add('endTime', (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss'))
        }
    }

    $GraphQuery = [System.UriBuilder]('https://manage.office.com/api/v1.0/{0}/activity/feed/subscriptions/content' -f $TenantFilter)
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    foreach ($Item in ($Parameters.GetEnumerator())) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }
    $GraphQuery.Query = $ParamCollection.ToString()

    Write-Verbose "GET [ $($GraphQuery.ToString()) ]"
    $LogBundles = New-GraphGetRequest -uri $GraphQuery.ToString() -tenantid $TenantFilter -scope 'https://manage.office.com/.default' -IncludeResponseHeaders
    $AuditLogContents = $LogBundles | Select-Object contentUri, contentCreated, @{Name = 'TenantFilter'; Expression = { $TenantFilter } }

    if (!$ShowAll.IsPresent) {
        $LastContent = ($AuditLogContents | Sort-Object contentCreated -Descending | Select-Object -First 1 -ExpandProperty contentCreated) | Get-Date
        if ($WebhookConfig.LastContentCreated) {
            $AuditLogContents = $AuditLogContents | Where-Object { ($_.contentCreated | Get-Date).ToLocalTime() -gt $StartTime }
        }
        if ($LastContent) {
            if ($WebhookConfig.PSObject.Properties.Name -contains 'LastContentCreated') {
                $WebhookConfig.LastContentCreated = [datetime]$LastContent
            } else {
                $WebhookConfig | Add-Member -MemberType NoteProperty -Name LastContentCreated -Value ''
                $WebhookConfig.LastContentCreated = [datetime]$LastContent
            }
            $null = Add-CIPPAzDataTableEntity @WebhookTable -Entity $WebhookConfig -Force
        }
    }
    return $AuditLogContents
}