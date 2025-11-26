function Set-CIPPStandardsCompareField {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $FieldName,
        $FieldValue,
        $TenantFilter
    )
    $Table = Get-CippTable -tablename 'CippStandardsReports'
    $TenantName = Get-Tenants -TenantFilter $TenantFilter

    if ($FieldValue -is [System.Boolean]) {
        $FieldValue = [bool]$FieldValue
    } elseif ($FieldValue -is [string]) {
        $FieldValue = [string]$FieldValue
    } else {
        $FieldValue = ConvertTo-Json -Compress -InputObject @($FieldValue) -Depth 10 | Out-String
        $FieldValue = [string]$FieldValue
    }

    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($TenantName.defaultDomainName)' and RowKey eq '$($FieldName)'"

    if ($PSCmdlet.ShouldProcess('CIPP Standards Compare', "Set field '$FieldName' to '$FieldValue' for tenant '$($TenantName.defaultDomainName)'")) {
        try {
            if ($Existing) {
                $Existing.Value = $FieldValue
                $Existing | Add-Member -NotePropertyName TemplateId -NotePropertyValue $script:StandardInfo.StandardTemplateId -Force
                Add-CIPPAzDataTableEntity @Table -Entity $Existing -Force
            } else {
                $Result = [PSCustomObject]@{
                    PartitionKey = [string]$TenantName.defaultDomainName
                    RowKey       = [string]$FieldName
                    Value        = $FieldValue
                    TemplateId   = $script:StandardInfo.StandardTemplateId
                }
                Add-CIPPAzDataTableEntity @Table -Entity $Result -Force
            }
            Write-Information "Adding $FieldName to StandardCompare for $Tenant. content is $FieldValue"
        } catch {
            Write-Warning "Failed to add $FieldName to StandardCompare for $Tenant. content is $FieldValue - $($_.Exception.Message)"
        }
    }
}
