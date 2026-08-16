# The second tranche of template families, all under the instance model. As with the first
# tranche, each family resolves its own partition and grades on its own terms; these tests
# pin the decisions that fail SILENTLY - a wrong cache, an ungraded direction, a compare
# that never fires - where the standard reports Compliant forever and nobody notices.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Convert-QuarantinePermissionsValue { [CmdletBinding()] param($InputObject) }
    function New-CIPPAssignmentFilter { param($FilterObject, $TenantFilter, $APIName) }
    function New-CIPPGroup { param($GroupObject, $TenantFilter, $APIName) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, $Select, $Compliance, $AsApp) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter) $Text }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function Set-CIPPQuarantinePolicy { param($identity, $action, $EndUserQuarantinePermissions, $ESNEnabled, $IncludeMessagesFromBlockedSenderAddress, $tenantFilter, $APIName) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    foreach ($Hook in @('AssignmentFilterTemplate', 'ReusableSettingsTemplate', 'GroupTemplate', 'ExchangeConnectorTemplate',
            'DeployContactTemplates', 'TenantAllowBlockListTemplate', 'QuarantineTemplate', 'SafeLinksTemplatePolicy')) {
        . (Join-Path $Baselines "Get-CIPPBaseline${Hook}State.ps1")
        . (Join-Path $Baselines "Invoke-CIPPBaseline${Hook}.ps1")
    }

    $script:Tenant = 'contoso.onmicrosoft.com'

    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }

    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
}

