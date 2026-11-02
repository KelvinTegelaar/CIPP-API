BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $CaFolder = Join-Path $RepoRoot 'Modules/CIPPCore/Public/SecuritySimulations/CAAnalysis'
    . (Join-Path $CaFolder 'ConvertTo-CIPPCANormalizedPolicy.ps1')
    . (Join-Path $CaFolder 'New-CIPPCAGapFinding.ps1')
    . (Join-Path $CaFolder 'Test-CIPPCAGapMicrosoftGuidance.ps1')
    . (Join-Path $CaFolder 'Get-CIPPCAPersonaMatrix.ps1')
    function Test-CIPPCAPolicyPhishingResistant { param($Policy, $Context) $false }

    $DataFolder = Join-Path $RepoRoot 'Config/SecuritySimulations/CAAnalysis'
    $script:Reference = Get-Content (Join-Path $DataFolder 'Reference.json') -Raw | ConvertFrom-Json -Depth 20
    $script:Guidance = @(Get-Content (Join-Path $DataFolder 'MicrosoftGuidance.json') -Raw | ConvertFrom-Json -Depth 20)
    $script:CoverageControls = Get-Content (Join-Path $DataFolder 'CoverageControls.json') -Raw | ConvertFrom-Json -Depth 20
    $script:Apps = $script:Reference.guidanceAppIds
    $script:GlobalAdminRole = '62e90394-69f5-4237-9190-012177145e10'
    $script:DirSyncRole = 'd29b2b05-8046-44ba-8758-1e26182fcf32'
    $script:LegacyAuthLabel = "$($script:CoverageControls.BlockLegacyAuth.label)"

    function New-Context {
        param([object[]]$RawPolicies)
        $Policies = @($RawPolicies | ForEach-Object { ConvertTo-CIPPCANormalizedPolicy -Policy $_ })
        @{
            TenantFilter  = 'contoso.com'
            Policies      = $Policies
            Enabled       = @($Policies | Where-Object { $_.state -eq 'enabled' })
            ReportOnly    = @()
            Disabled      = @()
            AuthStrengths = @{}
            Licenses      = @{ HasEntraIdP1 = $true; HasEntraIdP2 = $true; HasIntunePlan1 = $true; HasWorkloadIdPremium = $false }
            Data          = @{
                Reference              = $script:Reference
                MicrosoftGuidance      = $script:Guidance
                CoverageControls       = $script:CoverageControls
                HighPrivilegeRoleNames = @{ $script:GlobalAdminRole = 'Global Administrator' }
            }
        }
    }

    function New-TokenProtectionPolicy {
        param(
            [string]$Name,
            [string[]]$Platforms,
            [string[]]$ClientAppTypes = @('mobileAppsAndDesktopClients'),
            [string]$DeviceFilterRule,
            [string[]]$IncludeApplications
        )
        if (-not $IncludeApplications) { $IncludeApplications = @($script:Apps.exchangeOnline, $script:Apps.sharePointOnline, $script:Apps.teamsService) }
        $Conditions = [pscustomobject]@{
            users          = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @('11111111-1111-1111-1111-111111111111') }
            applications   = [pscustomobject]@{ includeApplications = $IncludeApplications }
            clientAppTypes = $ClientAppTypes
            platforms      = if ($Platforms) { [pscustomobject]@{ includePlatforms = $Platforms; excludePlatforms = @() } } else { $null }
            devices        = if ($DeviceFilterRule) { [pscustomobject]@{ deviceFilter = [pscustomobject]@{ mode = 'exclude'; rule = $DeviceFilterRule } } } else { $null }
        }
        [pscustomobject]@{
            id              = [guid]::NewGuid().ToString()
            displayName     = $Name
            state           = 'enabled'
            conditions      = $Conditions
            grantControls   = $null
            sessionControls = [pscustomobject]@{ secureSignInSession = [pscustomobject]@{ isEnabled = $true } }
        }
    }

    function New-LegacyAuthBlockPolicy {
        param([string[]]$ExcludeRoles = @())
        [pscustomobject]@{
            id              = [guid]::NewGuid().ToString()
            displayName     = 'CA100 Block legacy authentication'
            state           = 'enabled'
            conditions      = [pscustomobject]@{
                users          = [pscustomobject]@{ includeUsers = @('All'); excludeGroups = @('22222222-2222-2222-2222-222222222222'); excludeRoles = $ExcludeRoles }
                applications   = [pscustomobject]@{ includeApplications = @('All') }
                clientAppTypes = @('exchangeActiveSync', 'other')
            }
            grantControls   = [pscustomobject]@{ operator = 'OR'; builtInControls = @('block') }
            sessionControls = $null
        }
    }

    function Get-AdminLegacyAuthCell {
        param($Matrix)
        $Matrix.cells | Where-Object { $_.persona -eq 'Admins' -and $_.control -eq $script:LegacyAuthLabel }
    }

    $script:WindowsDeviceFilter = '(device.systemLabels -contains "CloudPC" and device.trustType -eq "AzureAD") -or (device.systemLabels -contains "AzureVirtualDesktop" and device.trustType -eq "AzureAD") -or (device.systemLabels -contains "MicrosoftPowerAutomate" and device.trustType -eq "AzureAD") -or (device.enrollmentProfileName -eq "Autopilot self-deploying") -or (device.profileType -eq "SecureVM" and device.trustType -eq "AzureAD")'
}

