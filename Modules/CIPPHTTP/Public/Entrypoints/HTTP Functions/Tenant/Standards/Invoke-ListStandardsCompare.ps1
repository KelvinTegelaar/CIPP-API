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

    # Get-CIPPStandards is the authoritative source for what is currently in scope.
    $StandardParams = @{}
    if ($TemplateFilter) { $StandardParams.TemplateId = $TemplateFilter }
    if ($TenantFilter) { $StandardParams.TenantFilter = $TenantFilter }
    $StandardList = Get-CIPPStandards @StandardParams

    $ScopedTemplateGuids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ScopedQuarantineNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in $StandardList) {
        switch ($Entry.Standard) {
            { $_ -in @('IntuneTemplate', 'ConditionalAccessTemplate') } {
                if ($Entry.Settings.TemplateList.value) { $null = $ScopedTemplateGuids.Add($Entry.Settings.TemplateList.value) }
            }
            'QuarantineTemplate' {
                $DisplayName = $Entry.Settings.displayName.value ?? $Entry.Settings.displayName
                if ($DisplayName) { $null = $ScopedQuarantineNames.Add($DisplayName) }
            }
        }
    }

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

        # Skip rows for template types no longer in scope per the current standard list.
        if ($FieldName -match '^standards\.(IntuneTemplate|ConditionalAccessTemplate)\.(.+)$') {
            if (-not $ScopedTemplateGuids.Contains($Matches[2])) { continue }
        } elseif ($ScopedQuarantineNames.Count -gt 0 -and $FieldName -match '^standards\.QuarantineTemplate\.(.+)$') {
            # Decode hex-encoded display name and check if it's still in scope
            $HexEncoded = $Matches[1]
            $Chars = [System.Collections.Generic.List[char]]::new()
            for ($i = 0; $i -lt $HexEncoded.Length; $i += 2) {
                $Chars.Add([char][Convert]::ToInt32($HexEncoded.Substring($i, 2), 16))
            }
            $DecodedName = -join $Chars
            if (-not $ScopedQuarantineNames.Contains($DecodedName)) { continue }
        }

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

        # Parse CurrentValue and ExpectedValue from JSON if they are JSON strings
        $ParsedCurrentValue = if ($Standard.CurrentValue -and (Test-Json -Json $Standard.CurrentValue -ErrorAction SilentlyContinue)) {
            ConvertFrom-Json -InputObject $Standard.CurrentValue -ErrorAction SilentlyContinue
        } else {
            $Standard.CurrentValue
        }

        $ParsedExpectedValue = if ($Standard.ExpectedValue -and (Test-Json -Json $Standard.ExpectedValue -ErrorAction SilentlyContinue)) {
            ConvertFrom-Json -InputObject $Standard.ExpectedValue -ErrorAction SilentlyContinue
        } else {
            $Standard.ExpectedValue
        }

        if (-not $TenantStandards.ContainsKey($Tenant)) {
            $TenantStandards[$Tenant] = @{}
        }
        $TenantStandards[$Tenant][$FieldName] = @{
            Value            = $FieldValue
            LastRefresh      = $Standard.TimeStamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            TemplateId       = $Standard.TemplateId
            LicenseAvailable = $Standard.LicenseAvailable
            CurrentValue     = $ParsedCurrentValue
            ExpectedValue    = $ParsedExpectedValue
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
