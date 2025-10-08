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
    if ($TenantFilter) {
        $Table.Filter = "PartitionKey eq '{0}'" -f $TenantFilter
    }

    $Tenants = Get-Tenants -IncludeErrors
    $Standards = Get-CIPPAzDataTableEntity @Table | Where-Object { $_.PartitionKey -in $Tenants.defaultDomainName }

    #in the results we have objects starting with "standards." All these have to be converted from JSON. Do not do this is its a boolean
    <#$Results | ForEach-Object {
        $Object = $_
        $Object.PSObject.Properties | ForEach-Object {
            if ($_.Name -like 'standards_*') {
                if ($_.Value -is [System.Boolean]) {
                    $_.Value = [bool]$_.Value
                } elseif ($_.Value -like '*{*') {
                    $_.Value = ConvertFrom-Json -InputObject $_.Value -ErrorAction SilentlyContinue
                } else {
                    $_.Value = [string]$_.Value
                }

                $Key = $_.Name.replace('standards_', 'standards.')
                $Key = $Key.replace('IntuneTemplate_', 'IntuneTemplate.')
                $Key = $Key -replace '__', '-'

                $object | Add-Member -MemberType NoteProperty -Name $Key -Value $_.Value -Force
                $object.PSObject.Properties.Remove($_.Name)
            }
        }
    }#>

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
