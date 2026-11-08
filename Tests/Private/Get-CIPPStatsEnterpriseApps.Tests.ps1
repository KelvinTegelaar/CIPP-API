# Pester tests for Get-CIPPStatsEnterpriseApps: non-Microsoft, non-default enterprise apps counted by the tenants they appear in.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CippJson' -as [type])) { Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') }
    function Get-CIPPDbItem { param($Partition, $Type) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CIPPVendorTenantMap { }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPStatsEnterpriseApps.ps1')

    function New-Row($Object) { [pscustomobject]@{ Data = ($Object | ConvertTo-Json -Compress -Depth 5) } }
}

Describe 'Get-CIPPStatsEnterpriseApps' {
    BeforeEach {
        Mock Get-CIPPVendorTenantMap {
            $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Map['f8cdef31-a31e-4b4a-93e4-5f571e91255a'] = [pscustomobject]@{ Name = 'Microsoft'; VendorType = 'Microsoft' }
            $Map['22222222-2222-2222-2222-222222222222'] = [pscustomobject]@{ Name = 'Some RMM'; VendorType = 'MSP' }
            $Map
        }
    }

    It 'counts non-Microsoft apps once per tenant and skips Microsoft, CIPP, managed identity and other default principals' {
        $env:ApplicationID = 'cipp-sam-app'
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 't1.com' }; [pscustomobject]@{ defaultDomainName = 't2.com' } }
        Mock Get-CIPPDbItem {
            $Rows = @{}
            $Rows['t1.com'] = @(
                (New-Row @{ id = '1'; appId = 'app-a'; displayName = 'MyEnterpriseApp'; appOwnerOrganizationId = '11111111-1111-1111-1111-111111111111'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '2'; appId = 'app-a'; displayName = 'MyEnterpriseApp'; appOwnerOrganizationId = '11111111-1111-1111-1111-111111111111'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '3'; appId = 'ms-app'; displayName = 'Office 365 Exchange Online'; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '4'; appId = 'app-b'; displayName = 'Managed Identity'; appOwnerOrganizationId = $null; servicePrincipalType = 'ManagedIdentity' })
                (New-Row @{ id = '7'; appId = 'cipp-sam-app'; displayName = 'CIPP-SAM'; appOwnerOrganizationId = '33333333-3333-3333-3333-333333333333'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '8'; appId = 'legacy'; displayName = 'Legacy'; appOwnerOrganizationId = $null; servicePrincipalType = 'Legacy' })
            )
            $Rows['t2.com'] = @(
                (New-Row @{ id = '5'; appId = 'app-a'; displayName = 'MyEnterpriseApp'; appOwnerOrganizationId = '11111111-1111-1111-1111-111111111111'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '6'; appId = 'app-c'; displayName = 'OtherApp'; appOwnerOrganizationId = '22222222-2222-2222-2222-222222222222'; servicePrincipalType = 'Application' })
                (New-Row @{ id = '9'; appId = 'cipp-sam-app'; displayName = 'CIPP-SAM'; appOwnerOrganizationId = '33333333-3333-3333-3333-333333333333'; servicePrincipalType = 'Application' })
            )
            $Rows[$Partition]
        }
        $r = @(Get-CIPPStatsEnterpriseApps)
        $r.Count | Should -Be 2
        $r[0].ID | Should -Be 'app-a'
        $r[0].DisplayName | Should -Be 'MyEnterpriseApp'
        $r[0].Count | Should -Be 2
        $r[1].ID | Should -Be 'app-c'
        $r[1].Count | Should -Be 1
        Should -Invoke Get-CIPPDbItem -Times 2 -Exactly -ParameterFilter { $Partition -in 't1.com', 't2.com' -and $Type -eq 'ServicePrincipals' }
    }

    It 'returns an empty list when the read fails' {
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 't1.com' } }
        Mock Get-CIPPDbItem { throw 'boom' }
        @(Get-CIPPStatsEnterpriseApps).Count | Should -Be 0
    }
}
