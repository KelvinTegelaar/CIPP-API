# Pester tests for Get-CIPPDrift
#
# Covers:
#   - The #6347 bug: raw .name comparison used to match $null -eq $null for policy types that have
#     no .name property at all, silently suppressing tenant-only Intune drift detection.
#   - A second regression discovered while validating the #6347 fix: collapsing template/tenant
#     names to a single "effective name" (preferring displayName) breaks matching for Settings
#     Catalog-style policies, whose templates always get a CIPP-forced .displayName but whose real
#     Graph identity (and the only property tenant policies of that type actually have) is .name.
#   - Conditional Access extra-policy matching (unaffected by either bug, used as a control).
#   - Standards-deviation display name/description resolution (Intune/CA/ReusableSettings/Quarantine).
#   - Stale tenantDrift row pruning, gated on whether the relevant Graph collection succeeded.
#
# Get-CIPPDrift talks to several CIPPCore/Az helpers; all are stubbed here and mocked per-scenario
# so the function under test can run standalone, following the convention in
# Tests/Alerts/Get-CIPPAlertIntunePolicyConflicts.Tests.ps1.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDrift.ps1'

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter, $TableName) }
    function Get-CIPPTenantAlignment { param($TenantFilter, $TemplateId) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force, $TableName) }
    function Remove-CIPPAzDataTableEntity { param($Entity, $TableName) }

    # Builds an IntuneTemplate row the way the templates table stores it: JSON is a wrapper object
    # (Displayname/Description/Type/RAWJson) where RAWJson is itself a JSON string of the captured
    # policy body. RawPolicy is a hashtable/PSCustomObject for the *actual* Graph-shaped body (the
    # thing that may or may not have .name / .displayName depending on policy type).
    function New-IntuneTemplateRow {
        param($RowKey, $DisplayName, $RawPolicy, $Description = 'desc', $Type = 'deviceCompliancePolicy', $Package)
        $Wrapper = @{
            Displayname = $DisplayName
            Description = $Description
            Type        = $Type
            RAWJson     = ($RawPolicy | ConvertTo-Json -Compress -Depth 10)
        }
        [pscustomobject]@{
            PartitionKey = 'IntuneTemplate'
            RowKey       = $RowKey
            Package      = $Package
            JSON         = ($Wrapper | ConvertTo-Json -Compress -Depth 10)
        }
    }

    function New-CATemplateRow {
        param($RowKey, $Policy, $Package)
        [pscustomobject]@{
            PartitionKey = 'CATemplate'
            RowKey       = $RowKey
            Package      = $Package
            JSON         = ($Policy | ConvertTo-Json -Compress -Depth 10)
        }
    }

    function New-DriftEntity {
        param($StandardName, $Status = 'New', $Reason = $null, $User = $null)
        [pscustomobject]@{
            StandardName = $StandardName
            Status       = $Status
            Reason       = $Reason
            User         = $User
        }
    }

    # NOTE: These two builders must live in this top-level BeforeAll (not directly inside a
    # Describe block) because Pester v5 only re-executes BeforeAll/It bodies during the Run
    # phase - plain `function` statements written directly in a Describe body only exist during
    # the Discovery phase and are gone by the time Mock -MockWith scriptblocks actually invoke them.
    function New-BaseAlignment {
        param($TemplateGuids)
        [pscustomobject]@{
            standardType         = 'drift'
            StandardName         = 'Test Standard'
            StandardId           = 'sid-1'
            AlignmentScore       = 100
            CompliantStandards   = 0
            ComparisonDetails    = @()
            LatestDataCollection = (Get-Date)
            standardSettings     = @{
                # Get-CIPPDrift iterates standardSettings.IntuneTemplate as an array and reads a
                # single TemplateList.value per entry - it is one entry per selected template, not
                # one entry with a comma-joined value.
                IntuneTemplate = @($TemplateGuids | ForEach-Object { @{ TemplateList = @{ value = $_ } } })
            }
        }
    }

    function New-CABaseAlignment {
        param($TemplateGuids)
        [pscustomobject]@{
            standardType         = 'drift'
            StandardName         = 'CA Standard'
            StandardId           = 'sid-2'
            AlignmentScore       = 100
            CompliantStandards   = 0
            ComparisonDetails    = @()
            LatestDataCollection = (Get-Date)
            standardSettings     = @{
                ConditionalAccessTemplate = @($TemplateGuids | ForEach-Object { @{ TemplateList = @{ value = $_ } } })
            }
        }
    }

    . $FunctionPath
}

