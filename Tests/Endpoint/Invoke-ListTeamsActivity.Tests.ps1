# Pester tests for Invoke-ListTeamsActivity
#
# Type is spliced into a Graph report URL and a reporting-cache type name, so it must be a bare report name.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListTeamsActivity.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListTeamsActivity.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTeamsActivityReport { param($TenantFilter, $Type) }
    function Get-CIPPReportPage { param($TenantFilter, $Type, $PageSize, $ContinuationToken, $Report) }

    . $FunctionPath
}

Describe 'Invoke-ListTeamsActivity Type validation' {
    BeforeEach {
        Mock New-GraphGetRequest { '' }
        Mock Get-CIPPTeamsActivityReport { @() }
    }

    It 'rejects a Type that is not a bare report name on the <Path> path' -ForEach @(
        @{ Path = 'cache'; Query = @{ UseReportDB = 'true' }; Type = "TeamsUserActivityUser' or PartitionKey ne '" }
        @{ Path = 'live'; Query = @{}; Type = 's/../../users?x=' }
    ) {
        $Query.tenantFilter = 'a.com'
        $Query.Type = $Type
        $Response = Invoke-ListTeamsActivity -Request @{ Query = $Query }
        $Response.StatusCode | Should -Be ([int][HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke Get-CIPPTeamsActivityReport -Times 0
    }

    It 'serves the report name the frontend sends' {
        $Response = Invoke-ListTeamsActivity -Request @{ Query = @{ tenantFilter = 'a.com'; Type = 'TeamsUserActivityUser'; UseReportDB = 'true' } }
        $Response.StatusCode | Should -Be ([int][HttpStatusCode]::OK)
        Should -Invoke Get-CIPPTeamsActivityReport -Times 1 -ParameterFilter { $Type -eq 'TeamsUserActivityUser' }
    }

    It 'calls the live Graph report for a valid name' {
        $null = Invoke-ListTeamsActivity -Request @{ Query = @{ tenantFilter = 'a.com'; Type = 'TeamsUserActivityUser' } }
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -eq "https://graph.microsoft.com/beta/reports/getTeamsUserActivityUserDetail(period='D30')" }
    }
}
