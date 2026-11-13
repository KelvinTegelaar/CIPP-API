BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Devices = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests/ZTNA/Devices'
    . (Join-Path $Devices 'Invoke-CippTestZTNA24550.ps1')
    . (Join-Path $Devices 'Invoke-CippTestZTNA24552.ps1')

    function Get-CIPPTestData {
        param($TenantFilter, $Type, $Fields, [switch]$Stream)
        switch ($Type) {
            'IntuneConfigurationPolicies' { $script:Policies }
            'IntuneDeviceConfigurations' { $script:DeviceConfigs }
        }
    }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function New-Choice($Id, $Value) { [pscustomobject]@{ settingDefinitionId = $Id; choiceSettingValue = [pscustomobject]@{ value = $Value; children = @() } } }
    function New-Group($Id, $Children) { [pscustomobject]@{ settingDefinitionId = $Id; groupSettingCollectionValue = @([pscustomobject]@{ children = @($Children) }) } }
    function New-Policy($Name, $Platform, $Technologies, $Instances, [int]$Assignments = 0) {
        [pscustomobject]@{
            name              = $Name
            platforms         = $Platform
            technologies      = $Technologies
            templateReference = [pscustomobject]@{ templateFamily = 'none' }
            settings          = @(foreach ($I in $Instances) { [pscustomobject]@{ settingInstance = $I } })
            assignments       = @(for ($i = 0; $i -lt $Assignments; $i++) { [pscustomobject]@{ target = @{} } })
        }
    }
    function New-Legacy($Name, $Type, $Props, [int]$Assignments = 0) {
        $L = [pscustomobject]@{ '@odata.type' = "#microsoft.graph.$Type"; displayName = $Name; assignments = @(for ($i = 0; $i -lt $Assignments; $i++) { [pscustomobject]@{ target = @{} } }) }
        foreach ($K in $Props.Keys) { $L | Add-Member -NotePropertyName $K -NotePropertyValue $Props[$K] }
        $L
    }
    $script:RequireEnc = 'device_vendor_msft_bitlocker_requiredeviceencryption_1'
    $script:FwId = 'com.apple.security.firewall_com.apple.security.firewall'
}

Describe 'ZTNA24550 Windows BitLocker' {
    BeforeEach {
        $script:Policies = @(New-Policy 'Other' 'windows10' 'mdm' @(New-Choice 'device_vendor_msft_policy_config_x' 'x_1') 1)
        $script:DeviceConfigs = @()
    }

    It 'finds Require Device Encryption nested inside a group setting' {
        $script:Policies = @(New-Policy 'Nested' 'windows10' 'mdm' @(New-Group 'device_vendor_msft_bitlocker_group' @(New-Choice 'device_vendor_msft_bitlocker_requiredeviceencryption' $script:RequireEnc)) 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\| Nested \| none \| ✅ Assigned \| 1 \|'
    }

    It 'fails when the BitLocker policy is not assigned' {
        $script:Policies = @(New-Policy 'Top' 'windows10' 'mdm' @(New-Choice 'device_vendor_msft_bitlocker_requiredeviceencryption' $script:RequireEnc))
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '\| Top \| none \| ❌ Not assigned \| 0 \|'
    }

    It 'ignores a macOS policy carrying the same value' {
        $script:Policies = @(New-Policy 'Mac' 'macOS' 'mdm' @(New-Choice 'device_vendor_msft_bitlocker_requiredeviceencryption' $script:RequireEnc) 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
    }

    It 'passes on an assigned legacy endpoint protection profile that encrypts the device' {
        $script:DeviceConfigs = @(New-Legacy 'Legacy EP' 'windows10EndpointProtectionConfiguration' @{ bitLockerEncryptDevice = $true } 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\| Legacy EP \| windows10EndpointProtectionConfiguration \| ✅ Assigned \| 1 \|'
    }

    It 'passes on an assigned legacy general profile that requires storage encryption' {
        $script:DeviceConfigs = @(New-Legacy 'Legacy Gen' 'windows10GeneralConfiguration' @{ storageRequireDeviceEncryption = $true } 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'does not count an endpoint protection profile that leaves BitLocker off' {
        $script:DeviceConfigs = @(New-Legacy 'EP default' 'windows10EndpointProtectionConfiguration' @{ bitLockerEncryptDevice = $false; bitLockerSystemDrivePolicy = [pscustomobject]@{ encryptionMethod = $null } } 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Not -Match 'EP default'
    }

    It 'grades legacy profiles when no settings catalog policies are cached' {
        $script:Policies = @()
        $script:DeviceConfigs = @(New-Legacy 'Legacy EP' 'windows10EndpointProtectionConfiguration' @{ bitLockerEncryptDevice = $true } 1)
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
    }

    It 'skips when neither cache has data' {
        $script:Policies = @()
        Invoke-CippTestZTNA24550 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Skipped'
    }
}

Describe 'ZTNA24552 macOS firewall' {
    BeforeAll {
        function New-Firewall($Name, $Value, [int]$Assignments, $Technologies = 'mdm,appleRemoteManagement') {
            New-Policy $Name 'macOS' $Technologies @(New-Group $script:FwId @((New-Choice 'com.apple.security.firewall_enablefirewall' $Value), (New-Choice 'com.apple.security.firewall_blockallincoming' 'com.apple.security.firewall_blockallincoming_false'))) $Assignments
        }
    }

    It 'passes when an assigned policy enables the firewall' {
        $script:Policies = @((New-Firewall 'FW on' 'com.apple.security.firewall_enablefirewall_true' 1), (New-Policy 'SSO' 'macOS' 'mdm,appleRemoteManagement' @(New-Choice 'com.apple.extensiblesso_x' 'y') 1))
        Invoke-CippTestZTNA24552 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\| FW on \| ✅ Assigned \| 1 \| ✅ Enabled \|'
        $script:Result.Markdown | Should -Not -Match 'SSO'
    }

    It 'fails and lists an assigned policy that disables the firewall' {
        $script:Policies = @(New-Firewall 'FW off' 'com.apple.security.firewall_enablefirewall_false' 1)
        Invoke-CippTestZTNA24552 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Match '\| FW off \| ✅ Assigned \| 1 \| ❌ Disabled \|'
    }

    It 'fails when the enabling policy is not assigned' {
        $script:Policies = @((New-Firewall 'FW on' 'com.apple.security.firewall_enablefirewall_true' 0), (New-Firewall 'FW off' 'com.apple.security.firewall_enablefirewall_false' 1))
        Invoke-CippTestZTNA24552 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
    }

    It 'ignores policies without the Apple remote management technology' {
        $script:Policies = @(New-Firewall 'FW mdm only' 'com.apple.security.firewall_enablefirewall_true' 1 'mdm')
        Invoke-CippTestZTNA24552 -Tenant 'contoso.com'
        $script:Result.Status | Should -Be 'Failed'
        $script:Result.Markdown | Should -Not -Match 'FW mdm only'
    }
}
