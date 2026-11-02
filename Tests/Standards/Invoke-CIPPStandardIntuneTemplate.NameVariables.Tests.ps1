# Pester tests for the %variable% handling in Invoke-CIPPStandardIntuneTemplate's identity columns.
#
# A template whose Displayname carries a tenant variable (e.g. %shortname%-WIN-COMP) is deployed
# under the resolved name, because Set-CIPPIntunePolicy forces the column value onto the payload for
# column-named types (Device, deviceCompliancePolicies, ...). The standard used to look the policy up
# under the raw, unresolved column value, so the match never hit: every remediate run treated the
# policy as missing and POSTed a fresh duplicate. Resolving the column once, up front, makes the
# lookup name, the compare identity and the created name the same resolved string, so a second run
# finds the policy it created and edits it in place.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardIntuneTemplate.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardIntuneTemplate.ps1 under Modules/' }

    # Stubs mirror the real signatures; strict binding makes signature drift fail loudly here.
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Filter) }
    function Repair-CIPPIntuneTemplateNesting { [CmdletBinding()] param($Template, $Table) }
    function Sync-CIPPReusablePolicySettings { [CmdletBinding()] param($TemplateInfo, $Tenant) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($Text, $TenantFilter, [switch]$EscapeForJson) }
    function Get-CIPPIntunePolicy { [CmdletBinding()] param($TemplateType, $DisplayName, $PolicyId, $Headers, $APINAME, $tenantFilter) }
    function Get-CIPPIntunePolicyAssignments { [CmdletBinding()] param($PolicyId, $TemplateType, $TenantFilter, $ExistingPolicy) }
    function Compare-CIPPIntuneAssignments { [CmdletBinding()] param($ExistingAssignments, $ExpectedAssignTo, $ExpectedCustomGroup, $ExpectedExcludeGroup, $ExpectedAssignmentFilter, $ExpectedAssignmentFilterType, $PolicyType, $TenantFilter) }
    function Select-CIPPIntuneAvailableSetting { [CmdletBinding()] param($Policy, $TenantFilter) }
    function Compare-CIPPIntuneObject { [CmdletBinding()] param($ReferenceObject, $DifferenceObject, $compareType) }
    function Set-CIPPIntunePolicy { [CmdletBinding()] param($TemplateType, $Description, $DisplayName, $RawJSON, $AssignTo, $ExcludeGroup, $Headers, $APIName, $TenantFilter, $AssignmentFilterName, $AssignmentFilterType, [array]$ReusableSettings, [int]$LevenshteinDistance, [string]$AssignmentMode) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, [bool]$LicenseAvailable = $true, [array]$BulkFields) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    # Real helpers - they are pure, and it is their exact rules the fix depends on:
    #   Get-CIPPIntunePolicyName returns the (now resolved) column value for column-named types;
    #   Merge-CIPPIntuneTemplateIdentity stamps that same value onto the compared payload;
    #   Get-CIPPIntuneAssignTarget decides whether the assignment is re-read.
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyName.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Merge-CIPPIntuneTemplateIdentity.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneAssignTarget.ps1')
    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:RawName = '%shortname%-WIN-COMP-Default-DG-PRD'
    $script:ResolvedName = 'CONTOSO-WIN-COMP-Default-DG-PRD'

    function New-TemplateSettings {
        [PSCustomObject]@{
            TemplateList      = [PSCustomObject]@{ value = 'tpl-1' }
            AssignTo          = 'On'
            customGroup       = $null
            verifyAssignments = $false
            remediate         = $true
            report            = $true
            alert             = $false
            templateId        = 'tpl-1'
        }
    }
}

Describe 'Invoke-CIPPStandardIntuneTemplate name variables' {
    BeforeEach {
        $script:LookupNames = @()
        $script:MergeNames = @()
        $script:SetNames = @()

        Mock -CommandName Get-CippTable -MockWith { @{ Table = 'templates' } }
        # A Device (column-named) template whose Displayname column holds a %variable%.
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @([PSCustomObject]@{
                    RowKey = 'tpl-1'
                    GUID   = 'tpl-1'
                    JSON   = '{"Displayname":"%shortname%-WIN-COMP-Default-DG-PRD","Description":"","Type":"Device","RAWJson":"{\"@odata.type\":\"#microsoft.graph.windows10GeneralConfiguration\",\"displayName\":\"%shortname%-WIN-COMP-Default-DG-PRD\"}"}'
                })
        }
        Mock -CommandName Repair-CIPPIntuneTemplateNesting -MockWith { $Template }
        Mock -CommandName Sync-CIPPReusablePolicySettings -MockWith { [PSCustomObject]@{} }
        # Resolve %shortname% the way the runtime helper does; honoured for RawJSON and for the columns.
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text -replace '%shortname%', 'CONTOSO' }
        Mock -CommandName Get-CIPPIntunePolicy -MockWith {
            $script:LookupNames += $DisplayName
            [PSCustomObject]@{ id = 'policy-1'; cippconfiguration = '{"displayName":"CONTOSO-WIN-COMP-Default-DG-PRD"}' }
        }
        Mock -CommandName Compare-CIPPIntuneObject -MockWith { $null }
        Mock -CommandName Set-CIPPIntunePolicy -MockWith {
            $script:SetNames += $DisplayName
            'Successfully edited policy'
        }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
    }

    It 'looks the policy up under the resolved name, not the raw %variable%' {
        Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

        $script:LookupNames | Should -Contain $script:ResolvedName
        $script:LookupNames | Should -Not -Contain $script:RawName
    }

    It 'creates/edits the policy under the resolved name, so the next run finds this policy' {
        Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

        $script:SetNames | Should -Contain $script:ResolvedName
        $script:SetNames | Should -Not -Contain $script:RawName
    }

    It 'uses the same resolved name for the lookup and the deployment - they must agree to converge' {
        Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

        # This is the property that ends the duplicate loop: what was searched for is what gets
        # written, so a second run's exact-name lookup matches and edits in place.
        ($script:SetNames | Select-Object -Unique) | Should -Be ($script:LookupNames | Select-Object -Unique)
    }

    It 'compares against the resolved identity, so a rename does not read as permanent drift' {
        Mock -CommandName Merge-CIPPIntuneTemplateIdentity -MockWith {
            $script:MergeNames += $DisplayName
            $Policy
        }

        Invoke-CIPPStandardIntuneTemplate -Tenant $script:Tenant -Settings (New-TemplateSettings)

        $script:MergeNames | Should -Contain $script:ResolvedName
        $script:MergeNames | Should -Not -Contain $script:RawName
    }
}
