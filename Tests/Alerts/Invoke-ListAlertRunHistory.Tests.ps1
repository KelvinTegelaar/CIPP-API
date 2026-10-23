# ListAlertRunHistory reads one day partition per requested day and narrows each read by alert, tenant and outcome.
# A tenant matches on its customerId or on the domain the run recorded; outcomes outside the four known ones are a 400.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-ListAlertRunHistory.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-Tenants { param($TenantFilter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Select-CippAllowedTenantData { param([Parameter(ValueFromPipeline)]$InputObject, $TenantProperty) process { $InputObject } }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }

    . $FunctionPath

    function Invoke-List ([hashtable]$Query) { Invoke-ListAlertRunHistory -Request ([pscustomobject]@{ Query = $Query; Body = $null }) }
}

Describe 'Invoke-ListAlertRunHistory' {
    BeforeEach {
        $script:Filters = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPTable { @{ Context = 'stub' } }
        Mock Get-CIPPAzDataTableEntity { $script:Filters.Add($Filter); [pscustomobject]@{ Tenant = 'contoso.com'; Outcome = 'Completed'; ExecutedTime = '1792720800' } }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1'; defaultDomainName = 'contoso.com' } }
    }

    It 'requires tenantFilter' {
        (Invoke-List @{}).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'rejects an unknown outcome without reading the table' {
        $Response = Invoke-List @{ tenantFilter = 'AllTenants'; Outcome = 'Completed,Exploded' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*Exploded*'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'reads one day partition per day and adds no tenant condition for all tenants' {
        $Response = Invoke-List @{ tenantFilter = 'AllTenants'; Days = '3' }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:Filters.Count | Should -Be 3
        $script:Filters[0] | Should -BeExactly "PartitionKey eq '$([datetime]::UtcNow.ToString('yyyyMMdd'))'"
    }

    It 'matches a tenant on its recorded domain or its customerId' {
        $null = Invoke-List @{ tenantFilter = 'contoso.com' }
        $script:Filters[0] | Should -BeLike "* and (Tenant eq 'contoso.com' or TenantId eq 'cust-1')"
    }

    It 'narrows to the requested outcomes and alert' {
        $null = Invoke-List @{ tenantFilter = 'AllTenants'; TaskId = 'task-1'; Outcome = 'Failed, Not reported' }
        $script:Filters[0] | Should -BeLike "* and TaskId eq 'task-1' and (Outcome eq 'Failed' or Outcome eq 'Not reported')"
    }

    It 'accepts outcomes sent as an array in the body' {
        $null = Invoke-ListAlertRunHistory -Request ([pscustomobject]@{ Query = @{}; Body = [pscustomobject]@{ tenantFilter = 'AllTenants'; Outcome = @('Skipped', 'Failed') } })
        $script:Filters[0] | Should -BeLike "*(Outcome eq 'Skipped' or Outcome eq 'Failed')"
    }
}
