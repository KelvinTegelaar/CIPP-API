# Pester tests for the assignment half of Invoke-CIPPStandardDevicePrepProfile.
#
# The failure this guards is a half-deployed profile that can never heal: the compliance check
# compared settings only, and the /assign call existed only immediately after policy creation. A
# profile whose settings matched but whose assignment was missing short-circuited as "already
# correctly configured" on every run - the assignment was unreachable and drift could not even see
# it. The check has to read the assignment state, and remediation has to be able to repair the
# assignment without recreating the profile (which would sever the enrollment-time device group).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDevicePrepProfile.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDevicePrepProfile.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type) }
    function Get-CIPPIntunePolicyAssignments { [CmdletBinding()] param($PolicyId, $TemplateType, $TenantFilter, $ExistingPolicy) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, [bool]$LicenseAvailable = $true, [array]$BulkFields) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = [string]$Exception } }

    # The assignment helpers are pure apart from the group lookup, so use the real ones - the
    # Device Preparation target shape they produce is exactly what these tests exist to pin down.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignmentTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneAssignments.ps1')
    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AllUsersGroupId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'

    function New-ProfileSettings {
        param($AssignTo = 'AllDevicesAndUsers', [int]$Timeout = 60)
        [PSCustomObject]@{
            ProfileName        = 'TEST_PREP_PROFILE'
            ProfileDescription = 'Test profile'
            Timeout            = $Timeout
            CustomErrorMessage = 'Contact IT.'
            AllowSkip          = $false
            AllowDiagnostics   = $false
            AssignTo           = $AssignTo
            remediate          = $true
            report             = $true
            alert              = $false
        }
    }

    function New-ChoiceSetting {
        param($DefinitionId, $Value)
        [PSCustomObject]@{
            settingInstance = [PSCustomObject]@{
                settingDefinitionId = $DefinitionId
                choiceSettingValue  = [PSCustomObject]@{ value = "${DefinitionId}_$Value" }
            }
        }
    }

    function New-SimpleSetting {
        param($DefinitionId, $Value)
        [PSCustomObject]@{
            settingInstance = [PSCustomObject]@{
                settingDefinitionId = $DefinitionId
                simpleSettingValue  = [PSCustomObject]@{ value = $Value }
            }
        }
    }

    # The deployed policy, parsed back the way the standard reads it: settings identical to what
    # New-ProfileSettings requests, so only the assignment dimension varies per test.
    function New-PolicyDetail {
        [PSCustomObject]@{
            id       = 'policy-1'
            name     = 'TEST_PREP_PROFILE'
            settings = @(
                New-ChoiceSetting 'enrollment_autopilot_dpp_deploymentmode' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_deploymenttype' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_jointype' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_accountype' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_allowskip' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_allowdiagnostics' '0'
                New-SimpleSetting 'enrollment_autopilot_dpp_timeout' 60
                New-SimpleSetting 'enrollment_autopilot_dpp_customerrormessage' 'Contact IT.'
                New-SimpleSetting 'enrollment_autopilot_dpp_devicesecuritygroupids' ''
            )
        }
    }

    function New-AllUsersAssignment {
        [PSCustomObject]@{
            target = [PSCustomObject]@{
                '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
                groupId       = $script:AllUsersGroupId
            }
        }
    }
}

Describe 'Invoke-CIPPStandardDevicePrepProfile assignment handling' {
    BeforeEach {
        $script:CompareFields = @()
        $script:PostCalls = @()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*configurationPolicies' } -MockWith {
            @([PSCustomObject]@{ name = 'TEST_PREP_PROFILE'; id = 'policy-1' })
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*expand=settings*' } -MockWith { New-PolicyDetail }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            $script:PostCalls += @{ uri = $uri; type = $type; body = $body }
            [PSCustomObject]@{ id = 'new-policy-1' }
        }
        Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith { @() }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            $script:CompareFields += @{ Current = $CurrentValue; Expected = $ExpectedValue }
        }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
    }

    Context 'settings correct, assignment missing' {
        It 'repairs the assignment in place instead of recreating the profile' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            # One call: the /assign repair on the existing policy. No delete, no recreation.
            @($script:PostCalls).Count | Should -Be 1
            $script:PostCalls[0].uri | Should -BeLike "*configurationPolicies('policy-1')/assign"
            $script:PostCalls[0].type | Should -Be 'POST'
        }

        It 'assigns the All Users virtual group rather than the broad virtual targets' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            $script:PostCalls[0].body | Should -BeLike "*$($script:AllUsersGroupId)*"
            $script:PostCalls[0].body | Should -Not -BeLike '*allDevicesAssignmentTarget*'
            $script:PostCalls[0].body | Should -Not -BeLike '*allLicensedUsersAssignmentTarget*'
        }

        It 'reports the missing assignment so drift can surface it' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            $script:CompareFields[0].Current.isAssigned | Should -BeFalse
            $script:CompareFields[0].Expected.isAssigned | Should -BeTrue
            $script:CompareFields[0].Current.assignmentDifferences | Should -BeLike '*All Users*'
        }
    }

    Context 'settings correct, assignment correct' {
        BeforeEach {
            Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith { @(New-AllUsersAssignment) }
        }

        It 'makes no write calls at all' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            @($script:PostCalls).Count | Should -Be 0
        }

        It 'reports the profile as assigned' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            $script:CompareFields[0].Current.isAssigned | Should -BeTrue
            $script:CompareFields[0].Expected.isAssigned | Should -BeTrue
        }
    }

    Context 'assignment state cannot be read' {
        BeforeEach {
            Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith { throw 'Graph timeout' }
        }

        It 'treats unknown as not-a-deviation: no remediation, no isAssigned dimension' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings)

            @($script:PostCalls).Count | Should -Be 0
            $script:CompareFields[0].Current.PSObject.Properties.Name | Should -Not -Contain 'isAssigned'
            $script:CompareFields[0].Expected.PSObject.Properties.Name | Should -Not -Contain 'isAssigned'
        }
    }

    Context 'settings drifted' {
        It 'recreates the profile and assigns it with the group target' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -Timeout 20)

            # Delete, recreate, assign - in that order.
            @($script:PostCalls).Count | Should -Be 3
            $script:PostCalls[0].type | Should -Be 'DELETE'
            $script:PostCalls[1].uri | Should -BeLike '*configurationPolicies'
            $script:PostCalls[2].uri | Should -BeLike "*configurationPolicies('new-policy-1')/assign"
            $script:PostCalls[2].body | Should -BeLike "*$($script:AllUsersGroupId)*"
        }
    }

    Context "legacy 'AllDevices' selection" {
        It 'does not write a target Device Preparation cannot honour, and says why' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -AssignTo 'AllDevices')

            @($script:PostCalls | Where-Object { $_.uri -like '*assign' }).Count | Should -Be 0
            Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*cannot be assigned to All Devices*' }
        }
    }
}
