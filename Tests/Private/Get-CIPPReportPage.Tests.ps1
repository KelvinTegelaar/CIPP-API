BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPReportPage.ps1')

    $script:Report = { param($Tenant) 1..2 | ForEach-Object { [PSCustomObject]@{ id = "$Tenant-$_"; Tenant = 'stale' } } }
    $script:Walk = {
        param($PageSize)
        $Token = $null
        do {
            $Page = Get-CIPPReportPage -TenantFilter 'AllTenants' -Type 'Teams' -Report $script:Report -PageSize $PageSize -ContinuationToken $Token
            , $Page
            $Token = $Page.Metadata.nextLink
        } while ($Token)
    }
}

Describe 'Get-CIPPReportPage' {
    BeforeEach {
        Mock Get-Tenants { @('c.com', 'a.com', 'b.com', 'd.com') | ForEach-Object { [PSCustomObject]@{ defaultDomainName = $_ } } }
        Mock Get-CIPPDbItem {
            [PSCustomObject]@{ PartitionKey = 'c.com'; DataCount = 300 }
            [PSCustomObject]@{ PartitionKey = 'a.com'; DataCount = 200 }
            [PSCustomObject]@{ PartitionKey = 'b.com'; DataCount = 100 }
            [PSCustomObject]@{ PartitionKey = 'd.com'; DataCount = 0 }
            [PSCustomObject]@{ PartitionKey = 'gone.com'; DataCount = 50 }
        }
        Mock Write-LogMessage {}
    }

    It 'walks managed tenants with data in ordinal order, whole tenants per page, each exactly once' {
        $Pages = @(& $script:Walk 250)
        $Pages.Count | Should -Be 2
        $Pages[0].Results.Tenant | Should -Be @('a.com', 'a.com', 'b.com', 'b.com')
        $Pages[0].Metadata.nextLink | Should -Be 'b.com'
        $Pages[1].Results.Tenant | Should -Be @('c.com', 'c.com')
        $Pages[1].Metadata.Contains('nextLink') | Should -BeFalse
    }

    It 'serves everything on one page when the budget is not reached' {
        $Pages = @(& $script:Walk 5000)
        $Pages.Count | Should -Be 1
        @($Pages[0].Results).Count | Should -Be 6
    }

    It 'plans over the union of several cache types and sums their counts' {
        Mock Get-CIPPDbItem -ParameterFilter { $Type -eq 'Scripts' } {
            [PSCustomObject]@{ PartitionKey = 'd.com'; DataCount = 10 }
            [PSCustomObject]@{ PartitionKey = 'a.com'; DataCount = 100 }
        }
        $Page = Get-CIPPReportPage -TenantFilter 'AllTenants' -Type 'Teams', 'Scripts' -Report $script:Report -PageSize 300
        @($Page.Results.Tenant | Select-Object -Unique) | Should -Be @('a.com')
        $Page.Metadata.nextLink | Should -Be 'a.com'
        $Rest = Get-CIPPReportPage -TenantFilter 'AllTenants' -Type 'Teams', 'Scripts' -Report $script:Report -PageSize 5000 -ContinuationToken 'a.com'
        @($Rest.Results.Tenant | Select-Object -Unique) | Should -Be @('b.com', 'c.com', 'd.com')
    }

    It 'logs a failing tenant and keeps the rest of the page' {
        $script:Report = { param($Tenant) if ($Tenant -eq 'a.com') { throw 'boom' }; [PSCustomObject]@{ id = $Tenant } }
        $Page = Get-CIPPReportPage -TenantFilter 'AllTenants' -Type 'Teams' -Report $script:Report
        $Page.Results.Tenant | Should -Be @('b.com', 'c.com')
        Should -Invoke Write-LogMessage -Times 1
    }

    It 'serves nothing to a caller whose allowed-tenant scope is empty' {
        Mock Get-Tenants { @() }
        $Report = { param($Tenant) throw "read $Tenant" }
        $Page = Get-CIPPReportPage -TenantFilter 'AllTenants' -Type 'Teams' -Report $Report
        @($Page.Results).Count | Should -Be 0
        $Page.Metadata.Count | Should -Be 0
        Should -Invoke Write-LogMessage -Times 0
    }

    It 'serves a single tenant as one page without stamping Tenant' {
        $Page = Get-CIPPReportPage -TenantFilter 'a.com' -Type 'Teams' -Report { param($Tenant) [PSCustomObject]@{ id = $Tenant } }
        $Page.Results.id | Should -Be 'a.com'
        $Page.Results[0].PSObject.Properties.Name | Should -Not -Contain 'Tenant'
        $Page.Metadata.Count | Should -Be 0
        Should -Invoke Get-CIPPDbItem -Times 0
    }
}
