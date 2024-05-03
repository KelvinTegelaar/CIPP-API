function Add-CIPPBPAField {
    param (
        $BPAName = 'CIPP Standards v1.0 - Table view',
        $FieldName,
        $FieldValue,
        $StoreAs,
        $Tenant
    )
    $Table = Get-CippTable -tablename 'cachebpav2'
    $TenantName = Get-Tenants | Where-Object -Property defaultDomainName -EQ $Tenant
    $CurrentContentsObject = (Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$BPAName' and PartitionKey eq '$($TenantName.customerId)'")
    Write-Information "Adding $FieldName to $BPAName for $Tenant. content is $FieldValue"
    if ($CurrentContentsObject.RowKey) {
        $CurrentContents = @{}
        $CurrentContentsObject.PSObject.Properties.Name | ForEach-Object {
            $CurrentContents[$_] = $CurrentContentsObject.$_
        }
        $Result = $CurrentContents
    } else {
        $Result = @{
            Tenant       = "$($TenantName.displayName)"
            GUID         = "$($TenantName.customerId)"
            RowKey       = $BPAName
            PartitionKey = "$($TenantName.customerId)"
            LastRefresh  = [string]$(Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        }
    }
    switch -Wildcard ($StoreAs) {
        '*bool' {
            $Result["$fieldName"] = [bool]$FieldValue
        }
        'JSON' {
            if ($FieldValue -eq $null) { $JsonString = '{}' } else { $JsonString = (ConvertTo-Json -Depth 15 -InputObject $FieldValue -Compress) }
            $Result[$fieldName] = [string]$JsonString
        }
        'string' {
            $Result[$fieldName], [string]$FieldValue
        }
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Result -Force
}