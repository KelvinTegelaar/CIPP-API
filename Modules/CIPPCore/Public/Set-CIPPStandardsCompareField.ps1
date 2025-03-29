function Set-CIPPStandardsCompareField {
    param (
        $FieldName,
        $FieldValue,
        $TenantFilter
    )
    $Table = Get-CippTable -tablename 'CippStandardsReports'
    $TenantName = Get-Tenants | Where-Object -Property defaultDomainName -EQ $Tenant
    #if the fieldname does not contain standards. prepend it.
    $FieldName = $FieldName.replace('standards.', 'standards_')
    if ($FieldValue -is [System.Boolean]) {
        $fieldValue = [bool]$FieldValue
    } elseif ($FieldValue -is [string]) {
        $FieldValue = [string]$FieldValue
    } else {
        $FieldValue = ConvertTo-Json -Compress -InputObject @($FieldValue) -Depth 10 | Out-String
        $FieldValue = [string]$FieldValue
    }

    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardReport' and RowKey eq '$($TenantName.defaultDomainName)'"
    if ($Existing) {
        $Existing = $Existing | Select-Object * -ExcludeProperty ETag, TimeStamp | ConvertTo-Json -Depth 10 -Compress | ConvertFrom-Json -AsHashtable
        $Existing[$FieldName] = $FieldValue
        $Existing['LastRefresh'] = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        $Existing = [PSCustomObject]$Existing

        Add-CIPPAzDataTableEntity @Table -Entity $Existing -Force
    } else {
        $Result = @{
            tenantFilter = "$($TenantName.defaultDomainName)"
            GUID         = "$($TenantName.customerId)"
            RowKey       = "$($TenantName.defaultDomainName)"
            PartitionKey = 'StandardReport'
            LastRefresh  = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        }
        $Result[$FieldName] = $FieldValue
        Add-CIPPAzDataTableEntity @Table -Entity $Result -Force

    }
    Write-Information "Adding $FieldName to StandardCompare for $Tenant. content is $FieldValue"
}