Describe 'Test-CIPPCAGapMicrosoftGuidance token protection checks' {
    It 'accepts the Microsoft-documented Windows device filter, including the Power Automate clause' {
        $Context = New-Context -RawPolicies @(New-TokenProtectionPolicy -Name 'CA208 Windows token protection' -Platforms @('windows') -DeviceFilterRule $script:WindowsDeviceFilter)
        $Findings = @(Test-CIPPCAGapMicrosoftGuidance -Context $Context)
        @($Findings | Where-Object { $_.title -like 'Token protection*' }) | Should -BeNullOrEmpty
    }

    It 'still flags a Windows policy whose filter forgets a device type' {
        $Rule = 'device.systemLabels -contains "CloudPC" and device.trustType -eq "AzureAD"'
        $Context = New-Context -RawPolicies @(New-TokenProtectionPolicy -Name 'CA208 Windows token protection' -Platforms @('windows') -DeviceFilterRule $Rule)
        $Finding = @(Test-CIPPCAGapMicrosoftGuidance -Context $Context) | Where-Object { $_.title -eq 'Token protection does not exempt devices that cannot support it' }
        $Finding | Should -Not -BeNullOrEmpty
        $Finding.description | Should -Match 'Power Automate hosted machines'
        $Finding.description | Should -Not -Match 'Cloud PCs'
    }

    It 'still flags a Windows policy without any device filter' {
        $Context = New-Context -RawPolicies @(New-TokenProtectionPolicy -Name 'CA208 Windows token protection' -Platforms @('windows'))
        @(Test-CIPPCAGapMicrosoftGuidance -Context $Context) | Where-Object { $_.title -eq 'Token protection does not exempt devices that cannot support it' } | Should -Not -BeNullOrEmpty
    }

    It 'accepts an iOS and macOS policy as a supported platform scope and skips the Windows device checklist' {
        $Context = New-Context -RawPolicies @(New-TokenProtectionPolicy -Name 'CA209 iOS macOS token protection' -Platforms @('iOS', 'macOS') -DeviceFilterRule 'device.mdmAppId -ne "0000000a-0000-0000-c000-000000000000"')
        $Findings = @(Test-CIPPCAGapMicrosoftGuidance -Context $Context)
        @($Findings | Where-Object { $_.title -like 'Token protection*' }) | Should -BeNullOrEmpty
    }

    It 'flags a token protection policy that reaches Android or has no platform condition' {
        $Context = New-Context -RawPolicies @(
            New-TokenProtectionPolicy -Name 'No platform condition'
            New-TokenProtectionPolicy -Name 'Includes Android' -Platforms @('windows', 'android')
        )
        $Findings = @(@(Test-CIPPCAGapMicrosoftGuidance -Context $Context) | Where-Object { $_.title -eq 'Token protection is applied beyond the platforms and apps that support it' })
        $Findings.Count | Should -Be 2
        $Findings[0].description | Should -Match 'Windows, iOS and macOS'
    }

    It 'flags web browsers in scope on an Apple-only policy' {
        $Context = New-Context -RawPolicies @(New-TokenProtectionPolicy -Name 'CA209 iOS macOS token protection' -Platforms @('iOS', 'macOS') -ClientAppTypes @('browser', 'mobileAppsAndDesktopClients'))
        $Finding = @(Test-CIPPCAGapMicrosoftGuidance -Context $Context) | Where-Object { $_.title -eq 'Token protection is applied beyond the platforms and apps that support it' }
        $Finding | Should -Not -BeNullOrEmpty
        $Finding.description | Should -Match 'web browsers'
        $Finding.description | Should -Not -Match 'not limited to'
    }

    It 'treats Windows 365 as unsupported for an Apple-only policy but supported for a Windows one' {
        $Apps = @($script:Apps.exchangeOnline, $script:Apps.windows365)
        $Context = New-Context -RawPolicies @(
            New-TokenProtectionPolicy -Name 'Apple with W365' -Platforms @('iOS', 'macOS') -IncludeApplications $Apps -DeviceFilterRule 'x'
            New-TokenProtectionPolicy -Name 'Windows with W365' -Platforms @('windows') -IncludeApplications $Apps -DeviceFilterRule $script:WindowsDeviceFilter
        )
        $Findings = @(@(Test-CIPPCAGapMicrosoftGuidance -Context $Context) | Where-Object { $_.title -eq 'Token protection is applied to applications that do not support it' })
        $Findings.Count | Should -Be 1
        $Findings[0].affectedPolicies | Should -Be @('Apple with W365')
    }
}

Describe 'Get-CIPPCAPersonaMatrix admin coverage from All-users policies' {
    It 'counts an All-users legacy-auth block that only excludes a break-glass group as covering admins' {
        $Matrix = Get-CIPPCAPersonaMatrix -Context (New-Context -RawPolicies @(New-LegacyAuthBlockPolicy))
        (Get-AdminLegacyAuthCell $Matrix).state | Should -Be 'Enforced'
        @($Matrix.findings | Where-Object { $_.title -like 'Admins have no enforced policy for*' -and $_.title -like "*$($script:LegacyAuthLabel)*" }) | Should -BeNullOrEmpty
    }

    It 'keeps counting it when a non-privileged role such as Directory Synchronization Accounts is excluded' {
        $Matrix = Get-CIPPCAPersonaMatrix -Context (New-Context -RawPolicies @(New-LegacyAuthBlockPolicy -ExcludeRoles @($script:DirSyncRole)))
        (Get-AdminLegacyAuthCell $Matrix).state | Should -Be 'Enforced'
    }

    It 'stops counting it when a privileged role is excluded, whatever the casing of the role id' {
        $Matrix = Get-CIPPCAPersonaMatrix -Context (New-Context -RawPolicies @(New-LegacyAuthBlockPolicy -ExcludeRoles @($script:GlobalAdminRole.ToUpperInvariant())))
        (Get-AdminLegacyAuthCell $Matrix).state | Should -Be 'Missing'
    }
}
