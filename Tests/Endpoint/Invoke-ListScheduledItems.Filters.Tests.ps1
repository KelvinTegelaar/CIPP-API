# Tests for the TaskState and Reference filters on ListScheduledItems.
#
# TaskState is pushed into the storage query (exact match, comma-separated list, casing normalised).
# Reference is matched client-side as a case-insensitive substring, so square-bracketed ticket IDs
# like '[ID:1528]' match literally instead of being read as a -like character set.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListScheduledItems.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListScheduledItems.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors, [switch]$SkipList, [switch]$IncludeAll, [switch]$TriggerRefresh, [switch]$SkipDomains, [switch]$CleanOld) }
    # Return the raw value so filter assertions are predictable (the real helper quotes/escapes).
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }

    . $FunctionPath

    function New-ListRequest {
        param([hashtable]$Query = @{}, [hashtable]$Body = @{})
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListScheduledItems' }
            Headers = @{}
            Query   = [pscustomobject]$Query
            Body    = [pscustomobject]$Body
        }
    }

    # Built fresh per call: the endpoint rewrites Tenant/Parameters on the objects it returns.
    function New-TaskRows {
        @(
            [pscustomobject]@{ RowKey = '1'; Name = 'Add OOO Vacation Mode: bob'; Command = 'Set-CIPPOutOfOffice'; Tenant = 'contoso.com'; TaskState = 'Completed'; Reference = '[ID:1528] Vacation Schedule - Bob' }
            [pscustomobject]@{ RowKey = '2'; Name = 'Remove OOO Vacation Mode: bob'; Command = 'Set-CIPPOutOfOffice'; Tenant = 'contoso.com'; TaskState = 'Planned'; Reference = '[ID:1528] Vacation Schedule - Bob' }
            [pscustomobject]@{ RowKey = '3'; Name = 'Remove OOO Vacation Mode: amy'; Command = 'Set-CIPPOutOfOffice'; Tenant = 'contoso.com'; TaskState = 'Planned'; Reference = '[ID:1516] Vacation Schedule - Amy' }
            # Characters of the bracketed ID, but not the ID itself: matched by -like '*[ID:1528]*', not by the filter.
            [pscustomobject]@{ RowKey = '4'; Name = 'Unrelated task'; Command = 'Set-CIPPOutOfOffice'; Tenant = 'contoso.com'; TaskState = 'Planned'; Reference = 'D' }
            [pscustomobject]@{ RowKey = '5'; Name = 'No reference'; Command = 'Set-CIPPOutOfOffice'; Tenant = 'contoso.com'; TaskState = 'Planned' }
        )
    }
}

Describe 'Invoke-ListScheduledItems TaskState filter' {
    BeforeEach {
        $script:CapturedFilter = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Test-CIPPAccess -MockWith { 'AllTenants' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:CapturedFilter = $Filter; @() }
    }

    It 'adds a single state to the storage filter' {
        $null = Invoke-ListScheduledItems -Request (New-ListRequest -Query @{ TaskState = 'Planned' })
        $script:CapturedFilter | Should -Match "\(TaskState eq 'Planned'\)"
    }

    It 'ORs a comma-separated list of states and trims whitespace' {
        $null = Invoke-ListScheduledItems -Request (New-ListRequest -Query @{ TaskState = 'Planned, Running' })
        $script:CapturedFilter | Should -Match "\(TaskState eq 'Planned' or TaskState eq 'Running'\)"
    }

    It 'normalises casing to the stored title-case form' {
        $null = Invoke-ListScheduledItems -Request (New-ListRequest -Body @{ TaskState = 'pLANNED' })
        $script:CapturedFilter | Should -Match "TaskState eq 'Planned'"
    }

    It 'leaves the storage filter alone when no state is supplied' {
        $null = Invoke-ListScheduledItems -Request (New-ListRequest)
        $script:CapturedFilter | Should -Not -Match 'TaskState'
    }

    It 'ignores an empty list such as a lone comma' {
        $null = Invoke-ListScheduledItems -Request (New-ListRequest -Query @{ TaskState = ' , ' })
        $script:CapturedFilter | Should -Not -Match 'TaskState'
    }
}

Describe 'Invoke-ListScheduledItems Reference filter' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Test-CIPPAccess -MockWith { 'AllTenants' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-TaskRows }
    }

    It 'returns only tasks whose reference contains the bracketed ticket ID' {
        $Response = Invoke-ListScheduledItems -Request (New-ListRequest -Query @{ Reference = '[ID:1528]' })
        @($Response.Body.RowKey) | Sort-Object | Should -Be @('1', '2')
    }

    It 'matches case-insensitively' {
        $Response = Invoke-ListScheduledItems -Request (New-ListRequest -Body @{ Reference = '[id:1516]' })
        @($Response.Body.RowKey) | Should -Be @('3')
    }

    It 'returns everything when no reference is supplied' {
        $Response = Invoke-ListScheduledItems -Request (New-ListRequest)
        @($Response.Body).Count | Should -Be 5
    }

    It 'combines with SearchTitle' {
        $Response = Invoke-ListScheduledItems -Request (New-ListRequest -Query @{ Reference = '[ID:1528]'; SearchTitle = 'Remove*' })
        @($Response.Body.RowKey) | Should -Be @('2')
    }
}
