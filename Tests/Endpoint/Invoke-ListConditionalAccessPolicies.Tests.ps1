# Pester tests for the AllTenants branch of Invoke-ListConditionalAccessPolicies
# Validates the manualPagination contract over the cacheCAPolicies table, the queue
# fallback on a cold cache (and its suppression mid-walk), and the legacy unpaged path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    # Rows-exist path returns a raw-JSON string Body; queue/cold paths return an object.
    function ConvertFrom-ResponseBody {
        param($Response)
        if ($Response.Body -is [string]) { return ($Response.Body | ConvertFrom-Json) }
        return $Response.Body
    }

    # Stub every CIPP helper the exercised paths call so Pester's Mock has a command to replace.
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Get-CIPPPagedTableRows { param($Table, $PartitionKeys, $RowKeyGe, $RowKeyLt, $ExtraFilterClauses, $PageSize, $MaxQueries, $ContinuationToken) }
    function Get-CIPPQueueData { param($Reference) }
    function New-CippQueueEntry { param($Name, $Link, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }
    function Get-NormalizedError { param($Message) $Message }
    # Real passthrough, not a Mock: the endpoint pipes rows into it, and pipeline binding
    # inside Pester mock bodies is unreliable.
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$Row, $TenantProperty) process { $Row } }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-ListConditionalAccessPolicies.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-CaRequest {
        param([hashtable]$Query = @{})
        $Merged = @{ tenantFilter = 'AllTenants' }
        foreach ($Key in $Query.Keys) { $Merged[$Key] = $Query[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListConditionalAccessPolicies' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Merged
        }
    }

    function New-CacheRow {
        param([string]$Tenant, [string]$Id)
        [PSCustomObject]@{
            PartitionKey = 'CAPolicy'
            RowKey       = [guid]::NewGuid().ToString()
            Tenant       = $Tenant
            Timestamp    = (Get-Date)
            Policy       = (@{ id = $Id; displayName = "Policy $Id"; Tenant = $Tenant } | ConvertTo-Json -Compress)
        }
    }
}

Describe 'Invoke-ListConditionalAccessPolicies AllTenants' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'fake' } }
        Mock -CommandName Get-CIPPQueueData -MockWith { $null }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        Mock -CommandName Get-CIPPPagedTableRows -MockWith { [PSCustomObject]@{ Rows = @(); NextToken = $null } }
        Mock -CommandName New-CippQueueEntry -MockWith { @{ RowKey = 'queue-1' } }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { 'instance-1' }
        Mock -CommandName Get-Tenants -MockWith { @([PSCustomObject]@{ defaultDomainName = 'a.com' }) }
    }

    It 'serves a paged { Results, Metadata } page with nextLink and clamps PageSize' {
        Mock -CommandName Get-CIPPPagedTableRows -MockWith {
            [PSCustomObject]@{
                Rows      = @((New-CacheRow 'a.com' 'p1'), (New-CacheRow 'b.com' 'p2'))
                NextToken = 'CAPolicy|some-guid'
            }
        }

        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest -Query @{ manualPagination = 'true'; PageSize = '10' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.ContentType | Should -Be 'application/json'
        $response.Body | Should -BeOfType [string]
        $body = ConvertFrom-ResponseBody $response
        $body.Results | Should -HaveCount 2
        $body.Results.id | Should -Contain 'p1'
        $body.Metadata.nextLink | Should -Be 'CAPolicy|some-guid'
        Should -Invoke Get-CIPPPagedTableRows -Times 1 -ParameterFilter {
            ($PartitionKeys -join ',') -eq 'CAPolicy' -and $PageSize -eq 250 -and
            ($ExtraFilterClauses -join '') -like 'Timestamp ge datetime*'
        }
        Should -Invoke Start-CIPPOrchestrator -Times 0
    }

    It 'stitches the cached Policy blob verbatim without a parse round-trip' {
        $rowA = New-CacheRow 'a.com' 'p1'
        Mock -CommandName Get-CIPPPagedTableRows -MockWith {
            [PSCustomObject]@{ Rows = @($rowA); NextToken = $null }
        }.GetNewClosure()

        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest -Query @{ manualPagination = 'true' }) -TriggerMetadata $null

        # Exact stored blob bytes must appear verbatim; a parse + re-serialize would restyle them.
        $response.Body | Should -BeLike ('*' + $rowA.Policy + '*')
        $body = ConvertFrom-ResponseBody $response
        $body.Results.id | Should -Be 'p1'
    }

    It 'omits nextLink on the final page' {
        Mock -CommandName Get-CIPPPagedTableRows -MockWith {
            [PSCustomObject]@{ Rows = @((New-CacheRow 'a.com' 'p1')); NextToken = $null }
        }

        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest -Query @{ manualPagination = 'true' }) -TriggerMetadata $null

        $body = ConvertFrom-ResponseBody $response
        $body.Results | Should -HaveCount 1
        $body.Metadata.nextLink | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPPagedTableRows -Times 1 -ParameterFilter { $PageSize -eq 5000 }
    }

    It 'queues the fan-out on a cold cache first page' {
        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest -Query @{ manualPagination = 'true' }) -TriggerMetadata $null

        $response.Body.Metadata.QueueMessage | Should -Match 'Loading data'
        @($response.Body.Results) | Should -HaveCount 0
        Should -Invoke Start-CIPPOrchestrator -Times 1
    }

    It 'does not re-queue when an empty page arrives mid-walk' {
        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest -Query @{ manualPagination = 'true'; nextLink = 'CAPolicy|stale' }) -TriggerMetadata $null

        $body = ConvertFrom-ResponseBody $response
        @($body.Results) | Should -HaveCount 0
        Should -Invoke Start-CIPPOrchestrator -Times 0
        Should -Invoke New-CippQueueEntry -Times 0
    }

    It 'keeps the legacy unpaged full fetch without manualPagination' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @((New-CacheRow 'a.com' 'p1'), (New-CacheRow 'b.com' 'p2'), (New-CacheRow 'c.com' 'p3'))
        }

        $response = Invoke-ListConditionalAccessPolicies -Request (New-CaRequest) -TriggerMetadata $null

        $body = ConvertFrom-ResponseBody $response
        $body.Results | Should -HaveCount 3
        $body.Metadata.nextLink | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPPagedTableRows -Times 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1
    }
}
