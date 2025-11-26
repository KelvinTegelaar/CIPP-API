function Invoke-ListStandardsCompare {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.BestPracticeAnalyser.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $Table = Get-CIPPTable -TableName 'CippStandardsReports'
    $TenantFilter = $Request.Query.tenantFilter
    $TemplateFilter = $Request.Query.templateId

    $Filters = [system.collections.generic.list[string]]::new()
    if ($TenantFilter) {
        $Filters.Add("PartitionKey eq '{0}'" -f $TenantFilter)
    }
    if ($TemplateFilter) {
        $Filters.Add("TemplateId eq '{0}'" -f $TemplateFilter)
    }
    $Filter = $Filters -join ' and '

    $Tenants = Get-Tenants -IncludeErrors
    $Standards = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.PartitionKey -in $Tenants.defaultDomainName }

    $TenantStandards = @{}
    $Results = [System.Collections.Generic.List[object]]::new()

    foreach ($Standard in $Standards) {
        # each standard is on their own row now, the field name is the RowKey and the value is in the Value field
        $FieldName = $Standard.RowKey
        $FieldValue = $Standard.Value
        $Tenant = $Standard.PartitionKey

        # decode field names that are hex encoded (e.g. QuarantineTemplates)
        if ($FieldName -match '^(standards\.QuarantineTemplate\.)(.+)$') {
            $Prefix = $Matches[1]
            $HexEncodedName = $Matches[2]
            $Chars = [System.Collections.Generic.List[char]]::new()
            for ($i = 0; $i -lt $HexEncodedName.Length; $i += 2) {
                $Chars.Add([char][Convert]::ToInt32($HexEncodedName.Substring($i, 2), 16))
            }
            $FieldName = "$Prefix$(-join $Chars)"
        }

        if ($FieldValue -is [System.Boolean]) {
            $FieldValue = [bool]$FieldValue
        } elseif (Test-Json -Json $FieldValue -ErrorAction SilentlyContinue) {
            $FieldValue = ConvertFrom-Json -InputObject $FieldValue -ErrorAction SilentlyContinue
        } else {
            $FieldValue = [string]$FieldValue
        }

        if (-not $TenantStandards.ContainsKey($Tenant)) {
            $TenantStandards[$Tenant] = @{}
        }
        $TenantStandards[$Tenant][$FieldName] = @{
            Value       = $FieldValue
            LastRefresh = $Standard.TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            TemplateId  = $Standard.TemplateId
        }
    }

    foreach ($Tenant in $TenantStandards.Keys) {
        $TenantStandard = [PSCustomObject]@{
            tenantFilter = $Tenant
        }
        foreach ($Field in $TenantStandards[$Tenant].Keys) {
            $Value = $TenantStandards[$Tenant][$Field]
            $TenantStandard | Add-Member -MemberType NoteProperty -Name $Field -Value $Value -Force
        }
        $Results.Add($TenantStandard)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })

}
