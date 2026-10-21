BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }

    $script:AsOf = [datetime]::new(2026, 10, 20, 12, 0, 0, [System.DateTimeKind]::Utc)

    function New-TestDeviceParams {
        @{
            Device   = [PSCustomObject]@{
                id = 'mdm-1'; deviceName = 'LAPTOP-ADA'; userDisplayName = 'Ada Lovelace'; userPrincipalName = 'ada@fabrikam.example'
                ownerType = 'company'; enrolledDateTime = '2025-05-25T08:00:00Z'; lastSyncDateTime = '2026-10-19T08:00:00Z'
                complianceState = 'compliant'; managementAgent = 'mdm'; serialNumber = 'SER-001'; operatingSystem = 'Windows'; osVersion = '10.0.26100.1'
                chassisType = 'laptop'; model = 'Model X'; manufacturer = 'Contoso'; totalStorageSpaceInBytes = 512GB; freeStorageSpaceInBytes = 256GB
                deviceEnrollmentType = 'windowsAzureADJoin'; joinType = 'azureADJoined'; deviceRegistrationState = 'registered'; autopilotEnrolled = $true
                hardwareinformation = [PSCustomObject]@{
                    deviceGuardVirtualizationBasedSecurityHardwareRequirementState = 'meetHardwareRequirements'
                    deviceGuardVirtualizationBasedSecurityState = 'running'
                    deviceGuardLocalSystemAuthorityCredentialGuardState = 'running'
                }
            }
            Tenant   = [PSCustomObject]@{ defaultDomainName = 'fabrikam.example' }
            Policies = @(
                [PSCustomObject]@{ Name = 'Windows baseline'; Status = 'compliant'; LastReported = '2026-10-19T08:00:00Z'; GraceExpiry = $null }
                [PSCustomObject]@{ Name = 'BitLocker required'; Status = 'inGracePeriod'; LastReported = '2026-10-19T08:00:00Z'; GraceExpiry = '2026-10-25T00:00:00Z' }
            )
            Groups   = @('All Devices', 'Autopilot Devices')
            RmmLinks = @(@{ Label = 'Datto RMM'; Tip = 'Open in Datto RMM'; Url = 'https://rmm.example/device/42' })
            AsOf     = $script:AsOf
        }
    }
    function Get-TestAttention([hashtable]$Params) { @(Get-HuduDeviceAttentionItems -Model (Get-HuduDeviceViewModel @Params)) }
}

Describe 'Get-HuduDeviceBody' {
    It 'renders every section for a full model' {
        $Params = New-TestDeviceParams
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params) -SyncedAt $script:AsOf
        foreach ($Heading in 'Device details', 'Hardware', 'Enrollment and security', 'Compliance policies', 'Groups') {
            $Body | Should -Match ">$Heading( <span|</span></h3>)"
        }
        foreach ($Text in 'LAPTOP-ADA', '>Compliant<', 'Windows 10.0.26100.1', 'Ada Lovelace (ada@fabrikam.example)', 'Synced 20 Oct 2026 12:00 UTC',
            '>Intune<', '>RMM<', '>Datto RMM<', 'SER-001', 'Laptop', '256 GB <span style="opacity:.7">of 512 GB, 256 GB free', 'Windows Azure AD join', '>MDM<',
            'Meet hardware requirements', '>Yes<', 'Windows baseline', 'In grace period', '25 Oct 2026', 'Autopilot Devices', '25 May 2025', '19 Oct 2026') {
            $Body | Should -Match ([regex]::Escape($Text))
        }
        $Body | Should -Match 'width:50%;background:#f77f00'
        $Body | Should -Not -Match 'Needs attention'
    }

    It 'leaves out empty policy and group cards and the RMM links' {
        $Params = New-TestDeviceParams
        $Params.Policies = @(); $Params.Groups = @(); $Params.RmmLinks = @()
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        $Body | Should -Not -Match 'Compliance policies|>Groups|>RMM<'
    }

    It 'uses nothing the Hudu sanitizer strips and the brand header' {
        $Params = New-TestDeviceParams
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Not -Match 'gap:|<svg|aria-hidden'
        $Body | Should -Match '^<div style="overflow:hidden"><div style="border:1px solid rgba\(128,128,128,.3\);border-top:3px solid #f77f00;'
        $Body | Should -Match '<table style="width:100%;border:0;margin:0;table-layout:auto'
    }

    It 'uses no layout CSS that Hudu or its mobile app drops' {
        $Params = New-TestDeviceParams
        $Params.Device.complianceState = 'noncompliant'
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Match 'Needs attention'
        $Body | Should -Not -Match 'display:(inline-)?flex|justify-content|float:|gap:'
    }

    It 'encodes every data value and only links http and https URLs' {
        $Evil = '<script>alert(1)</script>"x'
        $Params = New-TestDeviceParams
        $Params.Device.deviceName = $Evil
        $Params.Device.userDisplayName = $Evil
        $Params.Device.model = $Evil
        $Params.Policies[0].Name = $Evil
        $Params.Groups = @($Evil)
        $Params.RmmLinks = @(
            @{ Label = $Evil; Tip = $Evil; Url = 'https://rmm.example/d" onmouseover="alert(1)' }
            @{ Label = 'CW Control'; Tip = 'x'; Url = 'javascript:alert(1)' }
        )
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params) -SyncedAt $script:AsOf
        $Body | Should -Not -Match '<script'
        $Body | Should -Not -Match '"x'
        $Body | Should -Not -Match '" onmouseover='
        $Body | Should -Not -Match 'javascript:'
        $Body | Should -Match '<span>CW Control</span>'
        $Body | Should -Match ([regex]::Escape('&lt;script&gt;alert(1)&lt;/script&gt;&quot;x'))
    }

    It 'hashes the same body on consecutive days, without the Synced line' {
        $Params = New-TestDeviceParams
        $Params.Device.lastSyncDateTime = '2026-08-01T08:00:00Z'
        $First = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        $First | Should -Match 'Not synced in over 30 days'
        $Params.AsOf = $script:AsOf.AddDays(1)
        $Second = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        $Second | Should -BeExactly $First
        $First | Should -Not -Match '>Synced '
        Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params) -SyncedAt $script:AsOf | Should -Match '>Synced '
    }
}

