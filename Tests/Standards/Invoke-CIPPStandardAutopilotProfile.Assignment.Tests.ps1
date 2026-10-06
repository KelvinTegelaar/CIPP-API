# Pester tests for the assignment half of Invoke-CIPPStandardAutopilotProfile: the AssignTo mode
# (with the legacy AssignToAllDevices fallback), group name resolution, assignment drift and the
# reconcile call into Set-CIPPDefaultAPDeploymentProfile.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardAutopilotProfile.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardAutopilotProfile.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function Set-CIPPDefaultAPDeploymentProfile { [CmdletBinding()] param($TenantFilter, $DisplayName, $Description, $DeviceNameTemplate, $AllowWhiteGlove, $CollectHash, $UserType, $DeploymentMode, $HideChangeAccount, $AssignTo, $GroupIds, $ExcludeGroupIds, [switch]$Reconcile, $HidePrivacy, $HideTerms, $AutoKeyboard, $Headers, $Language, $APIName) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $headers, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = [string]$Exception } }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'

    function New-APSetting {
        param([hashtable]$Extra = @{})
        $Settings = [ordered]@{
            DisplayName        = 'AP Test'
            Description        = 'd'
            DeviceNameTemplate = 'CIPP-%RAND:5%'
            CollectHash        = $true
            SelfDeployingMode  = $false
            HideTerms          = $true
            HidePrivacy        = $true
            NotLocalAdmin      = $true
            AllowWhiteGlove    = $true
            AutoKeyboard       = $true
            remediate          = $true
            report             = $true
            alert              = $false
        }
        foreach ($Key in $Extra.Keys) { $Settings[$Key] = $Extra[$Key] }
        [PSCustomObject]$Settings
    }

    function New-Assignment {
        param($Type, $GroupId)
        [PSCustomObject]@{ id = "a-$Type-$GroupId"; target = [PSCustomObject]@{ '@odata.type' = "#microsoft.graph.$Type"; groupId = $GroupId } }
    }
}

Describe 'Invoke-CIPPStandardAutopilotProfile assignments' {
    BeforeEach {
        $script:Assignments = @()
        $script:Compare = $null
        Mock Test-CIPPStandardLicense { $true }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*windowsAutopilotDeploymentProfiles' } -MockWith {
            [PSCustomObject]@{
                id                            = 'profile-1'
                displayName                   = 'AP Test'
                description                   = 'd'
                deviceNameTemplate            = 'CIPP-%RAND:5%'
                locale                        = $null
                preprovisioningAllowed        = $true
                hardwareHashExtractionEnabled = $true
                outOfBoxExperienceSetting     = [PSCustomObject]@{
                    deviceUsageType              = 'singleUser'
                    privacySettingsHidden        = $true
                    eulaHidden                   = $true
                    userType                     = 'standard'
                    keyboardSelectionPageSkipped = $true
                }
            }
        }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*profile-1/assignments' } -MockWith { $script:Assignments }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/groups*' } -MockWith {
            @(
                [PSCustomObject]@{ id = 'g-dev'; displayName = 'AP Devices' }
                [PSCustomObject]@{ id = 'g-ex'; displayName = 'AP Excluded' }
                [PSCustomObject]@{ id = 'g-other'; displayName = 'Other' }
            )
        }
        Mock Set-CIPPDefaultAPDeploymentProfile { }
        Mock Set-CIPPStandardsCompareField { $script:Compare = @{ Current = $CurrentValue; Expected = $ExpectedValue } }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
    }

    It 'treats legacy AssignToAllDevices settings on an all-devices profile as compliant' {
        $script:Assignments = @(New-Assignment 'allDevicesAssignmentTarget')

        Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings (New-APSetting @{ AssignToAllDevices = $true })

        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 0
        $script:Compare.Expected.assignments.allDevices | Should -BeTrue
        $script:Compare.Current.assignments.allDevices | Should -BeTrue
    }

    It 'leaves manual group assignments alone under legacy settings with the switch off' {
        $script:Assignments = @(New-Assignment 'groupAssignmentTarget' 'g-other'; New-Assignment 'exclusionGroupAssignmentTarget' 'g-ex')

        Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings (New-APSetting @{ AssignToAllDevices = $false; DeviceNameTemplate = 'drifted' })

        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly -ParameterFilter { -not $Reconcile -and $AssignTo -eq $false }
        $script:Compare.Expected.assignments.includeGroups | Should -Be @('g-other')
    }

    It 'flags an all-devices profile in custom group mode and reconciles to the resolved group' {
        $script:Assignments = @(New-Assignment 'allDevicesAssignmentTarget')

        Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings (New-APSetting @{ AssignTo = 'customGroup'; customGroup = 'AP Dev*' })

        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly -ParameterFilter {
            $AssignTo -eq $false -and $Reconcile -and (@($GroupIds) -join ',') -eq 'g-dev' -and @($ExcludeGroupIds).Count -eq 0
        }
        $script:Compare.Expected.assignments.includeGroups | Should -Be @('AP Devices (g-dev)')
        $script:Compare.Current.assignments.allDevices | Should -BeTrue
    }

    It 'resolves and compares exclude groups' {
        $script:Assignments = @(New-Assignment 'allDevicesAssignmentTarget')
        $Settings = New-APSetting @{ AssignTo = 'allDevices'; excludeGroup = 'AP Excl*' }

        Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings $Settings

        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly -ParameterFilter {
            $AssignTo -eq $true -and $Reconcile -and (@($ExcludeGroupIds) -join ',') -eq 'g-ex'
        }
        $script:Compare.Expected.assignments.excludeGroups | Should -Be @('AP Excluded (g-ex)')

        $script:Assignments = @(New-Assignment 'allDevicesAssignmentTarget'; New-Assignment 'exclusionGroupAssignmentTarget' 'g-ex')
        Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings $Settings
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly
    }

    It 'warns instead of throwing when no custom group resolves, and does not reconcile' {
        $script:Assignments = @(New-Assignment 'groupAssignmentTarget' 'g-other')

        { Invoke-CIPPStandardAutopilotProfile -Tenant $script:Tenant -Settings (New-APSetting @{ AssignTo = 'customGroup'; customGroup = 'Nope' }) } | Should -Not -Throw

        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*Nope*' }
        Should -Invoke Set-CIPPDefaultAPDeploymentProfile -Times 1 -Exactly -ParameterFilter { -not $Reconcile -and @($GroupIds).Count -eq 0 }
    }
}
