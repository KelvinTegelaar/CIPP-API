# Pester tests for Get-CIPPAlertSpecificAppIds
# Covers input normalisation (picker objects, comma separated strings, multi-input objects),
# the single bulk lookup, one lifecycle call per run, and the skip when nothing is configured.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPAlertSpecificAppIds.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $AlertPath) { throw 'Could not locate Get-CIPPAlertSpecificAppIds.ps1 under Modules/' }

    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . $AlertPath

    $script:Exchange = 'b78f6a77-d4e5-46fb-87e5-d1648bd02519'
    $script:Teams = '24205314-2b89-4e07-a2a4-579e898a5640'

    function script:New-Principals {
        param([string[]]$AppIds)
        $Values = foreach ($Id in $AppIds) {
            [pscustomobject]@{ id = "sp-$Id"; appId = $Id; displayName = "App $Id"; accountEnabled = $true; createdDateTime = '2026-01-01T00:00:00Z'; publisherName = 'Vendor'; appOwnerOrganizationId = 'vendor-tenant' }
        }
        @([pscustomobject]@{ body = [pscustomobject]@{ value = @($Values) } })
    }
}

Describe 'Get-CIPPAlertSpecificAppIds' {
    BeforeEach {
        $script:Alerted = $null
        $script:Requests = $null
        Mock -CommandName Write-AlertTrace -MockWith { param($cmdletName, $tenantFilter, $data) $script:Alerted = $data }
        Mock -CommandName Write-LogMessage
        Mock -CommandName New-GraphBulkRequest -MockWith { param($Requests, $tenantid) $script:Requests = $Requests; script:New-Principals -AppIds @($script:Exchange) }
    }

    It 'reports a present app from picker objects and queries all ids in one filter' {
        $Picked = @(
            [pscustomobject]@{ label = 'ConnectWise Exchange'; value = $script:Exchange },
            [pscustomobject]@{ label = 'ConnectWise Teams'; value = $script:Teams }
        )

        Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue $Picked

        Should -Invoke -CommandName New-GraphBulkRequest -Times 1 -Exactly
        @($script:Requests).Count | Should -Be 1
        @($script:Requests)[0].url | Should -Match ([regex]::Escape("appId in ('$($script:Exchange)','$($script:Teams)')"))
        Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
        $Rows = @($script:Alerted)
        $Rows.Count | Should -Be 1
        $Rows[0].AppId | Should -Be $script:Exchange
        $Rows[0].AppName | Should -Be "App $($script:Exchange)"
        $Rows[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'accepts a comma separated string and ignores anything that is not a guid' {
        Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue "$($script:Exchange), not-a-guid ,$($script:Teams)"

        @($script:Requests)[0].url | Should -Match ([regex]::Escape("appId in ('$($script:Exchange)','$($script:Teams)')"))
        @($script:Requests)[0].url | Should -Not -Match 'not-a-guid'
    }

    It 'accepts a multi-input object carrying AppIds and de-duplicates case-insensitively' {
        $Wrapped = [pscustomobject]@{ AppIds = @($script:Exchange, $script:Exchange.ToUpper()) }

        Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue $Wrapped

        @($script:Requests)[0].url | Should -Match ([regex]::Escape("appId in ('$($script:Exchange)')"))
    }

    It 'reconciles once with empty data when none of the apps are present' {
        Mock -CommandName New-GraphBulkRequest -MockWith { script:New-Principals -AppIds @() }

        Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue @($script:Exchange)

        Should -Invoke -CommandName Write-AlertTrace -Times 1 -Exactly
        @($script:Alerted) | Should -BeNullOrEmpty
    }

    It 'skips without reconciling when no valid app id is configured' {
        Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue 'nothing-valid'

        Should -Invoke -CommandName New-GraphBulkRequest -Times 0
        Should -Invoke -CommandName Write-AlertTrace -Times 0
        Should -Invoke -CommandName Write-LogMessage -Times 1 -Exactly
    }

    It 'does not reconcile when the lookup fails' {
        Mock -CommandName New-GraphBulkRequest -MockWith { throw 'Graph unavailable' }

        { Get-CIPPAlertSpecificAppIds -TenantFilter 'contoso.onmicrosoft.com' -InputValue @($script:Exchange) } | Should -Not -Throw

        Should -Invoke -CommandName Write-AlertTrace -Times 0
    }
}