Describe 'Get-CIPPDrift - Intune extra-policy matching (#6347 and Settings Catalog regression)' {
    BeforeEach {
        $script:IntuneCapable = $true
        $script:ConditionalAccessCapable = $false
        $script:IntuneTemplateRows = @()
        $script:CATemplateRows = @()
        $script:ReusableTemplateRows = @()
        $script:DriftEntityRows = @()
        $script:GraphResponses = @{}
        $script:AddedDriftEntities = [System.Collections.Generic.List[object]]::new()
        $script:RemovedDriftEntities = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Test-CIPPStandardLicense -MockWith {
            param($StandardName, $TenantFilter, $Preset)
            if ($Preset -eq 'Intune') { $script:IntuneCapable } else { $script:ConditionalAccessCapable }
        }
        Mock -CommandName Get-CippTable -MockWith { param($tablename) @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter, $TableName)
            switch -Wildcard ($Filter) {
                "*PartitionKey eq 'IntuneTemplate'*" { return @($script:IntuneTemplateRows) }
                "*PartitionKey eq 'CATemplate'*" { return @($script:CATemplateRows) }
                "*PartitionKey eq 'IntuneReusableSettingTemplate'*" { return @($script:ReusableTemplateRows) }
                default { return @($script:DriftEntityRows) }
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            foreach ($r in $Requests) {
                [pscustomobject]@{
                    id   = $r.id
                    body = @{ value = @($script:GraphResponses[$r.id]) }
                }
            }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Entity, [switch]$Force, $TableName)
            foreach ($e in @($Entity)) { $script:AddedDriftEntities.Add($e) }
        }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith {
            param($Entity, $TableName)
            $script:RemovedDriftEntities.Add($Entity)
        }
    }

    It 'does NOT match on the original null-eq-null bug (template and tenant both lack .name)' {
        # Both sides are of a displayName-only Graph type (e.g. compliance policy): the raw captured
        # body has no .name property at all, so it is $null on both sides. Names genuinely differ.
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Template A' -RawPolicy @{ id = 'tpl-1' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'Totally Different Policy' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 1
        $Result[0].currentDeviations[0].standardName | Should -Be 'IntuneTemplates.tenant-1'
        $Result[0].currentDeviations[0].standardDisplayName | Should -Be 'Intune - Totally Different Policy'
    }

    It 'matches on displayName-to-displayName when both sides have equal, non-null displayName' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Same Policy' -RawPolicy @{ id = 'tpl-1'; displayName = 'Same Policy' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'Same Policy' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'matches Settings Catalog policies on raw name-to-name even though the template also has a forced displayName' {
        # Settings Catalog (deviceManagement/configurationPolicies) templates get a CIPP-friendly
        # displayName forced onto them (Add-Member -Force) even though the underlying Graph object
        # only ever has .name. The tenant-side policy, captured straight from Graph, has ONLY .name.
        # A "collapsed effective name" comparison (prefer displayName if present) would compare the
        # CIPP-friendly template name against the raw tenant .name and never match - that was the
        # regression introduced by the first fix attempt for #6347.
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'My Settings Catalog Template' -Type 'configurationPolicy' -RawPolicy @{ id = 'tpl-1'; name = 'RawSettingsCatalogName123' })
        )
        $script:GraphResponses = @{
            'deviceManagement/configurationPolicies' = @(
                @{ id = 'tenant-1'; name = 'RawSettingsCatalogName123' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'matches on the displayName-to-name cross pairing' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Cross Match' -RawPolicy @{ id = 'tpl-1' })
        )
        $script:GraphResponses = @{
            'deviceManagement/configurationPolicies' = @(
                @{ id = 'tenant-1'; name = 'Cross Match' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'matches on the name-to-displayName cross pairing' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Some Friendly Name' -Type 'configurationPolicy' -RawPolicy @{ id = 'tpl-1'; name = 'Cross Match 2' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'Cross Match 2' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'reports a deviation when no pairing matches any template' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Template One' -RawPolicy @{ id = 'tpl-1'; name = 'template-one-raw' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'Unrelated Tenant Policy' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 1
        $Result[0].currentDeviations[0].expectedValue | Should -Match 'only exists in the tenant'
    }

    It 'matches a later template when earlier templates in the loop do not match' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Not It' -RawPolicy @{ id = 'tpl-1' })
            (New-IntuneTemplateRow -RowKey 'guid-2' -DisplayName 'This One' -RawPolicy @{ id = 'tpl-2' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'This One' }
            )
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1', 'guid-2')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'preserves an Accepted status across re-detection of the same extra policy' {
        $script:IntuneTemplateRows = @(
            (New-IntuneTemplateRow -RowKey 'guid-1' -DisplayName 'Template A' -RawPolicy @{ id = 'tpl-1' })
        )
        $script:GraphResponses = @{
            'deviceManagement/deviceCompliancePolicies' = @(
                @{ id = 'tenant-1'; displayName = 'Unrelated Tenant Policy' }
            )
        }
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'IntuneTemplates.tenant-1' -Status 'Accepted')
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-BaseAlignment -TemplateGuids @('guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
        $Result[0].acceptedDeviationsCount | Should -Be 1
        $Result[0].acceptedDeviations[0].Status | Should -Be 'Accepted'
    }
}

Describe 'Get-CIPPDrift - Conditional Access extra-policy matching' {
    BeforeEach {
        $script:IntuneCapable = $false
        $script:ConditionalAccessCapable = $true
        $script:IntuneTemplateRows = @()
        $script:CATemplateRows = @()
        $script:ReusableTemplateRows = @()
        $script:DriftEntityRows = @()
        $script:GraphResponses = @{}

        Mock -CommandName Test-CIPPStandardLicense -MockWith {
            param($StandardName, $TenantFilter, $Preset)
            if ($Preset -eq 'Intune') { $script:IntuneCapable } else { $script:ConditionalAccessCapable }
        }
        Mock -CommandName Get-CippTable -MockWith { param($tablename) @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter, $TableName)
            switch -Wildcard ($Filter) {
                "*PartitionKey eq 'IntuneTemplate'*" { return @($script:IntuneTemplateRows) }
                "*PartitionKey eq 'CATemplate'*" { return @($script:CATemplateRows) }
                "*PartitionKey eq 'IntuneReusableSettingTemplate'*" { return @($script:ReusableTemplateRows) }
                default { return @($script:DriftEntityRows) }
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            foreach ($r in $Requests) {
                [pscustomobject]@{ id = $r.id; body = @{ value = @($script:GraphResponses[$r.id]) } }
            }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { param($Entity, [switch]$Force, $TableName) }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($Entity, $TableName) }
    }

    It 'does not report a deviation when displayName matches exactly' {
        $script:CATemplateRows = @(New-CATemplateRow -RowKey 'ca-guid-1' -Policy @{ id = 'ca-tpl-1'; displayName = 'Block Legacy Auth' })
        $script:GraphResponses = @{ 'policies' = @(@{ id = 'ca-tenant-1'; displayName = 'Block Legacy Auth' }) }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-CABaseAlignment -TemplateGuids @('ca-guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
    }

    It 'reports a deviation with a Conditional Access label when displayName does not match any template' {
        $script:CATemplateRows = @(New-CATemplateRow -RowKey 'ca-guid-1' -Policy @{ id = 'ca-tpl-1'; displayName = 'Block Legacy Auth' })
        $script:GraphResponses = @{ 'policies' = @(@{ id = 'ca-tenant-1'; displayName = 'Some Other CA Policy' }) }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith { @(New-CABaseAlignment -TemplateGuids @('ca-guid-1')) }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 1
        $Result[0].currentDeviations[0].standardName | Should -Be 'ConditionalAccessTemplates.ca-tenant-1'
        $Result[0].currentDeviations[0].standardDisplayName | Should -Be 'Conditional Access - Some Other CA Policy'
    }
}

Describe 'Get-CIPPDrift - standards deviation display name resolution' {
    BeforeEach {
        $script:IntuneCapable = $false
        $script:ConditionalAccessCapable = $false
        $script:IntuneTemplateRows = @()
        $script:CATemplateRows = @()
        $script:ReusableTemplateRows = @()
        $script:DriftEntityRows = @()
        $script:GraphResponses = @{}

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
        Mock -CommandName Get-CippTable -MockWith { param($tablename) @{ TableName = $tablename } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter, $TableName)
            switch -Wildcard ($Filter) {
                "*PartitionKey eq 'IntuneTemplate'*" { return @($script:IntuneTemplateRows) }
                "*PartitionKey eq 'CATemplate'*" { return @($script:CATemplateRows) }
                "*PartitionKey eq 'IntuneReusableSettingTemplate'*" { return @($script:ReusableTemplateRows) }
                default { return @($script:DriftEntityRows) }
            }
        }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { param($Entity, [switch]$Force, $TableName) }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($Entity, $TableName) }
    }

    It 'resolves the Intune template display name and description for standards.IntuneTemplate deviations' {
        $script:IntuneTemplateRows = @(New-IntuneTemplateRow -RowKey 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -DisplayName 'Compliance Baseline' -Description 'Baseline description' -RawPolicy @{})
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-3'
                    AlignmentScore       = 90
                    CompliantStandards   = 1
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @(
                        [pscustomobject]@{
                            StandardName     = 'standards.IntuneTemplate.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.somesetting'
                            Compliant        = $false
                            StandardValue    = $true
                            ComplianceStatus = 'Non-Compliant'
                        }
                    )
                })
        }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Deviation = $Result[0].currentDeviations[0]
        $Deviation.standardDisplayName | Should -Be 'Compliance Baseline'
        $Deviation.standardDescription | Should -Be 'Baseline description'
    }

    It 'decodes the hex-encoded name for standards.QuarantineTemplate deviations' {
        $HexName = -join ([byte[]][System.Text.Encoding]::UTF8.GetBytes('Bad Policy') | ForEach-Object { $_.ToString('x2') })
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-4'
                    AlignmentScore       = 90
                    CompliantStandards   = 1
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @(
                        [pscustomobject]@{
                            StandardName     = "standards.QuarantineTemplate.$HexName"
                            Compliant        = $false
                            StandardValue    = $true
                            ComplianceStatus = 'Non-Compliant'
                        }
                    )
                })
        }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviations[0].standardDisplayName | Should -Be 'Quarantine Policy: Bad Policy'
    }

    It 'separates License Missing deviations into their own bucket, not currentDeviations' {
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-5'
                    AlignmentScore       = 90
                    CompliantStandards   = 1
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @(
                        [pscustomobject]@{
                            StandardName     = 'standards.SomeStandard'
                            Compliant        = $false
                            StandardValue    = $true
                            ComplianceStatus = 'License Missing'
                        }
                    )
                })
        }

        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result[0].currentDeviationsCount | Should -Be 0
        $Result[0].licenseMissingDeviationsCount | Should -Be 1
    }
}

