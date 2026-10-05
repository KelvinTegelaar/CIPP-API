BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Reports/Invoke-ExecLicensePricing.ps1'

    if (-not ('HttpStatusCode' -as [type])) {
        [void]([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
            $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPLicensePrice { param($SkuId, $Currency, [switch]$ListCurrencies, [switch]$IncludeUnknown, [switch]$FailOnError) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    $script:E5 = '06ebc4ee-1bb5-47dd-8120-11324bc54e06'
    $script:E3 = '6fd2c87f-b296-42f0-b197-1e91e994b900'
    $script:UnknownSku = '00000000-0000-0000-0000-000000000003'

    function New-ImportRow {
        param($SkuId, $Price, $Currency = 'GBP', $Name = 'Edited name', $PartNumber = 'EDITED_PART')
        [pscustomobject]@{
            Product_Display_Name = $Name
            skuPartNumber        = $PartNumber
            skuId                = $SkuId
            MonthlyPrice         = $Price
            Currency             = $Currency
        }
    }

    function New-Request {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecLicensePricing' }
            Headers = @{}
            Body    = $Body
        }
    }
}

Describe 'Invoke-ExecLicensePricing bulk import' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removals = [System.Collections.Generic.List[object]]::new()
        $script:FailSku = $null
        $script:ResolvedPrices = @{
            GBP = @(
                [pscustomobject]@{ skuId = $script:E5; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5'; MonthlyPrice = 38.0; Currency = 'GBP'; Source = 'Estimate' }
                [pscustomobject]@{ skuId = $script:E3; skuPartNumber = 'ENTERPRISEPACK'; Product_Display_Name = 'Office 365 E3'; MonthlyPrice = 23.0; Currency = 'GBP'; Source = 'Override' }
                [pscustomobject]@{ skuId = $script:UnknownSku; skuPartNumber = 'UNKNOWN_SKU'; Product_Display_Name = 'Unknown SKU'; MonthlyPrice = $null; Currency = 'GBP'; Source = 'Unknown' }
            )
        }

        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @([pscustomobject]@{ PartitionKey = 'Price'; RowKey = 'existing' }) }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            if ($Entity.skuId -eq $script:FailSku) { throw 'Table write failed' }
            $script:Writes.Add($Entity)
        }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { $script:Removals.Add($Entity) }
        Mock -CommandName Get-CIPPLicensePrice -MockWith {
            if ($ListCurrencies) { return @('GBP', 'USD') }
            return $script:ResolvedPrices[$Currency]
        }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'returns only changed rows using the catalog metadata and does not write during validation' {
        $Rows = @(
            (New-ImportRow -SkuId $script:E5 -Price 40.25),
            (New-ImportRow -SkuId $script:E3 -Price 23.0),
            (New-ImportRow -SkuId $script:UnknownSku -Price $null)
        )
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Valid | Should -BeTrue
        $Response.Body.Updated | Should -Be 1
        $Response.Body.Unchanged | Should -Be 2
        $Response.Body.Failed | Should -Be 0
        $Response.Body.Changes.Count | Should -Be 1
        $Response.Body.Changes[0].skuId | Should -Be $script:E5
        $Response.Body.Changes[0].Product_Display_Name | Should -Be 'Office 365 E5'
        $Response.Body.Changes[0].skuPartNumber | Should -Be 'ENTERPRISEPREMIUM'
        $Response.Body.Changes[0].CurrentPrice | Should -Be 38.0
        $script:Writes.Count | Should -Be 0
    }

    It 'matches a shipped resolved SKU with trailing nonbreaking whitespace' {
        $script:ResolvedPrices.GBP[0].skuId = "$($script:E5)$([char]0xA0)"
        $Rows = @((New-ImportRow -SkuId $script:E5 -Price 40.25))
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Valid | Should -BeTrue
        $Response.Body.Changes[0].skuId | Should -Be $script:E5
        $script:Writes.Count | Should -Be 0
    }

    It 'rejects resolved SKU IDs that collide after GUID normalization' {
        $DirtyE5 = "$($script:E5)$([char]0xA0)"
        $Collision = [pscustomobject]@{ skuId = $DirtyE5; skuPartNumber = 'DUPLICATE'; Product_Display_Name = 'Duplicate SKU'; MonthlyPrice = 99.0; Currency = 'GBP'; Source = 'Estimate' }
        $script:ResolvedPrices['GBP'] = @($script:ResolvedPrices['GBP']) + @($Collision)
        $Rows = @((New-ImportRow -SkuId $script:E5 -Price 40.25))
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Errors.Error -join ' ' | Should -Match 'ambiguous in the known license list'
        $script:Writes.Count | Should -Be 0
    }

    It 'rejects invalid and duplicate rows before writing any price' {
        $Rows = @(
            (New-ImportRow -SkuId 'not-a-guid' -Price 10),
            (New-ImportRow -SkuId $script:E5 -Price -1 -Currency 'GBP'),
            (New-ImportRow -SkuId $script:E5 -Price 'bad' -Currency 'GBP'),
            (New-ImportRow -SkuId $script:E3 -Price 10 -Currency 'USD'),
            (New-ImportRow -SkuId '00000000-0000-0000-0000-000000000001' -Price 10)
        )
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Valid | Should -BeFalse
        $Response.Body.Updated | Should -Be 0
        $Response.Body.Failed | Should -Be 5
        $Response.Body.Errors.Error -join ' ' | Should -Match 'valid GUID'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'cannot be negative'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'must be a number'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'match the selected currency'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'Duplicate SKU and currency row'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'not in the known license list'
        $script:Writes.Count | Should -Be 0
    }

    It 'rejects blank prices for priced SKUs and requires the price column' {
        $Row = New-ImportRow -SkuId $script:E5 -Price $null
        $Row.PSObject.Properties.Remove('MonthlyPrice')
        $BlankRow = New-ImportRow -SkuId $script:E3 -Price '  '
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = @($Row, $BlankRow) })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Errors.Error -join ' ' | Should -Match 'MonthlyPrice is required'
        $Response.Body.Errors.Error -join ' ' | Should -Match 'required for a priced license'
        $Response.Body.Failed | Should -Be 2
        $script:Writes.Count | Should -Be 0
    }

    It 'treats a zero price for an unpriced SKU as a change' {
        $Rows = @((New-ImportRow -SkuId $script:UnknownSku -Price 0))
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Valid | Should -BeTrue
        $Response.Body.Updated | Should -Be 1
        $Response.Body.Unchanged | Should -Be 0
        $Response.Body.Changes[0].MonthlyPrice | Should -Be 0
    }

    It 'rejects unsupported currency without writing' {
        $Rows = @((New-ImportRow -SkuId $script:E5 -Price 40 -Currency 'EUR'))
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Validate'; Currency = 'EUR'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Errors[0].Error | Should -Match 'not supported'
        $script:Writes.Count | Should -Be 0
    }

    It 'rejects a stale review before writing' {
        $Row = New-ImportRow -SkuId $script:E5 -Price 40
        $Row | Add-Member -NotePropertyName CurrentPrice -NotePropertyValue 37.0
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Apply'; Currency = 'GBP'; Rows = @($Row) })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Errors[0].Error | Should -Match 'changed since review'
        $script:Writes.Count | Should -Be 0
    }

    It 'applies multiple changes and reports partial table failures' {
        $script:FailSku = $script:E3
        $Rows = @(
            (New-ImportRow -SkuId $script:E5 -Price 40),
            (New-ImportRow -SkuId $script:E3 -Price 25)
        )
        foreach ($Row in $Rows) {
            $Current = if ($Row.skuId -eq $script:E5) { 38.0 } else { 23.0 }
            $Row | Add-Member -NotePropertyName CurrentPrice -NotePropertyValue $Current
        }
        $Response = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'BulkImport'; Mode = 'Apply'; Currency = 'GBP'; Rows = $Rows })) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Response.Body.Valid | Should -BeTrue
        $Response.Body.Updated | Should -Be 1
        $Response.Body.Unchanged | Should -Be 0
        $Response.Body.Failed | Should -Be 1
        $Response.Body.Errors[0].skuId | Should -Be $script:E3
        $Response.Body.Results | Should -Match 'failed 1'
        $script:Writes.Count | Should -Be 1
        $script:Writes[0].RowKey | Should -Be "$($script:E5)-gbp"
    }

    It 'keeps the existing single-row set and remove actions working' {
        $SetResponse = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'SetPrice'; skuId = $script:E5; Currency = 'GBP'; MonthlyPrice = 31.0; skuPartNumber = 'ENTERPRISEPREMIUM'; Product_Display_Name = 'Office 365 E5' })) -TriggerMetadata $null
        $RemoveResponse = Invoke-ExecLicensePricing -Request (New-Request -Body ([pscustomobject]@{ Action = 'RemovePrice'; skuId = $script:E5; Currency = 'GBP' })) -TriggerMetadata $null

        $SetResponse.StatusCode | Should -Be 200
        $RemoveResponse.StatusCode | Should -Be 200
        $script:Writes.Count | Should -Be 1
        $script:Writes[0].RowKey | Should -Be "$($script:E5)-gbp"
        $script:Removals.Count | Should -Be 1
    }
}