Describe 'Get-CIPPBaselineAssignmentFilterTemplateState' {
    BeforeAll {
        $script:AfItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ assignmentFilterTemplate = 'tpl-af' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'IntuneAssignmentFilters-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-af'; JSON = '{"displayName":"Corp Devices","description":"d","platform":"windows10AndLater","rule":"(device.model -eq \"X\")","assignmentFilterManagementType":"devices"}' } }
    }

    It 'is compliant when the filter matches on every graded field' {
        Mock New-CIPPDbRequest { @(@{ id = 'f1'; displayName = 'Corp Devices'; description = 'd'; platform = 'windows10AndLater'; rule = '(device.model -eq "X")'; assignmentFilterManagementType = 'devices' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineAssignmentFilterTemplateState -Item $script:AfItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports drift when the RULE differs, not just when the filter is missing' {
        # The classic aggregate compare could never see this - its Where-Object tested a
        # property against itself, so a deployed-but-wrong filter always read compliant.
        Mock New-CIPPDbRequest { @(@{ id = 'f1'; displayName = 'Corp Devices'; description = 'd'; platform = 'windows10AndLater'; rule = '(device.model -eq "Y")'; assignmentFilterManagementType = 'devices' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineAssignmentFilterTemplateState -Item $script:AfItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'grades a missing filter as one presence row, not one drift row per field' {
        Mock New-CIPPDbRequest { @(@{ id = 'f2'; displayName = 'Other' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineAssignmentFilterTemplateState -Item $script:AfItem -TenantFilter $script:Tenant
        $Prepared.Expected.PSObject.Properties.Name | Should -Be @('deployed')
        $Prepared.Current.deployed | Should -BeFalse
    }

    It 'patches only the fields that drifted' {
        Mock New-GraphPostRequest { }
        $Current = [PSCustomObject]@{
            deployed = $true; description = 'd'; platform = 'windows10AndLater'; rule = 'OLD'; assignmentFilterManagementType = 'devices'
            templateBody = [PSCustomObject]@{ displayName = 'Corp Devices'; description = 'd'; platform = 'windows10AndLater'; rule = 'NEW'; assignmentFilterManagementType = 'devices' }
            existingId = 'f1'
        }
        Invoke-CIPPBaselineAssignmentFilterTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PATCH' -and $body -match '"rule"' -and $body -notmatch '"platform"' }
    }

    It 'creates through the shared path when the filter is missing' {
        Mock New-CIPPAssignmentFilter { [PSCustomObject]@{ Success = $true } }
        $Current = [PSCustomObject]@{ deployed = $false; templateBody = [PSCustomObject]@{ displayName = 'Corp Devices' }; existingId = $null }
        Invoke-CIPPBaselineAssignmentFilterTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-CIPPAssignmentFilter -Times 1 -Exactly
    }
}

Describe 'Get-CIPPBaselineReusableSettingsTemplateState' {
    BeforeAll {
        $script:RsItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ reusableSettingsTemplate = 'tpl-rs' } }
        $script:RsBody = '{"displayName":"Cert Path","description":"d","settingDefinitionId":"def_1","settingInstance":{"settingDefinitionId":"def_1","simpleSettingValue":{"value":"C:\\pki"}}}'
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'IntuneReusableSettings-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-rs'; JSON = ('{"DisplayName":"Cert Path","RawJSON":' + ($script:RsBody | ConvertTo-Json) + '}') } }
    }

    It 'is compliant when the deployed setting matches, tolerating explicit nulls' {
        # The existing row carries explicit nulls the template omits - Graph does this
        # constantly - including one INSIDE the settingInstance tree. The comparer treats
        # null, empty and absent as equal, which is what keeps this from reading as
        # permanent drift; this fixture pins that tolerance.
        Mock New-CIPPDbRequest { @(@{ id = 'rs1'; displayName = 'Cert Path'; description = 'd'; settingDefinitionId = 'def_1'; applicableTo = $null; settingInstance = @{ settingDefinitionId = 'def_1'; settingInstanceTemplateReference = $null; simpleSettingValue = @{ value = 'C:\pki' } } } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineReusableSettingsTemplateState -Item $script:RsItem -TenantFilter $script:Tenant
        @($Prepared.Current.drift).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports drift when the setting value differs inside the settingInstance tree' {
        Mock New-CIPPDbRequest { @(@{ id = 'rs1'; displayName = 'Cert Path'; description = 'd'; settingDefinitionId = 'def_1'; settingInstance = @{ settingDefinitionId = 'def_1'; simpleSettingValue = @{ value = 'D:\other' } } } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineReusableSettingsTemplateState -Item $script:RsItem -TenantFilter $script:Tenant
        @($Prepared.Current.drift).Count | Should -BeGreaterThan 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports a missing setting as drift' {
        Mock New-CIPPDbRequest { @(@{ id = 'rs2'; displayName = 'Other' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineReusableSettingsTemplateState -Item $script:RsItem -TenantFilter $script:Tenant
        $Prepared.Current.deployed | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'PUTs over the existing object and POSTs a new one' {
        Mock New-GraphPostRequest { }
        Invoke-CIPPBaselineReusableSettingsTemplate -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ rawJSON = '{"a":1}'; existingId = 'rs1' })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PUT' -and $uri -match 'rs1' }
        Invoke-CIPPBaselineReusableSettingsTemplate -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ rawJSON = '{"a":1}'; existingId = $null })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
    }
}

Describe 'Get-CIPPBaselineGroupTemplateState' {
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'Groups-Count'; DataCount = 1 } }
    }

    It 'checks a dynamic distribution template against Exchange, never against Graph groups' {
        # A DDG lives in Exchange only. Checked against the Groups cache it would read
        # missing forever and be re-created on every remediation run.
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-g'; JSON = '{"displayName":"All Sales","groupType":"dynamicDistribution","membershipRules":"Department -eq ''Sales''"}' } }
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ExoDynamicDistributionGroup') { @(@{ Name = 'All Sales'; Identity = 'All Sales'; RecipientFilter = "Department -eq 'Sales'" } | ConvertTo-Cached) }
            else { @() }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ groupTemplate = 'tpl-g' } }
        (Get-CIPPBaselineGroupTemplateState -Item $Item -TenantFilter $script:Tenant).Current.deployed | Should -BeTrue
    }

    It 'checks every other group type against the Groups cache' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-g'; JSON = '{"displayName":"Sec Group","groupType":"security"}' } }
        Mock New-CIPPDbRequest {
            if ($Type -eq 'Groups') { @(@{ id = 'g1'; displayName = 'Sec Group' } | ConvertTo-Cached) } else { @() }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ groupTemplate = 'tpl-g' } }
        (Get-CIPPBaselineGroupTemplateState -Item $Item -TenantFilter $script:Tenant).Current.deployed | Should -BeTrue
    }

    It 'reports a missing group as drift' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-g'; JSON = '{"displayName":"Sec Group","groupType":"security"}' } }
        Mock New-CIPPDbRequest { @(@{ id = 'g2'; displayName = 'Other' } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ groupTemplate = 'tpl-g' } }
        $Prepared = Get-CIPPBaselineGroupTemplateState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }
}

Describe 'Get-CIPPBaselineExchangeConnectorTemplateState' {
    # The template's direction is a column on the ENTITY, not a field in its JSON, and it
    # picks the cache. An outbound template checked against the inbound cache reads missing
    # forever and gets re-created on every remediation run.
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoOutboundConnector-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-c'; direction = 'Outbound'; JSON = '{"name":"To Partner","SmartHosts":["mail.partner.com"]}' } }
    }

    It 'consults the cache matching the template direction' {
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ExoOutboundConnector') { @(@{ Identity = 'To Partner' } | ConvertTo-Cached) } else { @() }
        }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ exConnectorTemplate = 'tpl-c' } }
        (Get-CIPPBaselineExchangeConnectorTemplateState -Item $Item -TenantFilter $script:Tenant).Current.deployed | Should -BeTrue
    }

    It 'reports a missing connector as drift' {
        Mock New-CIPPDbRequest { @(@{ Identity = 'Different' } | ConvertTo-Cached) }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ exConnectorTemplate = 'tpl-c' } }
        $Prepared = Get-CIPPBaselineExchangeConnectorTemplateState -Item $Item -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports No Data when the entity has no usable direction' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-c'; JSON = '{"name":"To Partner"}' } }
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ exConnectorTemplate = 'tpl-c' } }
        (Get-CIPPBaselineExchangeConnectorTemplateState -Item $Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'rewrites via Set- with the tenant identity when deployed, New- otherwise' {
        Mock New-ExoRequest { }
        $Body = [PSCustomObject]@{ name = 'To Partner' }
        Invoke-CIPPBaselineExchangeConnectorTemplate -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ deployed = $true; connectorBody = $Body; direction = 'outbound'; existingIdentity = 'To Partner' })
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-outboundconnector' }
        Invoke-CIPPBaselineExchangeConnectorTemplate -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ deployed = $false; connectorBody = ([PSCustomObject]@{ name = 'To Partner' }); direction = 'outbound'; existingIdentity = '' })
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'New-outboundconnector' }
    }
}

