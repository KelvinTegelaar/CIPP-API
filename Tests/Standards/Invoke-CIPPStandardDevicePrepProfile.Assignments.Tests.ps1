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
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = [string]$Exception } }
    function Get-CIPPTable { [CmdletBinding()] param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { [CmdletBinding()] param($Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { [CmdletBinding()] param($Entity, [switch]$Force) }

    # The assignment helpers are pure apart from the group lookup, so use the real ones - the
    # Device Preparation target shape they produce is exactly what these tests exist to pin down.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignmentTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneAssignments.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPEnrollmentTimeDeviceMembershipTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPEnrollmentTimeDeviceMembershipTarget.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPEnrollmentTimeDeviceMembershipMarker.ps1')
    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AllUsersGroupId = 'acacacac-9df4-4c7d-9d50-4ef0226f57a9'

    function New-ProfileSettings {
        param($AssignTo = 'AllDevicesAndUsers', [int]$Timeout = 60, $DeviceGroupName)
        [PSCustomObject]@{
            ProfileName        = 'TEST_PREP_PROFILE'
            ProfileDescription = 'Test profile'
            DeviceGroupName    = $DeviceGroupName
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
        param($DeviceGroupId = '')
        [PSCustomObject]@{
            id       = 'policy-1'
            name     = 'TEST_PREP_PROFILE'
            settings = @(
                New-ChoiceSetting 'enrollment_autopilot_dpp_deploymentmode' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_deploymenttype' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_jointype' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_accountype' '1'
                New-ChoiceSetting 'enrollment_autopilot_dpp_allowskip' '0'
                New-ChoiceSetting 'enrollment_autopilot_dpp_allowdiagnostics' '0'
                New-SimpleSetting 'enrollment_autopilot_dpp_timeout' 60
                New-SimpleSetting 'enrollment_autopilot_dpp_customerrormessage' 'Contact IT.'
                New-SimpleSetting 'enrollment_autopilot_dpp_devicesecuritygroupids' $DeviceGroupId
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
        # Intune applies the enrollment-time device group through its own action, so the retrieve
        # is the only thing that says what is really applied. Default: nothing applied.
        $script:MembershipResult = [PSCustomObject]@{ enrollmentTimeDeviceMembershipTargets = @() }
        # The marker is what CIPP recorded when it last applied a group. Default: never applied.
        $script:Marker = $null
        $script:MarkerWrites = @()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*configurationPolicies' } -MockWith {
            @([PSCustomObject]@{ name = 'TEST_PREP_PROFILE'; id = 'policy-1' })
        }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*expand=settings*' } -MockWith { New-PolicyDetail -DeviceGroupId 'device-group-1' }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            $script:PostCalls += @{ uri = $uri; type = $type; body = $body }
            # The set action answers 200 with a validation verdict rather than failing outright.
            [PSCustomObject]@{ id = 'new-policy-1'; validationSucceeded = $true }
        }
        Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*retrieveEnrollmentTimeDeviceMembershipTarget' } -MockWith {
            if ($script:MembershipResult -is [string]) { throw $script:MembershipResult }
            $script:MembershipResult
        }
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:Marker }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:MarkerWrites += @($Entity) }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
        Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith { @() }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            $script:CompareFields += @{ Current = $CurrentValue; Expected = $ExpectedValue }
        }
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

    Context 'enrollment time device membership target' {
        BeforeEach {
            # Settings and assignment both correct, so only the device group can drift.
            Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith { @(New-AllUsersAssignment) }
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith {
                @([PSCustomObject]@{ id = 'device-group-1'; displayName = 'DEVICE_PREP_DEVICES' })
            }
        }

        It 'applies the group through the membership action, not the settings string alone' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:PostCalls).Count | Should -Be 1
            $script:PostCalls[0].uri | Should -BeLike "*configurationPolicies('policy-1')/setEnrollmentTimeDeviceMembershipTarget"
            $Body = $script:PostCalls[0].body | ConvertFrom-Json
            $Body.enrollmentTimeDeviceMembershipTargets[0].targetType | Should -Be 'staticSecurityGroup'
            $Body.enrollmentTimeDeviceMembershipTargets[0].targetId | Should -Be 'device-group-1'
        }

        It 'repairs it in place - recreating would destroy the profile over a group it can add' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:PostCalls | Where-Object { $_.type -eq 'DELETE' }).Count | Should -Be 0
        }

        It 'makes no write when the applied group already matches' {
            $script:MembershipResult = [PSCustomObject]@{
                enrollmentTimeDeviceMembershipTargets = @([PSCustomObject]@{ targetType = 'staticSecurityGroup'; targetId = 'device-group-1' })
            }

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:PostCalls).Count | Should -Be 0
            $script:CompareFields[0].Current.DeviceGroupId | Should -Be 'device-group-1'
        }

        It 'sets the membership target on the profile it recreates' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES' -Timeout 20)

            $Set = @($script:PostCalls | Where-Object { $_.uri -like '*setEnrollmentTimeDeviceMembershipTarget' })
            @($Set).Count | Should -Be 1
            $Set[0].uri | Should -BeLike "*configurationPolicies('new-policy-1')/*"
            ($Set[0].body | ConvertFrom-Json).enrollmentTimeDeviceMembershipTargets[0].targetId | Should -Be 'device-group-1'
        }

        It 'carries the @odata.type the action requires' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            ($script:PostCalls[0].body | ConvertFrom-Json).enrollmentTimeDeviceMembershipTargets[0].'@odata.type' |
                Should -Be 'microsoft.graph.enrollmentTimeDeviceMembershipTarget'
        }

        It 'fails loudly when Intune answers 200 but rejects the group' {
            # The action reports rejection in the body, so an unchecked call would look successful.
            Mock -CommandName New-GraphPOSTRequest -ParameterFilter { $uri -like '*setEnrollmentTimeDeviceMembershipTarget' } -MockWith {
                [PSCustomObject]@{ validationSucceeded = $false; enrollmentTimeDeviceMembershipTargetValidationStatuses = @([PSCustomObject]@{ validationStatus = 'groupNotFound' }) }
            }

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $message -like '*groupNotFound*' }
        }

        It 'lets the live action overrule a stale marker, so a portal change is repaired' {
            # The marker says the group is applied; the tenant says otherwise, and the tenant wins
            # wherever the action routes.
            $script:Marker = [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = 'policy-1'; GroupId = 'device-group-1' }

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            $script:CompareFields[0].Current.DeviceGroupId | Should -Be ''
            @($script:PostCalls).Count | Should -Be 1
            $script:PostCalls[0].uri | Should -BeLike '*setEnrollmentTimeDeviceMembershipTarget'
        }

        It 'falls back to the marker only where the action does not route' {
            $script:Marker = [PSCustomObject]@{ PartitionKey = $script:Tenant; RowKey = 'policy-1'; GroupId = 'device-group-1' }
            $script:MembershipResult = 'No OData route exists'

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:PostCalls).Count | Should -Be 0
            $script:CompareFields[0].Current.DeviceGroupId | Should -Be 'device-group-1'
        }

        It 'leaves the dimension out when the configured group does not exist and cannot be made' {
            # Nothing in CIPP can create it on this run, so asserting it would deviate forever.
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } -MockWith { @() }

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:PostCalls).Count | Should -Be 0
            $script:CompareFields[0].Current.PSObject.Properties.Name | Should -Not -Contain 'DeviceGroupId'
            $script:CompareFields[0].Expected.PSObject.Properties.Name | Should -Not -Contain 'DeviceGroupId'
            Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*No security group found*' }
        }

        It 'grades a profile with the setting string but no marker as half deployed, and repairs it' {
            # Every create writes the setting string whether or not the group was ever applied,
            # so the string must not be able to vouch for the profile.
            $script:MembershipResult = 'No OData route exists'

            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            $script:CompareFields[0].Current.DeviceGroupId | Should -Be ''
            @($script:PostCalls).Count | Should -Be 1
            $script:PostCalls[0].uri | Should -BeLike '*setEnrollmentTimeDeviceMembershipTarget'
        }

        It 'records what it applied so the next run can see it' {
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES')

            @($script:MarkerWrites).Count | Should -Be 1
            $script:MarkerWrites[0].PartitionKey | Should -Be $script:Tenant
            $script:MarkerWrites[0].RowKey | Should -Be 'policy-1'
            $script:MarkerWrites[0].GroupId | Should -Be 'device-group-1'
            $script:MarkerWrites[0].AppliedAt | Should -Not -BeNullOrEmpty
        }

        It 'forgets the marker when it deletes the policy for recreation' {
            # The recreated profile gets a new id, so a surviving marker would answer for a
            # policy that no longer exists.
            Invoke-CIPPStandardDevicePrepProfile -Tenant $script:Tenant -Settings (New-ProfileSettings -DeviceGroupName 'DEVICE_PREP_DEVICES' -Timeout 20)

            Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.PartitionKey -eq $script:Tenant -and $Entity.RowKey -eq 'policy-1'
            }
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

