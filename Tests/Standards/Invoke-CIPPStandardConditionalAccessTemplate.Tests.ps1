# Pester tests for Invoke-CIPPStandardConditionalAccessTemplate
# Covers how the standard resolves its template row out of the templates table:
# by RowKey, by the GUID column when the two have diverged, and the not-found path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardConditionalAccessTemplate.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardConditionalAccessTemplate.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict
    # parameter binding makes signature drift in the standard fail loudly here instead
    # of silently landing in $args and leaving the captured value $null.
    function Get-CIPPDbItem { [CmdletBinding()] param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Set-CIPPDBCacheConditionalAccessPolicies { [CmdletBinding()] param($TenantFilter) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type) }
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CippTable { [CmdletBinding()] param($tablename) }
    function Get-CippAzDataTableEntity { [CmdletBinding()] param($Table, $Filter) }
    function ConvertTo-CIPPODataFilterValue { [CmdletBinding()] param([AllowEmptyString()][string]$Value, $Type) $Value }
    function New-CIPPCAPolicy { [CmdletBinding()] param($replacePattern, $TenantFilter, $state, $RawJSON, $Overwrite, $APIName, $Headers, $DisableSD, $CreateGroups, $PreloadedCAPolicies, $PreloadedLocations, $PreloadedSecurityDefaults) }
    function New-CIPPCATemplate { [CmdletBinding()] param($TenantFilter, $JSON, $preloadedLocations) }
    function Compare-CIPPIntuneObject { [CmdletBinding()] param($ReferenceObject, $DifferenceObject, $CompareType) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $Tenant, [bool]$LicenseAvailable = $true) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CIPPTextReplacement { [CmdletBinding()] param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables declared
    # there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'
    # Shape mirrors a template produced by New-CIPPCATemplate from a live policy: the embedded
    # `id` is the source tenant's policy id and is never the key the standard looks up.
    $script:TemplateJson = '{"id":"a3b48aca-e723-469d-81f1-86e550dd7d48","displayName":"CA004: Require login from inside Netherlands","state":"disabled","conditions":{"users":{"includeUsers":["All"]}},"grantControls":{"operator":"OR","builtInControls":["block"]}}'
}

Describe 'Invoke-CIPPStandardConditionalAccessTemplate template resolution' {
    BeforeEach {
        $script:logs = @()
        $script:compareFields = @()
        $script:deployCalls = 0

        Mock -CommandName Get-CIPPDbItem -MockWith { [pscustomobject]@{ Timestamp = (Get-Date); DataCount = 5 } }
        Mock -CommandName Set-CIPPDBCacheConditionalAccessPolicies -MockWith { }
        Mock -CommandName New-CIPPDbRequest -MockWith { @() }
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Get-CippTable -MockWith { @{ Table = 'templates' } }
        Mock -CommandName New-CIPPCAPolicy -MockWith { $script:deployCalls++ }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev)
            $script:logs += @{ Message = $message; Sev = $sev }
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $Tenant, $LicenseAvailable)
            $script:compareFields += @{ Field = $FieldName; Current = $CurrentValue }
        }
    }

    It 'resolves the template when RowKey matches the stored TemplateList value' {
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            param($Table, $Filter)
            if ($Filter -match "RowKey eq 'template-guid'") {
                @([pscustomobject]@{ RowKey = 'template-guid'; GUID = 'template-guid'; JSON = $script:TemplateJson })
            }
        }

        $Settings = [pscustomobject]@{
            report       = $true
            TemplateList = [pscustomobject]@{ label = 'CA004: Require login from inside Netherlands'; value = 'template-guid' }
        }
        Invoke-CIPPStandardConditionalAccessTemplate -Tenant $script:Tenant -Settings $Settings

        $script:logs.Message | Should -Not -Contain "Conditional Access template 'CA004: Require login from inside Netherlands' (template-guid) could not be loaded from the template store - skipping."
        $script:compareFields[0].Current.Differences | Should -Be 'Policy is missing from this tenant.'
    }

    It 'resolves the template by the GUID column when it has diverged from RowKey' {
        # One query matches either key, so a row whose GUID and RowKey disagree still resolves.
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            param($Table, $Filter)
            if ($Filter -match "GUID eq 'template-guid'") {
                @([pscustomobject]@{ RowKey = 'a-different-rowkey'; GUID = 'template-guid'; JSON = $script:TemplateJson })
            }
        }

        $Settings = [pscustomobject]@{
            report       = $true
            TemplateList = [pscustomobject]@{ label = 'CA004: Require login from inside Netherlands'; value = 'template-guid' }
        }
        Invoke-CIPPStandardConditionalAccessTemplate -Tenant $script:Tenant -Settings $Settings

        ($script:logs | Where-Object { $_.Message -match 'could not be loaded from the template store' }) | Should -BeNullOrEmpty
        $script:compareFields[0].Current.Differences | Should -Be 'Policy is missing from this tenant.'
    }

    It 'resolves the template in a single query' {
        # Both keys are matched in one filter rather than a lookup and a fallback.
        $script:queries = @()
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            param($Table, $Filter)
            $script:queries += $Filter
            @([pscustomobject]@{ RowKey = 'template-guid'; GUID = 'template-guid'; JSON = $script:TemplateJson })
        }

        $Settings = [pscustomobject]@{
            report       = $true
            TemplateList = [pscustomobject]@{ label = 'CA004: Require login from inside Netherlands'; value = 'template-guid' }
        }
        Invoke-CIPPStandardConditionalAccessTemplate -Tenant $script:Tenant -Settings $Settings

        @($script:queries | Where-Object { $_ -match 'CATemplate' }).Count | Should -Be 1
        $script:queries[0] | Should -Match "RowKey eq 'template-guid' or GUID eq 'template-guid'"
    }

    It 'reports a clear error when neither key resolves a row' {
        Mock -CommandName Get-CippAzDataTableEntity -MockWith { }

        $Settings = [pscustomobject]@{
            report       = $true
            TemplateList = [pscustomobject]@{ label = 'CA004: Require login from inside Netherlands'; value = 'missing-guid' }
        }
        Invoke-CIPPStandardConditionalAccessTemplate -Tenant $script:Tenant -Settings $Settings

        ($script:logs | Where-Object { $_.Message -match 'could not be loaded from the template store' -and $_.Sev -eq 'Error' }) | Should -Not -BeNullOrEmpty
        $script:compareFields[0].Current.Differences | Should -Match 'no longer exists in the template library'
    }

    It 'does not attempt a deployment with a null template body' {
        Mock -CommandName Get-CippAzDataTableEntity -MockWith { }

        $Settings = [pscustomobject]@{
            remediate    = $true
            TemplateList = [pscustomobject]@{ label = 'CA004: Require login from inside Netherlands'; value = 'missing-guid' }
        }
        Invoke-CIPPStandardConditionalAccessTemplate -Tenant $script:Tenant -Settings $Settings

        $script:deployCalls | Should -Be 0
        ($script:logs | Where-Object { $_.Message -match 'Failed to create or update conditional access rule' }) | Should -BeNullOrEmpty
    }
}
