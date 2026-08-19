# The pre-write cleanup in Push-ListGraphRequestQueue must see every existing row for the
# tenant, including the physical part rows of a cache blob that was split for size.
# Projecting a subset of the split-entity markers (the old PartitionKey, RowKey,
# OriginalEntityId read) made the table module attempt reassembly, fail on the stripped
# rows, and drop split tenants from $Existing entirely, so their stale rows were never
# removed before the rewrite.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ListGraphRequestQueue.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ListGraphRequestQueue.ps1 under Modules/' }

    # Stubs so Mock has commands to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-GraphRequestList { param($TenantFilter, $Endpoint, $Parameters, $NoPagination, $ReverseTenantLookupProperty, $ReverseTenantLookup, $AsApp, $Caller, $SkipCache) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    # Keep the CacheBridge invalidation branch out of the exercised path.
    $script:OriginalCippNg = $env:CIPPNG
    $env:CIPPNG = 'false'

    $script:Item = [pscustomobject]@{
        Endpoint                    = 'users'
        TenantFilter                = 'contoso.com'
        Parameters                  = @{ '$select' = 'id,displayName' }
        PartitionKey                = 'PKHASH'
        QueueId                     = 'queue-1'
        QueueType                   = 'AllTenants'
        NoPagination                = $false
        ReverseTenantLookupProperty = 'tenantId'
        ReverseTenantLookup         = $false
        AsApp                       = $false
    }
}

AfterAll {
    $env:CIPPNG = $script:OriginalCippNg
}

Describe 'Push-ListGraphRequestQueue pre-write cleanup' {
    BeforeEach {
        $script:Removed = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-GraphRequestList -MockWith { @([pscustomobject]@{ id = '1' }) }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { $script:Removed = $Entity }
    }

    It 'reads existing rows without projecting a subset of the split-entity markers' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        Push-ListGraphRequestQueue -Item $script:Item

        # Either no projection at all (full rows reassemble normally) or one that excludes
        # every marker (raw physical rows come back). A partial marker projection makes the
        # module fail reassembly and silently drop split tenants from the cleanup.
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            ($null -eq $Property) -or (
                $Property -notcontains 'OriginalEntityId' -and
                $Property -notcontains 'PartIndex' -and
                $Property -notcontains 'PartCount' -and
                $Property -notcontains 'SplitOverProps'
            )
        }
    }

    It 'passes every raw row of a split tenant to the delete, part rows included' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{ PartitionKey = 'PKHASH'; RowKey = 'contoso.com' }
                [pscustomobject]@{ PartitionKey = 'PKHASH'; RowKey = 'contoso.com-part1' }
                [pscustomobject]@{ PartitionKey = 'PKHASH'; RowKey = 'contoso.com-part2' }
            )
        }

        Push-ListGraphRequestQueue -Item $script:Item

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1
        @($script:Removed).Count | Should -Be 3
        @($script:Removed).RowKey | Should -Contain 'contoso.com-part2'
    }

    It 'skips the delete when no rows exist for the tenant' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        Push-ListGraphRequestQueue -Item $script:Item

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'still writes the fresh cache row after the cleanup' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }

        Push-ListGraphRequestQueue -Item $script:Item

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Entity.RowKey -eq 'contoso.com' -and $Force
        }
    }
}