Describe 'Get-CIPPBaselineDeployContactTemplatesState' {
    BeforeAll {
        $script:CtItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ contactTemplate = 'tpl-ct' } }
        $script:Deployed = @{ Identity = 'Support'; DisplayName = 'Support'; ExternalEmailAddress = 'support@partner.com'; MailTip = ''; HiddenFromAddressListsEnabled = $false; FirstName = ''; LastName = ''; Company = 'ACME'; StateOrProvince = ''; StreetAddress = ''; Phone = ''; WebPage = ''; Title = ''; City = ''; PostalCode = ''; CountryOrRegion = ''; MobilePhone = '' }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoMailContacts-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-ct'; JSON = '{"displayName":"Support","email":"Support@Partner.com","companyName":"ACME"}' } }
    }

    It 'compares email case-insensitively against the lowered cache value' {
        Mock New-CIPPDbRequest { @($script:Deployed | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineDeployContactTemplatesState -Item $script:CtItem -TenantFilter $script:Tenant
        @($Prepared.Current.drift).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'does not grade fields the template leaves empty' {
        # The tenant has a City the template never specified - grading it would strip
        # operator data on remediation.
        $WithCity = $script:Deployed.Clone(); $WithCity.City = 'Amsterdam'
        Mock New-CIPPDbRequest { @($WithCity | ConvertTo-Cached) }
        @((Get-CIPPBaselineDeployContactTemplatesState -Item $script:CtItem -TenantFilter $script:Tenant).Current.drift).Count | Should -Be 0
    }

    It 'grades hidefromGAL in BOTH directions, unlike the string fields' {
        # The tenant hides the contact but the template says visible: boolean fields are
        # enforced even when the template value is falsy.
        $Hidden = $script:Deployed.Clone(); $Hidden.HiddenFromAddressListsEnabled = $true
        Mock New-CIPPDbRequest { @($Hidden | ConvertTo-Cached) }
        (Get-CIPPBaselineDeployContactTemplatesState -Item $script:CtItem -TenantFilter $script:Tenant).Current.drift | Should -Contain 'hidefromGAL'
    }

    It 'reports drift when a specified field differs' {
        $Wrong = $script:Deployed.Clone(); $Wrong.Company = 'Umbrella'
        Mock New-CIPPDbRequest { @($Wrong | ConvertTo-Cached) }
        (Get-CIPPBaselineDeployContactTemplatesState -Item $script:CtItem -TenantFilter $script:Tenant).Current.drift | Should -Contain 'companyName'
    }

    It 'reports No Data for a template with an invalid email, and never deploys it' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-ct'; JSON = '{"displayName":"Support","email":"not-an-email"}' } }
        Mock New-CIPPDbRequest { @($script:Deployed | ConvertTo-Cached) }
        (Get-CIPPBaselineDeployContactTemplatesState -Item $script:CtItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineTenantAllowBlockListTemplateState' {
    BeforeAll {
        $script:TablItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ tenantAllowBlockListTemplate = 'tpl-tabl' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoTenantAllowBlockList-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-tabl'; JSON = '{"templateName":"Bad senders","listType":"Sender","listMethod":"Block","entries":"evil@bad.com, worse@bad.com","notes":"cipp"}' } }
    }

    It 'is additive: entries an operator added by hand are never drift' {
        Mock New-CIPPDbRequest { @(
                (@{ ListType = 'Sender'; Value = 'evil@bad.com' } | ConvertTo-Cached),
                (@{ ListType = 'Sender'; Value = 'worse@bad.com' } | ConvertTo-Cached),
                (@{ ListType = 'Sender'; Value = 'operator-added@other.com' } | ConvertTo-Cached)
            ) }
        $Prepared = Get-CIPPBaselineTenantAllowBlockListTemplateState -Item $script:TablItem -TenantFilter $script:Tenant
        @($Prepared.Current.missingEntries).Count | Should -Be 0
    }

    It 'only counts entries of the SAME list type as present' {
        # The same value on the Url list must not satisfy a Sender template.
        Mock New-CIPPDbRequest { @(@{ ListType = 'Url'; Value = 'evil@bad.com' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineTenantAllowBlockListTemplateState -Item $script:TablItem -TenantFilter $script:Tenant
        $Prepared.Current.missingEntries | Should -Contain 'evil@bad.com'
    }

    It 'submits only the missing entries, under the dynamic list-method switch' {
        Mock New-ExoRequest { }
        $Current = [PSCustomObject]@{
            missingEntries = @('worse@bad.com')
            templateBody   = [PSCustomObject]@{ templateName = 'Bad senders'; listType = 'Sender'; listMethod = 'Block'; notes = 'cipp'; NoExpiration = $true }
        }
        Invoke-CIPPBaselineTenantAllowBlockListTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdParams.Entries.Count -eq 1 -and $cmdParams.Entries[0] -eq 'worse@bad.com' -and $cmdParams.Block -eq $true -and $cmdParams.NoExpiration -eq $true
        }
    }

    It 'refuses an invalid list method rather than submitting a broken batch' {
        $Current = [PSCustomObject]@{
            missingEntries = @('x@y.com')
            templateBody   = [PSCustomObject]@{ templateName = 'T'; listType = 'Sender'; listMethod = 'Destroy' }
        }
        { Invoke-CIPPBaselineTenantAllowBlockListTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }
}

Describe 'Get-CIPPBaselineQuarantineTemplateState' {
    BeforeAll {
        $script:QItem = [PSCustomObject]@{
            Variables = [PSCustomObject]@{
                displayName = 'CIPP Quarantine'; ESNEnabled = $true; ReleaseAction = 'PermissionToRequestRelease'
                IncludeMessagesFromBlockedSenderAddress = $false
                PermissionToDelete = $true; PermissionToPreview = $true; PermissionToBlockSender = $false; PermissionToAllowSender = $false
            }
        }
        $script:QPolicy = @{ Name = 'CIPP Quarantine'; Guid = 'aaaa1111-0000-0000-0000-000000000001'; ESNEnabled = $true; IncludeMessagesFromBlockedSenderAddress = $false; EndUserQuarantinePermissions = 'encoded' }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoQuarantinePolicy-Count'; DataCount = 1 } }
        Mock Convert-QuarantinePermissionsValue { @{ PermissionToViewHeader = $false; PermissionToDownload = $false; PermissionToBlockSender = $false; PermissionToDelete = $true; PermissionToPreview = $true; PermissionToRelease = $false; PermissionToRequestRelease = $true; PermissionToAllowSender = $false } }
    }

    It 'is compliant when every graded field matches' {
        Mock New-CIPPDbRequest { @($script:QPolicy | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineQuarantineTemplateState -Item $script:QItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'catches two permissions swapped between keys, which the classic value-multiset compare could not' {
        Mock Convert-QuarantinePermissionsValue { @{ PermissionToViewHeader = $false; PermissionToDownload = $false; PermissionToBlockSender = $true; PermissionToDelete = $false; PermissionToPreview = $true; PermissionToRelease = $false; PermissionToRequestRelease = $true; PermissionToAllowSender = $false } }
        Mock New-CIPPDbRequest { @($script:QPolicy | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineQuarantineTemplateState -Item $script:QItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'never adopts a built-in policy: the all-zeros Guid is excluded' {
        $BuiltIn = $script:QPolicy.Clone(); $BuiltIn.Guid = '00000000-0000-0000-0000-000000000000'
        Mock New-CIPPDbRequest { @($BuiltIn | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineQuarantineTemplateState -Item $script:QItem -TenantFilter $script:Tenant
        $Prepared.Current.deployed | Should -BeFalse
    }

    It 'maps the release action to exactly one of the two release permissions on the write' {
        Mock Set-CIPPQuarantinePolicy { }
        $Remediate = [PSCustomObject]@{ esnEnabled = $true; releaseAction = 'PermissionToRelease'; includeMessagesFromBlockedSenderAddress = $false; permissionToDelete = $false; permissionToPreview = $false; permissionToBlockSender = $false; permissionToAllowSender = $false }
        Invoke-CIPPBaselineQuarantineTemplate -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ deployed = $false; policyName = 'CIPP Quarantine' })
        Should -Invoke Set-CIPPQuarantinePolicy -Times 1 -Exactly -ParameterFilter {
            $action -eq 'Create' -and $EndUserQuarantinePermissions.PermissionToRelease -eq $true -and $EndUserQuarantinePermissions.PermissionToRequestRelease -eq $false
        }
    }
}

Describe 'Get-CIPPBaselineSafeLinksTemplatePolicyState' {
    BeforeAll {
        $script:SlItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ safeLinksTemplate = 'tpl-sl' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoSafeLinksPolicies-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-sl'; JSON = '{"TemplateName":"Default SL","Name":"CIPP SafeLinks","EnableSafeLinksForEmail":true,"State":"Enabled"}' } }
    }

    It 'reports drift when the policy exists but its RULE is missing' {
        # A policy without a rule protects nobody. Grading the pair as one bool would let
        # the half-deployed state read compliant.
        Mock New-CIPPDbRequest {
            if ($Type -eq 'ExoSafeLinksPolicies') { @(@{ Name = 'CIPP SafeLinks' } | ConvertTo-Cached) } else { @() }
        }
        $Prepared = Get-CIPPBaselineSafeLinksTemplatePolicyState -Item $script:SlItem -TenantFilter $script:Tenant
        $Prepared.Current.policyDeployed | Should -BeTrue
        $Prepared.Current.ruleDeployed | Should -BeFalse
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'derives the rule name from the policy name when the template names none' {
        Mock New-CIPPDbRequest { @() }
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoSafeLinksPolicies-Count'; DataCount = 0 } }
        (Get-CIPPBaselineSafeLinksTemplatePolicyState -Item $script:SlItem -TenantFilter $script:Tenant).Current.ruleName | Should -Be 'CIPP SafeLinks_Rule'
    }

    It 'binds the rule to its policy only on create, never on update' {
        # SafeLinksPolicy is not a settable property on Set-SafeLinksRule - passing it
        # fails the whole write.
        Mock New-ExoRequest { }
        $Template = [PSCustomObject]@{ Name = 'CIPP SafeLinks'; EnableSafeLinksForEmail = $true }
        $Current = [PSCustomObject]@{ policyDeployed = $true; ruleDeployed = $true; templateBody = $Template; policyName = 'CIPP SafeLinks'; ruleName = 'CIPP SafeLinks_Rule' }
        Invoke-CIPPBaselineSafeLinksTemplatePolicy -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -ParameterFilter { $cmdlet -eq 'Set-SafeLinksRule' -and -not $cmdParams.ContainsKey('SafeLinksPolicy') }
        $Current2 = [PSCustomObject]@{ policyDeployed = $true; ruleDeployed = $false; templateBody = $Template; policyName = 'CIPP SafeLinks'; ruleName = 'CIPP SafeLinks_Rule' }
        Invoke-CIPPBaselineSafeLinksTemplatePolicy -Remediate $null -TenantFilter $script:Tenant -Current $Current2
        Should -Invoke New-ExoRequest -ParameterFilter { $cmdlet -eq 'New-SafeLinksRule' -and $cmdParams.SafeLinksPolicy -eq 'CIPP SafeLinks' }
    }

    It 'applies the rule state the template expresses' {
        Mock New-ExoRequest { }
        $Template = [PSCustomObject]@{ Name = 'CIPP SafeLinks'; State = 'Enabled' }
        $Current = [PSCustomObject]@{ policyDeployed = $true; ruleDeployed = $true; templateBody = $Template; policyName = 'CIPP SafeLinks'; ruleName = 'CIPP SafeLinks_Rule' }
        Invoke-CIPPBaselineSafeLinksTemplatePolicy -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Enable-SafeLinksRule' }
    }
}