Describe 'Hudu labels' {
    It 'humanises <Value> as <Expected>' -ForEach @(
        @{ Value = 'hybridAzureADJoined'; Expected = 'Hybrid Azure AD joined' }
        @{ Value = 'windowsAzureADJoin'; Expected = 'Windows Azure AD join' }
        @{ Value = 'windowsCoManagement'; Expected = 'Windows co-management' }
        @{ Value = 'enabledWithoutUEFILock'; Expected = 'Enabled without UEFI lock' }
        @{ Value = 'meetHardwareRequirements'; Expected = 'Meet hardware requirements' }
        @{ Value = 'company'; Expected = 'Company' }
    ) {
        Get-HuduUiHumanized $Value | Should -BeExactly $Expected
    }

    It 'names the management agent <Agent> as <Expected>' -ForEach @(
        @{ Agent = 'mdm'; Expected = 'MDM' }
        @{ Agent = 'eas'; Expected = 'EAS' }
        @{ Agent = 'easMdm'; Expected = 'EAS/MDM' }
        @{ Agent = 'configurationManagerClient'; Expected = 'Configuration Manager' }
        @{ Agent = 'configurationManagerClientMdm'; Expected = 'Configuration Manager/MDM' }
        @{ Agent = 'intuneClient'; Expected = 'Intune client' }
        @{ Agent = 'jamf'; Expected = 'Jamf' }
        @{ Agent = 'googleCloudDevicePolicyController'; Expected = 'Google Cloud device policy controller' }
        @{ Agent = 'someFutureAgent'; Expected = 'Some future agent' }
    ) {
        $Params = New-TestDeviceParams
        $Params.Device.managementAgent = $Agent
        (Get-HuduDeviceViewModel @Params).Details.ManagementAgent | Should -BeExactly $Expected
    }

    It 'keeps row labels on one line' {
        New-HuduUiRow -Label 'Storage' -Value 'x' | Should -Match '<td style="[^"]*white-space:nowrap[^"]*">Storage</td>'
        $Params = New-TestDeviceParams
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        $Body | Should -Match '<td style="[^"]*white-space:nowrap[^"]*">Storage</td>'
    }
}

Describe 'New-HuduUiCard row tables' {
    It 'wraps each run of rows in one table and leaves other tables alone' {
        $Inner = '<table style="x"><tbody><tr><td>a</td></tr><tr><td>b</td></tr></tbody></table>'
        $Body = (New-HuduUiRow -Label 'A' -Value '1') + (New-HuduUiRow -Label 'B' -Value '2') + '<div>mid</div>' + (New-HuduUiRow -Label 'C' -Value '3') + $Inner
        $Card = New-HuduUiCard -Title 'T' -Body $Body
        [regex]::Matches($Card, '<table').Count | Should -Be 3
        $Card | Should -Match '<table style="width:100%[^"]*"><tbody><tr><td[^>]*>A</td><td[^>]*>1</td></tr><tr><td[^>]*>B</td>'
        $Card | Should -Match ([regex]::Escape($Inner))
    }

    It 'renders each device card, storage included, as one table' {
        $Params = New-TestDeviceParams
        $Params.Policies = @()
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        [regex]::Matches($Body, '<table').Count | Should -Be 3
        $Body | Should -Match '>Manufacturer</td>(?:(?!</table>).)*>Storage</td>'
    }
}

Describe 'Get-HuduDeviceAttentionItems' {
    It 'returns nothing when nothing applies' {
        Get-TestAttention (New-TestDeviceParams) | Should -BeNullOrEmpty
    }

    It 'flags a non-compliant device and not one in grace period' {
        $Params = New-TestDeviceParams
        $Params.Device.complianceState = 'inGracePeriod'
        Get-TestAttention $Params | Should -BeNullOrEmpty
        $Params.Device.complianceState = 'noncompliant'
        Get-TestAttention $Params | Should -Be 'Device is **non-compliant**'
    }

    It 'flags a device not synced in more than 30 days' {
        $Params = New-TestDeviceParams
        $Params.Device.lastSyncDateTime = $script:AsOf.AddDays(-30).ToString('o')
        Get-TestAttention $Params | Should -BeNullOrEmpty
        $Params.Device.lastSyncDateTime = $script:AsOf.AddDays(-31).ToString('o')
        Get-TestAttention $Params | Should -Be '**Not synced in over 30 days**'
    }

    It 'flags storage 90% used and not below' {
        $Params = New-TestDeviceParams
        $Params.Device.totalStorageSpaceInBytes = 1000; $Params.Device.freeStorageSpaceInBytes = 100
        Get-TestAttention $Params | Should -Match '^Storage is \*\*90%\*\* full'
        $Params.Device.freeStorageSpaceInBytes = 101
        Get-TestAttention $Params | Should -BeNullOrEmpty
    }

    It 'renders the strip under the header' {
        $Params = New-TestDeviceParams
        $Params.Device.complianceState = 'noncompliant'
        $Body = Get-HuduDeviceBody -Model (Get-HuduDeviceViewModel @Params)
        $Body | Should -Match 'Device is <strong>non-compliant</strong>'
        $Body.IndexOf('Needs attention') | Should -BeLessThan $Body.IndexOf('>Device details</span></h3>')
    }
}
