function Get-ApplicationInsightsQuery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    if (-not $env:APPLICATIONINSIGHTS_CONNECTION_STRING -and -not $env:APPINSIGHTS_INSTRUMENTATIONKEY) {
        throw 'Application Insights is not enabled for this instance.'
    }

    $SubscriptionId = Get-CIPPAzFunctionAppSubId
    if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
        $RGName = $Matches.RGName
    } else {
        $RGName = $env:WEBSITE_RESOURCE_GROUP
    }
    $AppInsightsName = $env:WEBSITE_SITE_NAME

    $Body = @{
        'query'            = $Query
        'options'          = @{'truncationMaxSize' = 67108864 }
        'maxRows'          = 1001
        'workspaceFilters' = @{'regions' = @() }
    } | ConvertTo-Json -Depth 10 -Compress

    $AppInsightsQuery = 'subscriptions/{0}/resourceGroups/{1}/providers/microsoft.insights/components/{2}/query' -f $SubscriptionId, $RGName, $AppInsightsName

    $resource = 'https://api.loganalytics.io'
    $Token = Get-CIPPAzIdentityToken -ResourceUrl $resource

    $headerParams = @{'Authorization' = "Bearer $Token" }
    $logAnalyticsBaseURI = 'https://api.loganalytics.io/v1'

    $result = Invoke-RestMethod -Method POST -Uri "$($logAnalyticsBaseURI)/$AppInsightsQuery" -Headers $headerParams -Body $Body -ContentType 'application/json' -ErrorAction Stop

    # Format Result to PSObject
    $headerRow = $null
    $headerRow = $result.tables.columns | Select-Object name
    $columnsCount = $headerRow.Count
    $logData = foreach ($row in $result.tables.rows) {
        $data = New-Object PSObject
        for ($i = 0; $i -lt $columnsCount; $i++) {
            $data | Add-Member -MemberType NoteProperty -Name $headerRow[$i].name -Value $row[$i]
        }
        $data
    }

    return $logData
}
