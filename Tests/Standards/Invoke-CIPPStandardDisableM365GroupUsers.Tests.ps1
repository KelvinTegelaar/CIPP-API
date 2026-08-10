# Pester tests for Invoke-CIPPStandardDisableM365GroupUsers
#
# Covers the remediation paths that produced issue #205: the tenant with no Group.Unified
# directory setting (where /beta/settings is eventually consistent and a read-back returns
# nothing), a values collection missing the entry being set, and a partial read that must
# not be patched over the top of.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDisableM365GroupUsers.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableM365GroupUsers.ps1 under Modules/' }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift in the standard fail loudly here instead of silently
    # landing in $args.
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp, $NoAuthCheck, $skipTokenCache, $ComplexFilter, $CountOnly) }
    function New-GraphPostRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders, $contentType, $IgnoreErrors, $returnHeaders, $maxRetries) }
    function New-CIPPGroup { [CmdletBinding()] param($GroupObject, $TenantFilter, $APIName, $Headers) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Tenant2, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Add-CIPPBPAField { [CmdletBinding()] param($FieldName, $FieldValue, $StoreAs, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }
    function Get-CippException { [CmdletBinding()] param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $StandardPath

    # Script scope: Pester 5 evaluates the Describe body at discovery, so plain variables
    # declared there are not in scope inside It blocks or mocks at run time.
    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:TemplateId = '62375ab9-6b52-47ed-826b-58e47e0e304b'

    # The 15 names Microsoft ships on the Group.Unified template, verified against live Graph.
    $script:TemplateNames = @(
        'NewUnifiedGroupWritebackDefault', 'EnableMIPLabels', 'CustomBlockedWordsList',
        'EnableMSStandardBlockedWords', 'ClassificationDescriptions', 'DefaultClassification',
        'PrefixSuffixNamingRequirement', 'AllowGuestsToBeGroupOwner', 'AllowGuestsToAccessGroups',
        'GuestUsageGuidelinesUrl', 'GroupCreationAllowedGroupId', 'AllowToAddGuests',
        'UsageGuidelinesUrl', 'ClassificationList', 'EnableGroupCreation'
    )

    function script:New-TemplateResponse {
        $Values = foreach ($Name in $script:TemplateNames) {
            $Default = switch ($Name) {
                'NewUnifiedGroupWritebackDefault' { 'true' }
                'AllowGuestsToAccessGroups' { 'true' }
                'AllowToAddGuests' { 'true' }
                'EnableGroupCreation' { 'true' }
                default { '' }
            }
            [pscustomobject]@{ name = $Name; type = 'System.String'; defaultValue = $Default }
        }
        [pscustomobject]@{ id = $script:TemplateId; displayName = 'Group.Unified'; values = @($Values) }
    }

    # An existing tenant setting. Pass -Omit to drop entries, mirroring a setting created
    # from an older template revision.
    function script:New-SettingResponse {
        param([string[]]$Omit = @(), [string]$EnableGroupCreation = 'true', [string]$Id = '093005de-06c3-4f4f-ac7b-0c161abaab09')
        $Values = foreach ($Name in $script:TemplateNames) {
            if ($Omit -contains $Name) { continue }
            $Value = switch ($Name) {
                'EnableGroupCreation' { $EnableGroupCreation }
                'AllowGuestsToAccessGroups' { 'true' }
                'AllowToAddGuests' { 'true' }
                'NewUnifiedGroupWritebackDefault' { 'true' }
                default { '' }
            }
            [pscustomobject]@{ name = $Name; value = $Value }
        }
        [pscustomobject]@{ id = $Id; displayName = 'Group.Unified'; templateId = $script:TemplateId; values = @($Values) }
    }
}

Describe 'Invoke-CIPPStandardDisableM365GroupUsers remediation' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:posts = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith { }
        Mock -CommandName Add-CIPPBPAField -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
        Mock -CommandName New-GraphPostRequest -MockWith {
            param($uri, $tenantid, $body, $type, $AsApp, $contentType)
            $script:posts.Add(@{ Uri = $uri; Type = "$type"; Body = $body })
            # Mirror live Graph: the create POST returns the created object (displayName empty).
            if ("$type" -eq 'POST') {
                $Parsed = $body | ConvertFrom-Json
                return [pscustomobject]@{
                    id          = 'd7ca702d-3b44-41d5-8b85-52d8b2355ac5'
                    displayName = ''
                    templateId  = $Parsed.templateId
                    values      = @($Parsed.values)
                }
            }
            return $null
        }
    }

    Context 'tenant has no Group.Unified setting (issue #205)' {
        BeforeEach {
            # Live behaviour: /beta/settings returns nothing, and still returns nothing when
            # read straight back after the create.
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { return script:New-TemplateResponse }
                return @()
            }
        }

        It 'does not throw the reported "property value cannot be found" error' {
            { Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            $Failures = $script:logs | Where-Object { $_.Sev -eq 'Error' }
            $Failures | Should -BeNullOrEmpty -Because 'the create path should succeed, not log a failure'
        }

        It 'creates the setting with a single well-formed POST and no PATCH' {
            Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true }

            $Creates = @($script:posts | Where-Object { $_.Type -eq 'POST' })
            $Creates.Count | Should -Be 1
            # The old code built ".../settings/$($string.id)" which collapsed to a trailing slash.
            $Creates[0].Uri | Should -BeExactly 'https://graph.microsoft.com/beta/settings'
            $Creates[0].Uri | Should -Not -Match '/settings/$'

            @($script:posts | Where-Object { $_.Type -match 'patch' }).Count |
                Should -Be 0 -Because 'the setting is created already correct, so no follow-up patch is needed'
        }

        It 'sends templateId and the desired values, without read-only properties' {
            Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true }

            $Body = (@($script:posts | Where-Object { $_.Type -eq 'POST' })[0]).Body | ConvertFrom-Json
            $Body.templateId | Should -BeExactly $script:TemplateId
            @($Body.values).Count | Should -Be 15
            ($Body.values | Where-Object name -EQ 'EnableGroupCreation').value | Should -BeExactly 'false'
            $Body.PSObject.Properties.Name | Should -Not -Contain 'id'
            $Body.PSObject.Properties.Name | Should -Not -Contain 'displayName'
        }

        It 'falls back to the built-in template when the template endpoint fails' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { throw 'Graph is having a moment' }
                return @()
            }

            { Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            $Body = (@($script:posts | Where-Object { $_.Type -eq 'POST' })[0]).Body | ConvertFrom-Json
            @($Body.values).Count | Should -Be 15
            ($Body.values | Where-Object name -EQ 'EnableGroupCreation').value | Should -BeExactly 'false'
        }
    }

    Context 'existing setting' {
        BeforeEach {
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { return script:New-TemplateResponse }
                return @(script:New-SettingResponse)
            }
        }

        It 'patches a body that is valid JSON with values as an array' {
            Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true }

            $Patch = @($script:posts | Where-Object { $_.Type -match 'patch' })
            $Patch.Count | Should -Be 1
            # The old body was "{values : [...]}" - an unquoted key, so not strict JSON.
            $Patch[0].Body | Should -Not -Match '^\{values\s*:'
            $Parsed = $Patch[0].Body | ConvertFrom-Json
            $Parsed.values | Should -BeOfType [System.Object]
            @($Parsed.values).Count | Should -Be 15
            ($Parsed.values | Where-Object name -EQ 'EnableGroupCreation').value | Should -BeExactly 'false'
        }

        It 'leaves unrelated values untouched' {
            Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true }

            $Parsed = (@($script:posts | Where-Object { $_.Type -match 'patch' })[0]).Body | ConvertFrom-Json
            ($Parsed.values | Where-Object name -EQ 'AllowGuestsToAccessGroups').value | Should -BeExactly 'true'
            ($Parsed.values | Where-Object name -EQ 'AllowToAddGuests').value | Should -BeExactly 'true'
        }

        It 'adds EnableGroupCreation when the tenant setting does not have it' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { return script:New-TemplateResponse }
                return @(script:New-SettingResponse -Omit 'EnableGroupCreation')
            }

            { Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            $Parsed = (@($script:posts | Where-Object { $_.Type -match 'patch' })[0]).Body | ConvertFrom-Json
            ($Parsed.values | Where-Object name -EQ 'EnableGroupCreation').value | Should -BeExactly 'false'
        }

        It 'sets GroupCreationAllowedGroupId when an allowed group is configured' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { return script:New-TemplateResponse }
                if ($Uri -like '*/groups?*') { return @([pscustomobject]@{ id = 'aaaabbbb-cccc-dddd-eeee-ffff00001111'; displayName = 'Group Creators' }) }
                return @(script:New-SettingResponse)
            }

            Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true; AllowedGroupName = 'Group Creators' }

            $Parsed = (@($script:posts | Where-Object { $_.Type -match 'patch' })[0]).Body | ConvertFrom-Json
            ($Parsed.values | Where-Object name -EQ 'GroupCreationAllowedGroupId').value |
                Should -BeExactly 'aaaabbbb-cccc-dddd-eeee-ffff00001111'
            @($Parsed.values | Where-Object name -EQ 'GroupCreationAllowedGroupId').Count |
                Should -Be 1 -Because 'the entry must be replaced, not duplicated'
        }
    }

    Context 'partial read' {
        It 'refuses to patch when the setting comes back with no values' {
            Mock -CommandName New-GraphGetRequest -MockWith {
                param($Uri, $tenantid)
                if ($Uri -like '*directorySettingTemplates*') { return script:New-TemplateResponse }
                return @([pscustomobject]@{ id = '093005de-06c3-4f4f-ac7b-0c161abaab09'; displayName = 'Group.Unified'; values = @() })
            }

            { Invoke-CIPPStandardDisableM365GroupUsers -Tenant $script:Tenant -Settings @{ remediate = $true } } |
                Should -Not -Throw

            @($script:posts).Count |
                Should -Be 0 -Because 'patching a truncated values collection would wipe the other group settings'

            # The old code also issued no PATCH here, but only because it crashed on the null
            # assignment first. Assert it declined deliberately, with a diagnosable message.
            $Errors = @($script:logs | Where-Object { $_.Sev -eq 'Error' })
            $Errors.Count | Should -BeGreaterThan 0
            $Errors[0].Message | Should -Match 'came back incomplete'
            $Errors[0].Message | Should -Not -Match "property 'value' cannot be found"
        }
    }
}
