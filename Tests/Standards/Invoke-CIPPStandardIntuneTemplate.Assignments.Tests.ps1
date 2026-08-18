# Pester tests for the assignment half of Invoke-CIPPStandardIntuneTemplate's remediation.
#
# Remediation used to stamp AssignmentsMatch = $true without reading anything back. Combined with
# the compliant-template skip in Push-CIPPStandardsList, which drops a standard from later runs
# while its cached result says compliant, that turned an assignment that never matched into a green
# tick lasting until something unrelated changed in the tenant - and a deviation that then
# reappeared for no visible reason. The remediation result has to come from a re-read.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardIntuneTemplate.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardIntuneTemplate.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here.
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Filter) }
    function Repair-CIPPIntuneTemplateNesting { [CmdletBinding()] param($Template, $Table) }
    function Sync-CIPPReusablePolicySettings { [CmdletBinding()] param($TemplateInfo, $Tenant) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($Text, $TenantFilter, [switch]$EscapeForJson) }
    function Get-CIPPIntunePolicyName { [CmdletBinding()] param($TemplateType, $RawJSON, $DisplayName) }
    function Get-CIPPIntunePolicy { [CmdletBinding()] param($TemplateType, $DisplayName, $PolicyId, $Headers, $APINAME, $tenantFilter) }
    function Get-CIPPIntunePolicyAssignments { [CmdletBinding()] param($PolicyId, $TemplateType, $TenantFilter, $ExistingPolicy) }
    function Compare-CIPPIntuneAssignments { [CmdletBinding()] param($ExistingAssignments, $ExpectedAssignTo, $ExpectedCustomGroup, $ExpectedExcludeGroup, $ExpectedAssignmentFilter, $ExpectedAssignmentFilterType, $PolicyType, $TenantFilter) }
    function Merge-CIPPIntuneTemplateIdentity { [CmdletBinding()] param($Policy, $TemplateType, $DisplayName, $Description) }
    function Select-CIPPIntuneAvailableSetting { [CmdletBinding()] param($Policy, $TenantFilter) }
    function Compare-CIPPIntuneObject { [CmdletBinding()] param($ReferenceObject, $DifferenceObject, $compareType) }
    function Set-CIPPIntunePolicy { [CmdletBinding()] param($TemplateType, $Description, $DisplayName, $RawJSON, $AssignTo, $ExcludeGroup, $Headers, $APIName, $TenantFilter, $AssignmentFilterName, $AssignmentFilterType, [array]$ReusableSettings, [int]$LevenshteinDistance, [string]$AssignmentMode) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, [bool]$LicenseAvailable = $true, [array]$BulkFields) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    # The assignment intent helper is pure, so use the real one - its Applied/Managed semantics are
    # exactly what decides whether the standard re-reads at all.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'

    function New-TemplateSettings {
        param($AssignTo = 'customGroup', $CustomGroup = 'Sales Users', $VerifyAssignments = $true)
        [PSCustomObject]@{
            TemplateList      = [PSCustomObject]@{ value = 'tpl-1' }
            AssignTo          = $AssignTo
            customGroup       = $CustomGroup
            verifyAssignments = $VerifyAssignments
            remediate         = $true
            report            = $true
            alert             = $false
            templateId        = 'tpl-1'
        }
    }

    function New-AssignmentVerdict {
        param([bool]$Matched, [bool]$Unknown, $Reasons = @())
        [PSCustomObject]@{
            Matched = if ($Unknown) { $null } else { $Matched }
            Unknown = $Unknown
            Reasons = @($Reasons)
        }
    }
}

