# Pester tests for Invoke-ListAuditLogCoverage.
#
# The coverage ledger holds one row per tenant per hour and nothing else trims it, so the
# endpoint must push the date range and the tenant selector into the table query rather than
# load every row and sift in memory - that is what made the page time out on a large instance.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAuditLogCoverage.ps1' -File | Select-Object -First 1 -ExpandProperty FullName
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param([switch]$IncludeErrors) }

    . $FunctionPath

    function New-Request { param($Query) [pscustomobject]@{ Query = $Query; Body = @{} } }
}

Describe 'Invoke-ListAuditLogCoverage' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Get-CIPPAzDataTableEntity { @() }
    }

    It 'queries one tenant partition within the window range instead of the whole ledger' {
        $null = Invoke-ListAuditLogCoverage -Request (New-Request @{ tenantFilter = 'contoso.onmicrosoft.com'; RelativeTime = '48h' })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Filter -match "^WindowStart ge datetime'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z' and WindowStart le datetime'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z' and PartitionKey eq 'contoso.onmicrosoft.com'$"
        }
    }

    It 'matches on TenantId when the selector carries a customer id' {
        $null = Invoke-ListAuditLogCoverage -Request (New-Request @{ tenantFilter = '11111111-2222-3333-4444-555555555555' })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "*TenantId eq '11111111-2222-3333-4444-555555555555'" -and $Filter -notlike '*PartitionKey*' }
    }

    It 'keeps the range but no tenant clause for AllTenants' {
        $null = Invoke-ListAuditLogCoverage -Request (New-Request @{ tenantFilter = 'AllTenants'; RelativeTime = '7d' })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "WindowStart ge datetime'*' and WindowStart le datetime'*'" -and $Filter -notlike '*PartitionKey*' -and $Filter -notlike '*TenantId*' }
    }

    It 'escapes a quote in the selector rather than breaking the filter' {
        $null = Invoke-ListAuditLogCoverage -Request (New-Request @{ tenantFilter = "o'brien.example" })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "*PartitionKey eq 'o''brien.example'" }
    }

    It 'still applies tenant access control to the returned rows' {
        Mock Test-CIPPAccess { @('tid-allowed') }
        Mock Get-Tenants { @([pscustomobject]@{ customerId = 'tid-allowed'; defaultDomainName = 'allowed.example' }) }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ PartitionKey = 'allowed.example'; RowKey = 'a'; TenantId = 'tid-allowed'; WindowStart = (Get-Date).ToUniversalTime().AddHours(-1); State = 'Downloaded' }
                [pscustomobject]@{ PartitionKey = 'other.example'; RowKey = 'b'; TenantId = 'tid-other'; WindowStart = (Get-Date).ToUniversalTime().AddHours(-1); State = 'Downloaded' }
            )
        }
        $Response = Invoke-ListAuditLogCoverage -Request (New-Request @{ tenantFilter = 'AllTenants' })
        $Body = $Response.Body | ConvertFrom-Json
        @($Body.Results).Count | Should -Be 1
        $Body.Results[0].Tenant | Should -Be 'allowed.example'
    }
}