Describe 'Set-CIPPEnrollmentTimeDeviceMembershipTarget' {
    # A group created moments earlier is not replicated yet and the action rejects it as
    # securityGroupNotFound, so the first apply after a create fails for a reason that clears
    # itself. Anything else is a real rejection and must surface on the first answer.
    BeforeEach {
        $script:SetResults = @()
        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            $script:Attempt++
            $script:SetResults[[Math]::Min($script:Attempt - 1, $script:SetResults.Count - 1)]
        }
        $script:Attempt = 0
        $script:Rejection = [PSCustomObject]@{
            validationSucceeded                                    = $false
            enrollmentTimeDeviceMembershipTargetValidationStatuses = @([PSCustomObject]@{ targetValidationErrorCode = 'securityGroupNotFound' })
        }
    }

    It 'rides out the replication delay and succeeds' {
        $script:SetResults = @($script:Rejection, $script:Rejection, [PSCustomObject]@{ validationSucceeded = $true })

        { Set-CIPPEnrollmentTimeDeviceMembershipTarget -PolicyId 'policy-1' -GroupId 'device-group-1' -TenantFilter $script:Tenant } |
            Should -Not -Throw

        Should -Invoke New-GraphPOSTRequest -Times 3 -Exactly
    }

    It 'gives up and throws once the retries are exhausted' {
        $script:SetResults = @($script:Rejection)

        { Set-CIPPEnrollmentTimeDeviceMembershipTarget -PolicyId 'policy-1' -GroupId 'device-group-1' -TenantFilter $script:Tenant } |
            Should -Throw '*securityGroupNotFound*'

        Should -Invoke New-GraphPOSTRequest -Times 4 -Exactly
    }

    It 'does not retry a rejection that will not clear on its own' {
        $script:SetResults = @([PSCustomObject]@{
                validationSucceeded                                    = $false
                enrollmentTimeDeviceMembershipTargetValidationStatuses = @([PSCustomObject]@{ targetValidationErrorCode = 'targetTypeNotSupported' })
            })

        { Set-CIPPEnrollmentTimeDeviceMembershipTarget -PolicyId 'policy-1' -GroupId 'device-group-1' -TenantFilter $script:Tenant } |
            Should -Throw '*targetTypeNotSupported*'

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }
}

Describe 'Remove-CIPPEnrollmentTimeDeviceMembershipMarker' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
    }

    It 'asks for the 404 to be terminating so a missing row reaches the catch' {
        # The table module reports a missing row with a NON-terminating error, which would walk
        # straight past try/catch and surface on every recreation of an unmarked profile.
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }

        Remove-CIPPEnrollmentTimeDeviceMembershipMarker -PolicyId 'policy-1' -TenantFilter $script:Tenant

        Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It 'swallows a removal failure rather than failing the recreation' {
        Mock -CommandName Remove-AzDataTableEntity -MockWith { throw 'The specified entity does not exist' }

        { Remove-CIPPEnrollmentTimeDeviceMembershipMarker -PolicyId 'policy-1' -TenantFilter $script:Tenant } |
            Should -Not -Throw
    }
}
