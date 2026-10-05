# Pester tests for Set-CIPPDBCacheIntunePolicies: assignment results are matched back to their policy by id
# (first policy wins on a duplicate id), and device statuses are fetched one $batch (20 policies) at a time.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntunePolicies.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntunePolicyListDefinitions.ps1' | Select-Object -First 1).FullName

    function Test-CIPPStandardLicense { $true }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Get-CIPPOmaSettingDecryptedValue { param($DeviceConfiguration, $DeviceConfigurationId, $TenantFilter) }
    function Add-CIPPDbItem {
        param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        $script:Written[$Type] = @($Data)
    }
    function New-GraphBulkRequest {
        param($Requests, $tenantid)
        $script:BulkSizes.Add(@($Requests).Count)
        foreach ($Request in @($Requests)) {
            $Value = if ($Request.url -like '*/assignments') {
                @([pscustomobject]@{ id = "$($Request.id)-assignment" })
            } elseif ($Request.url -like '*/deviceStatuses*') {
                @([pscustomobject]@{ id = "$($Request.id)-status" })
            } elseif ($Request.id -eq 'MobileApps') {
                @([pscustomobject]@{ id = 'app-1'; displayName = 'First' }, [pscustomobject]@{ id = 'app-2'; displayName = 'Second' }, [pscustomobject]@{ id = 'app-1'; displayName = 'Duplicate' })
            } elseif ($Request.id -eq 'DeviceConfigurations') {
                @(foreach ($i in 1..45) { [pscustomobject]@{ id = "cfg-$i"; displayName = "Config $i" } })
            } else {
                @()
            }
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = $Value } }
        }
    }
}

Describe 'Set-CIPPDBCacheIntunePolicies' {
    BeforeEach {
        $script:Written = @{}
        $script:BulkSizes = [System.Collections.Generic.List[int]]::new()
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null
    }

    It 'attaches each assignment result to the first policy with that id' {
        $Apps = $script:Written['IntuneMobileApps']
        $Apps[0].assignments.id | Should -Be 'app-1-assignment'
        $Apps[1].assignments.id | Should -Be 'app-2-assignment'
        $Apps[2].PSObject.Properties['assignments'] | Should -BeNullOrEmpty
    }

    It 'fetches device statuses 20 policies at a time and writes every policy' {
        ($script:BulkSizes -join ',') | Should -Match '(^|,)20,20,5(,|$)'
        foreach ($i in 1..45) { $script:Written["IntuneDeviceConfigurations_cfg-$i"].id | Should -Be "cfg-$i-status" }
    }
}