Describe 'Invoke-CIPPStandardIntuneTemplate assignment remediation' {
    BeforeEach {
        $script:CompareFields = @()
        $script:AssignmentReads = 0

        Mock -CommandName Get-CippTable -MockWith { @{ Table = 'templates' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([PSCustomObject]@{
                    RowKey = 'tpl-1'
                    JSON   = '{"Displayname":"iOS Restrictions","Description":"","Type":"Device","RAWJson":"{\"@odata.type\":\"#microsoft.graph.iosGeneralDeviceConfiguration\"}"}'
                })
        }
        Mock -CommandName Repair-CIPPIntuneTemplateNesting -MockWith { $Template }
        Mock -CommandName Sync-CIPPReusablePolicySettings -MockWith { [PSCustomObject]@{} }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName Get-CIPPIntunePolicyName -MockWith { 'iOS Restrictions' }
        Mock -CommandName Get-CIPPIntunePolicy -MockWith {
            [PSCustomObject]@{ id = 'policy-1'; cippconfiguration = '{"displayName":"iOS Restrictions"}' }
        }
        Mock -CommandName Get-CIPPIntunePolicyAssignments -MockWith {
            $script:AssignmentReads++
            @()
        }
        Mock -CommandName Merge-CIPPIntuneTemplateIdentity -MockWith { $Policy }
        # No difference in the policy body, so isCompliant isolates from isAssigned.
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { $null }
        Mock -CommandName Set-CIPPIntunePolicy -MockWith { 'Successfully edited policy' }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            $script:CompareFields += @{ Current = $CurrentValue; Expected = $ExpectedValue }
        }
    }

    Context 'when remediation manages the assignment' {
        It 'reads the assignments back instead of asserting they are correct' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $false -Reasons @('Not assigned to expected group(s): Sales Users') }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            # Once before remediation, once after. Asserting would have read only once.
            $script:AssignmentReads | Should -Be 2
            Should -Invoke Compare-CIPPIntuneAssignments -Times 2 -Exactly
        }

        It 'reports the policy as unassigned when the re-read still does not match' {
            # This is the regression: the old code recorded isAssigned = $true here.
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $false -Reasons @('Not assigned to expected group(s): Sales Users') }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            $script:CompareFields[0].Current.isAssigned | Should -BeFalse
            $script:CompareFields[0].Expected.isAssigned | Should -BeTrue
            $script:CompareFields[0].Current.assignmentDifferences | Should -BeLike '*Sales Users*'
        }

        It 'reports the policy as assigned when the re-read matches' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $true }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            $script:CompareFields[0].Current.isAssigned | Should -BeTrue
            $script:CompareFields[0].Current.Keys | Should -Not -Contain 'assignmentDifferences'
        }

        It 'leaves the assignment unjudged when the re-read cannot be completed' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Unknown $true }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            # Neither compliant nor a deviation: the next report run reads them again.
            $script:CompareFields[0].Current.Keys | Should -Not -Contain 'isAssigned'
            $script:CompareFields[0].Expected.Keys | Should -Not -Contain 'isAssigned'
        }

        It 'passes replace mode so the exact-set check is satisfiable' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $true }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            Should -Invoke Set-CIPPIntunePolicy -Times 1 -Exactly -ParameterFilter { $AssignmentMode -eq 'replace' }
        }
    }

    Context 'when the assignment call fails' {
        It 'does not record the policy as assigned' {
            # Set-CIPPAssignedPolicy now throws, so Set-CIPPIntunePolicy rethrows and the standard's
            # catch runs. The pre-remediation verdict has to survive rather than becoming $true.
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $false -Reasons @('Not assigned to expected group(s): Sales Users') }
            Mock -CommandName Set-CIPPIntunePolicy -MockWith { throw 'Failed to assign Sales Users to Policy policy-1' }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            $script:CompareFields[0].Current.isAssigned | Should -BeFalse
            # The failed run must not re-read either; there is nothing new to read.
            $script:AssignmentReads | Should -Be 1
        }

        It 'logs the failure' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $false }
            Mock -CommandName Set-CIPPIntunePolicy -MockWith { throw 'Failed to assign Sales Users to Policy policy-1' }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

            Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $message -like '*Failed to create or update Intune Template*' }
        }
    }

    Context 'when the standard names no assignment target' {
        It 'does not re-read, because remediation never touched the assignments' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $true }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings -AssignTo $null -CustomGroup $null)

            $script:AssignmentReads | Should -Be 1
            $script:CompareFields[0].Current.isAssigned | Should -BeTrue
        }

        It 'does not ask for replace mode, which would wipe assignments it does not own' {
            Mock -CommandName Compare-CIPPIntuneAssignments -MockWith { New-AssignmentVerdict -Matched $true }

            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings -AssignTo 'On' -CustomGroup $null)

            Should -Invoke Set-CIPPIntunePolicy -Times 1 -Exactly -ParameterFilter { $AssignmentMode -ne 'replace' }
        }
    }

    Context 'when assignment verification is switched off' {
        It 'does not read assignments and does not report on them' {
            Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings -VerifyAssignments $false)

            $script:AssignmentReads | Should -Be 0
            $script:CompareFields[0].Current.Keys | Should -Not -Contain 'isAssigned'
        }
    }
}