Describe 'Get-CIPPDrift - stale drift entity pruning' {
    BeforeEach {
        $script:IntuneCapable = $false
        $script:ConditionalAccessCapable = $false
        $script:IntuneTemplateRows = @()
        $script:CATemplateRows = @()
        $script:ReusableTemplateRows = @()
        $script:DriftEntityRows = @()
        $script:GraphResponses = @{}
        $script:AddedDriftEntities = [System.Collections.Generic.List[object]]::new()
        $script:RemovedDriftEntities = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
        Mock -CommandName Get-CippTable -MockWith { param($tablename) @{ TableName = $tablename } }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter, $TableName)
            switch -Wildcard ($Filter) {
                "*PartitionKey eq 'IntuneTemplate'*" { return @($script:IntuneTemplateRows) }
                "*PartitionKey eq 'CATemplate'*" { return @($script:CATemplateRows) }
                "*PartitionKey eq 'IntuneReusableSettingTemplate'*" { return @($script:ReusableTemplateRows) }
                default { return @($script:DriftEntityRows) }
            }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Entity, [switch]$Force, $TableName)
            foreach ($e in @($Entity)) { $script:AddedDriftEntities.Add($e) }
        }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith {
            param($Entity, $TableName)
            $script:RemovedDriftEntities.Add($Entity)
        }
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-6'
                    AlignmentScore       = 100
                    CompliantStandards   = 0
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @()
                })
        }
    }

    It 'removes a stale plain standards drift row that no longer appears in the alignment' {
        # Undecided ('New') rows are the only standards-type rows eligible for pruning - decided
        # rows are protected (see the decided-row tests below), so the explicit Status matters here.
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'standards.LongGoneStandard' -Status 'New')

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 1
        $script:RemovedDriftEntities[0].StandardName | Should -Be 'standards.LongGoneStandard'
    }

    It 'does not remove a stale IntuneTemplates row when the Intune policy collection did not run' {
        # IntuneCapable is $false in this Describe block, so IntunePoliciesCollected never becomes
        # $true; a stale IntuneTemplates.* row must be protected from deletion in that case, since we
        # cannot prove the tenant policy is actually gone without a successful Graph collection.
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'IntuneTemplates.some-tenant-policy-id')

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
    }

    It 'does not remove a drift row that is still referenced by the current alignment' {
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'standards.StillRelevant')
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-7'
                    AlignmentScore       = 90
                    CompliantStandards   = 1
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @(
                        [pscustomobject]@{
                            StandardName     = 'standards.StillRelevant'
                            Compliant        = $true
                            StandardValue    = $true
                            ComplianceStatus = 'Compliant'
                        }
                    )
                })
        }

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
    }

    It 'keeps a decided (<Status>) standards row when its key disappears from the alignment' -TestCases @(
        @{ Status = 'Accepted' }
        @{ Status = 'Denied' }
        @{ Status = 'DeniedRemediate' }
        @{ Status = 'DeniedDelete' }
        @{ Status = 'CustomerSpecific' }
    ) {
        # Standards-type keys can transiently drop out of ComparisonDetails (package/tag membership
        # changes, template re-saves). A decided row is invisible to the alignment score once its key
        # is gone, so retaining it is harmless - deleting it destroys the user's decision and makes
        # the deviation reappear as 'New' on the next run (the reported bug).
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'standards.IntuneTemplate.pkg-row-1' -Status $Status -Reason 'kept' -User 'admin@msp.com')

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
        $script:AddedDriftEntities.Count | Should -Be 0
    }

    It 'prunes an undecided stale standards row even when Status is null' {
        # Statusless rows can only be ancient or hand-made (both writers always set Status); they
        # carry no user decision, so they are treated as undecided and remain prunable.
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'standards.NoStatus' -Status $null)

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 1
        $script:RemovedDriftEntities[0].StandardName | Should -Be 'standards.NoStatus'
    }

    It 'resumes the prior status when a dropped key returns' {
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'standards.TransientKey' -Status 'Accepted' -Reason 'known deviation' -User 'admin@msp.com')

        # Run 1: key absent from the alignment - the decided row must survive.
        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null
        $script:RemovedDriftEntities.Count | Should -Be 0

        # Run 2: key returns as non-compliant - the deviation must resume as Accepted, not New.
        # The table mock reads $script:DriftEntityRows at invocation time, so the surviving row is
        # still present, mimicking table persistence across runs.
        Mock -CommandName Get-CIPPTenantAlignment -MockWith {
            @([pscustomobject]@{
                    standardType         = 'drift'
                    StandardName         = 'Standard'
                    StandardId           = 'sid-8'
                    AlignmentScore       = 90
                    CompliantStandards   = 0
                    LatestDataCollection = (Get-Date)
                    ComparisonDetails    = @(
                        [pscustomobject]@{
                            StandardName     = 'standards.TransientKey'
                            Compliant        = $false
                            StandardValue    = $false
                            ComplianceStatus = 'Non-Compliant'
                        }
                    )
                })
        }
        $Result = Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com'

        $Result.acceptedDeviationsCount | Should -Be 1
        $Result.newDeviationsCount | Should -Be 0
        $Result.acceptedDeviations[0].Status | Should -Be 'Accepted'
        $script:AddedDriftEntities.Count | Should -Be 0
    }

    It 'does not prune IntuneTemplates rows when any Intune batch item failed' {
        # Graph $batch returns HTTP 200 even when individual sub-requests fail (e.g. 429 throttling
        # on one deviceManagement endpoint), so a partial collection must not count as evidence that
        # the missing policies are gone - otherwise decided extra-policy rows get wiped and reappear
        # as 'New' after the next healthy run (the reported bug for policies deployed outside the
        # drift template).
        Mock -CommandName Test-CIPPStandardLicense -MockWith { param($StandardName, $TenantFilter, $Preset) $Preset -eq 'Intune' }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            @(
                [pscustomobject]@{ id = 'deviceAppManagement/managedAppPolicies'; status = 200; body = @{ value = @() } }
                [pscustomobject]@{ id = 'deviceManagement/configurationPolicies'; status = 429; body = @{ error = @{ message = 'Too many requests' } } }
            )
        }
        $script:DriftEntityRows = @(
            New-DriftEntity -StandardName 'IntuneTemplates.gone-policy-new' -Status 'New'
            New-DriftEntity -StandardName 'IntuneTemplates.gone-policy-accepted' -Status 'Accepted'
        )

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
    }

    It 'removes stale New and Accepted IntuneTemplates rows when every Intune batch item succeeded' {
        # Policy rows count against the alignment score by existence, so a fully successful
        # collection that lacks the policy must prune the row regardless of Status - this is also
        # what clears a DeniedDelete row after its tenant policy is deleted.
        Mock -CommandName Test-CIPPStandardLicense -MockWith { param($StandardName, $TenantFilter, $Preset) $Preset -eq 'Intune' }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            foreach ($r in $Requests) {
                [pscustomobject]@{ id = $r.id; status = 200; body = @{ value = @() } }
            }
        }
        $script:DriftEntityRows = @(
            New-DriftEntity -StandardName 'IntuneTemplates.gone-policy-new' -Status 'New'
            New-DriftEntity -StandardName 'IntuneTemplates.gone-policy-accepted' -Status 'Accepted'
        )

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 2
        $script:RemovedDriftEntities.StandardName | Should -Contain 'IntuneTemplates.gone-policy-new'
        $script:RemovedDriftEntities.StandardName | Should -Contain 'IntuneTemplates.gone-policy-accepted'
    }

    It 'does not prune ConditionalAccessTemplates rows when the CA batch item failed' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { param($StandardName, $TenantFilter, $Preset) $Preset -eq 'Entra' }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            @([pscustomobject]@{ id = 'policies'; status = 429; body = @{ error = @{ message = 'Too many requests' } } })
        }
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'ConditionalAccessTemplates.gone-ca' -Status 'Accepted')

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
    }

    It 'removes a stale ConditionalAccessTemplates row when the CA collection succeeded' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { param($StandardName, $TenantFilter, $Preset) $Preset -eq 'Entra' }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            param($Requests, $tenantid, $asapp)
            @([pscustomobject]@{ id = 'policies'; status = 200; body = @{ value = @() } })
        }
        $script:DriftEntityRows = @(New-DriftEntity -StandardName 'ConditionalAccessTemplates.gone-ca' -Status 'Accepted')

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 1
        $script:RemovedDriftEntities[0].StandardName | Should -Be 'ConditionalAccessTemplates.gone-ca'
    }

    It 'does not prune any rows when the run is scoped to a single template' {
        # A template-scoped run only sees that template's keys in ValidDriftKeys; pruning would wipe
        # every other template's rows for the tenant.
        Mock -CommandName Test-CIPPStandardLicense -MockWith { param($StandardName, $TenantFilter, $Preset) $Preset -eq 'Intune' }
        $script:DriftEntityRows = @(
            New-DriftEntity -StandardName 'standards.OtherTemplateStandard' -Status 'New'
            New-DriftEntity -StandardName 'IntuneTemplates.other-policy' -Status 'New'
        )

        Get-CIPPDrift -TenantFilter 'contoso.onmicrosoft.com' -TemplateId 'drift-template-1' | Out-Null

        $script:RemovedDriftEntities.Count | Should -Be 0
    }
}
