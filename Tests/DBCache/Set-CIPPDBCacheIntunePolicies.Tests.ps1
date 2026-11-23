# Pester tests for Set-CIPPDBCacheIntunePolicies: assignment results are matched back to their policy by id
# (first policy wins on a duplicate id), and device statuses are fetched one $batch (20 policies) at a time.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntunePolicies.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyReportTypeFilter.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntunePolicyListDefinitions.ps1' | Select-Object -First 1).FullName

    function Test-CIPPStandardLicense { $true }
    function Get-CIPPIntuneReportRows { param($TenantFilter, $Uri, $Filter, $Select, $OrderBy, $PageSize) , @() }
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

Describe 'Set-CIPPDBCacheIntunePolicies settings catalog device reports' {
    BeforeAll {
        $script:CatalogBase64 = '11111111-1111-4111-8111-111111111111'
        $script:CatalogFailed = '22222222-2222-4222-8222-222222222222'
        $script:CatalogEmpty = '33333333-3333-4333-8333-333333333333'
        $script:CatalogObject = '44444444-4444-4444-8444-444444444444'
        $script:CatalogFull = '55555555-5555-4555-8555-555555555555'
        $script:Columns = @('IntuneDeviceId', 'DeviceName', 'UPN', 'UserId', 'ReportStatus', 'ReportStatus_loc', 'UnifiedPolicyPlatformType', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc')

        function ConvertTo-Base64Body($Object) {
            [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Object | ConvertTo-Json -Depth 5 -Compress)))
        }
        function New-ReportPage {
            param([object[]]$Values, [int]$Total = $Values.Count)
            ConvertTo-Base64Body ([pscustomobject]@{ TotalRowCount = $Total; Schema = @(foreach ($Column in $script:Columns) { [pscustomobject]@{ Column = $Column } }); Values = $Values })
        }
    }

    BeforeEach {
        $script:CatalogIds = @($script:CatalogBase64, $script:CatalogFailed, $script:CatalogEmpty, $script:CatalogObject, $script:CatalogFull)
        $script:ReportBatches = [System.Collections.Generic.List[object]]::new()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Warnings = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage { if ($sev -eq 'Warning') { $script:Warnings.Add($message) } }
        Mock Add-CIPPDbItem { $script:Writes.Add([pscustomobject]@{ Type = $Type; Data = @($Data); AddCount = $AddCount.IsPresent; ClearOnEmpty = $ClearOnEmpty.IsPresent }) }
        Mock New-GraphBulkRequest {
            if (@($Requests)[0].url -like '*/reports/getConfigurationPolicyDevicesReport') {
                $script:ReportBatches.Add(@($Requests))
                foreach ($Request in @($Requests)) {
                    switch ($Request.id) {
                        $script:CatalogBase64 {
                            [pscustomobject]@{ id = $Request.id; status = 200; body = New-ReportPage -Values @(
                                    , @('dev-1', 'PC1', 'a@contoso.com', 'user-1', 'succeeded', 'Succeeded', 'windows10', 'Windows 10 and later', '2026-11-01T10:00:00')
                                    , @('dev-1', 'PC1', '', '00000000-0000-0000-0000-000000000000', 'succeeded', 'Succeeded', 'windows10', 'Windows 10 and later', '2026-11-01T10:00:00')
                                    , @('', 'PC2', 'b@contoso.com', '', 'error', 'Error', 'windows10', 'Windows 10 and later', '2026-11-02T10:00:00')
                                ) }
                        }
                        $script:CatalogObject {
                            $Page = [pscustomobject]@{ TotalRowCount = 1; Schema = @(foreach ($Column in $script:Columns) { [pscustomobject]@{ Column = $Column } }); Values = @(, @('dev-3', 'PC3', 'c@contoso.com', 'user-3', 'conflict', 'Conflict', 'macOS', 'macOS', '2026-11-03T10:00:00')) }
                            [pscustomobject]@{ id = $Request.id; status = 200; body = $Page }
                        }
                        $script:CatalogFailed {
                            [pscustomobject]@{ id = $Request.id; status = 400; body = ConvertTo-Base64Body ([pscustomobject]@{ error = [pscustomobject]@{ code = 'BadRequest'; message = 'Report unavailable' } }) }
                        }
                        $script:CatalogFull {
                            [pscustomobject]@{ id = $Request.id; status = 200; body = New-ReportPage -Total 501 -Values @(foreach ($i in 1..500) { , @("dev-$i", "PC$i", '', "user-$i", 'succeeded', 'Succeeded', 'windows10', 'Windows 10 and later', '2026-11-01T10:00:00') }) }
                        }
                        default {
                            [pscustomobject]@{ id = $Request.id; status = 200; body = New-ReportPage -Values @() }
                        }
                    }
                }
                return
            }
            foreach ($Request in @($Requests)) {
                $Value = if ($Request.url -like '*/deviceStatuses*') {
                    @([pscustomobject]@{ id = "x_$($Request.id)_dev-1"; deviceDisplayName = 'PC1' })
                } elseif ($Request.id -eq 'ConfigurationPolicies') {
                    @(foreach ($Id in $script:CatalogIds) { [pscustomobject]@{ id = $Id; name = "Policy $Id" } })
                } elseif ($Request.id -eq 'DeviceConfigurations') {
                    @([pscustomobject]@{ id = 'cfg-1'; displayName = 'Config 1' })
                } else {
                    @()
                }
                [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = $Value } }
            }
        }
        Mock Get-CIPPIntuneReportRows {
            , @(foreach ($i in 1..501) { [pscustomobject]@{ IntuneDeviceId = "dev-$i"; DeviceName = "PC$i"; UserId = "user-$i"; ReportStatus = 'Succeeded' } })
        }
    }

    It 'requests every catalog policy device report as a POST in one batch, selecting only the columns read' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $script:ReportBatches | Should -HaveCount 1
        $Requests = @($script:ReportBatches[0])
        $Requests.id | Should -Be $script:CatalogIds
        foreach ($Request in $Requests) {
            $Request.method | Should -Be 'POST'
            $Request.url | Should -Be '/deviceManagement/reports/getConfigurationPolicyDevicesReport'
            $Request.headers['Content-Type'] | Should -Be 'application/json'
            $Request.body.top | Should -Be 500
            $Request.body.skip | Should -Be 0
            $Request.body.select | Should -Be @('IntuneDeviceId', 'DeviceName', 'UPN', 'UserId', 'ReportStatus', 'UnifiedPolicyPlatformType', 'PspdpuLastModifiedTimeUtc')
            @($Request.body.select | Where-Object { $_ -like '*_loc' }) | Should -HaveCount 0
            $Request.body.filter | Should -BeLike "*(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy')*"
            $Request.body.filter | Should -BeLike "*(PolicyId eq '$($Request.id)')"
        }
    }

    It 'sends the report requests 20 policies at a time' {
        $script:CatalogIds = @(foreach ($i in 1..45) { '{0:x8}-0000-4000-8000-000000000000' -f $i })

        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        ($script:ReportBatches | ForEach-Object { @($_).Count }) -join ',' | Should -Be '20,20,5'
        @($script:Writes | Where-Object { $_.Type -like 'IntuneConfigurationPolicyDevices_*' }) | Should -HaveCount 45
    }

    It 'reads a base64 report body and caches only the read fields, keyed per device and user context' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $Write = $script:Writes | Where-Object Type -EQ "IntuneConfigurationPolicyDevices_$script:CatalogBase64"
        $Write.AddCount | Should -BeTrue
        $Write.ClearOnEmpty | Should -BeTrue
        $Write.Data.id | Should -Be @('dev-1|PC1|user-1', 'dev-1|PC1|00000000-0000-0000-0000-000000000000', '|PC2|b@contoso.com')
        @($Write.Data[0].PSObject.Properties.Name) | Should -Be @('id', 'IntuneDeviceId', 'DeviceName', 'UPN', 'ReportStatus', 'ReportStatus_loc', 'UnifiedPolicyPlatformType_loc', 'PspdpuLastModifiedTimeUtc')
        $Write.Data[0].IntuneDeviceId | Should -Be 'dev-1'
        $Write.Data[0].ReportStatus | Should -Be 'succeeded'
        $Write.Data[0].ReportStatus_loc | Should -Be 'Succeeded'
        $Write.Data[0].UnifiedPolicyPlatformType_loc | Should -Be 'Windows 10 and later'
    }

    It 'reads a report body that is already an object' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $Write = $script:Writes | Where-Object Type -EQ "IntuneConfigurationPolicyDevices_$script:CatalogObject"
        $Write.Data.id | Should -Be 'dev-3|PC3|user-3'
        $Write.Data.IntuneDeviceId | Should -Be 'dev-3'
        $Write.Data.ReportStatus_loc | Should -Be 'Conflict'
    }

    It 'pages a report whose first page is full through the report reader' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $Write = $script:Writes | Where-Object Type -EQ "IntuneConfigurationPolicyDevices_$script:CatalogFull"
        $Write.Data | Should -HaveCount 501
        $Write.Data[500].id | Should -Be 'dev-501|PC501|user-501'
        Should -Invoke Get-CIPPIntuneReportRows -Times 1 -Exactly
        Should -Invoke Get-CIPPIntuneReportRows -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport' -and
            $Filter -like "*(PolicyId eq '$script:CatalogFull')" -and $PageSize -eq 500 -and @($Select).Count -eq 7
        }
    }

    It 'records an empty report so it reads as no devices rather than no data' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $Write = $script:Writes | Where-Object Type -EQ "IntuneConfigurationPolicyDevices_$script:CatalogEmpty"
        $Write | Should -HaveCount 1
        $Write.Data | Should -HaveCount 0
        $Write.AddCount | Should -BeTrue
        $Write.ClearOnEmpty | Should -BeTrue
    }

    It 'turns a failed report into a warning and keeps the previous cache' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $script:Writes.Type | Should -Not -Contain "IntuneConfigurationPolicyDevices_$script:CatalogFailed"
        $script:Warnings | Where-Object { $_ -like "*device report for ConfigurationPolicies policy $script:CatalogFailed*HTTP 400 - Report unavailable*" } | Should -Not -BeNullOrEmpty
        $script:Writes.Type | Should -Contain "IntuneConfigurationPolicyDevices_$script:CatalogBase64"
    }

    It 'turns a failed report batch into a warning and writes none of its policies' {
        Mock New-GraphBulkRequest -ParameterFilter { @($Requests)[0].url -like '*/reports/*' } -MockWith { throw 'Batch failed' }

        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        @($script:Writes | Where-Object { $_.Type -like 'IntuneConfigurationPolicyDevices_*' }) | Should -HaveCount 0
        $script:Warnings | Where-Object { $_ -like '*device reports for ConfigurationPolicies*Batch failed*' } | Should -Not -BeNullOrEmpty
        $script:Writes.Type | Should -Contain 'IntuneConfigurationPolicies'
    }

    It 'leaves the existing cache types and their rows unchanged' {
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null

        $Catalog = $script:Writes | Where-Object Type -EQ 'IntuneConfigurationPolicies'
        @($Catalog.Data[0].PSObject.Properties.Name) | Should -Be @('id', 'name')
        $Statuses = $script:Writes | Where-Object Type -EQ 'IntuneDeviceConfigurations_cfg-1'
        $Statuses.Data.id | Should -Be 'x_cfg-1_dev-1'
        $Statuses.AddCount | Should -BeFalse
        @($script:Writes.Type | Where-Object { $_ -like 'IntuneConfigurationPolicyDevices*' }) | Should -HaveCount 4
        $script:Writes.Type | Where-Object { $_ -like 'IntuneDeviceCompliancePolicies_*' } | Should -BeNullOrEmpty
    }
}
