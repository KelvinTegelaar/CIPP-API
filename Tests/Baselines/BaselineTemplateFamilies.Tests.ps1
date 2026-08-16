# The template families under the instance model: the baseline stores one instance per
# selected template (multiple + instanceIdentity), so every hook resolves ONE reference.
# Each family still resolves its own templates from its own PartitionKey and grades on its
# own terms, and that is not stylistic: three of the eleven template families store rows
# under a partition whose name does NOT match the standard name ('ExConnectorTemplate',
# 'ContactTemplate', 'IntuneReusableSettingTemplate'). A shared resolver keyed on the
# standard name finds nothing, reports every template missing, and remediation then deploys
# duplicates. These tests pin the per-family behaviour a shared helper would erase.
#
# Fixtures go through ConvertFrom-Json on purpose: that is how New-CIPPDbRequest returns
# cached rows, and a PowerShell literal would carry Int32 where production carries Int64.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    # The real one is [CmdletBinding()], which is what lets the hook pass -ErrorAction Stop.
    function Compare-CIPPSensitiveInfoType { [CmdletBinding()] param($TenantFilter, $Template) }
    function Set-CIPPSensitivityLabel { param($TenantFilter, $Template, $APIName, $Headers) }
    function Set-CIPPRetentionCompliancePolicy { param($TenantFilter, $Template, $APIName, $Headers) }
    function Set-CIPPSensitiveInfoType { param($TenantFilter, $Template, $APIName, $Headers) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'Test-CIPPBaselineCacheCollected.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineSensitivityLabelTemplateState.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineRetentionCompliancePolicyTemplateState.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineSensitiveInfoTypeTemplateState.ps1')
    . (Join-Path $Baselines 'Get-CIPPBaselineTransportRuleTemplateState.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineSensitivityLabelTemplate.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineRetentionCompliancePolicyTemplate.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineSensitiveInfoTypeTemplate.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }

    # Mirrors the engine: project Current down to the Expected keys, then compare.
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
}

Describe 'Get-CIPPBaselineSensitivityLabelTemplateState' {
    # A label created outside CIPP routinely carries a GUID-ish Name with the human name
    # only in DisplayName. Matching on Name alone reports a DEPLOYED label as missing, and
    # because this family writes unconditionally, remediation would then redeploy it on
    # every single run.
    BeforeAll {
        $script:Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ sensitivityLabelTemplate = 'tpl-1' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoLabels-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-1'; JSON = '{"Name":"Confidential"}' } }
    }

    It 'matches a deployed label on DisplayName when its Name differs' {
        Mock New-CIPPDbRequest { @(@{ Name = '9f1c-guid-ish'; DisplayName = 'Confidential' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Current.missingLabels).Count | Should -Be 0
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'matches a deployed label on Name' {
        Mock New-CIPPDbRequest { @(@{ Name = 'Confidential'; DisplayName = 'Something else' } | ConvertTo-Cached) }
        @((Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant).Current.missingLabels).Count | Should -Be 0
    }

    It 'reports a label the tenant does not have as drift' {
        Mock New-CIPPDbRequest { @(@{ Name = 'Public'; DisplayName = 'Public' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current.missingLabels | Should -Contain 'Confidential'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports drift, not No Data, when the tenant genuinely has no labels at all' {
        # Collected-and-empty is a real answer here: no labels means the label is missing.
        Mock New-CIPPDbRequest { @() }
        $Prepared = Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant
        $Prepared.Current | Should -Not -BeNullOrEmpty
        $Prepared.Current.missingLabels | Should -Contain 'Confidential'
    }

    It 'reports unknown when the label cache has never been collected' {
        Mock New-CIPPDbRequest { @() }
        Mock Get-CIPPDbItem { $null }
        (Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'reports unknown when the selected template no longer resolves' {
        # A deleted template is not a compliant tenant - the instance cannot evaluate.
        Mock New-CIPPDbRequest { @(@{ Name = 'Public'; DisplayName = 'Public' } | ConvertTo-Cached) }
        Mock Get-CIPPAzDataTableEntity { $null }
        (Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'resolves the picker whether it stored a plain id or a label/value pair' {
        Mock New-CIPPDbRequest { @(@{ Name = 'Public'; DisplayName = 'Public' } | ConvertTo-Cached) }
        $Paired = [PSCustomObject]@{ Variables = [PSCustomObject]@{ sensitivityLabelTemplate = [PSCustomObject]@{ label = 'Confidential'; value = 'tpl-1' } } }
        (Get-CIPPBaselineSensitivityLabelTemplateState -Item $Paired -TenantFilter $script:Tenant).Current.missingLabels | Should -Contain 'Confidential'
    }

    It 'carries the template body for the executor, which rewrites unconditionally' {
        Mock New-CIPPDbRequest { @(@{ Name = 'Confidential'; DisplayName = 'Confidential' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineSensitivityLabelTemplateState -Item $script:Item -TenantFilter $script:Tenant
        @($Prepared.Current.templateBodies).Count | Should -Be 1
    }
}

Describe 'Get-CIPPBaselineRetentionCompliancePolicyTemplateState' {
    # Deliberately asymmetric with the label family: retention policies carry no display
    # name, and the classic matched on Name alone.
    BeforeAll {
        $script:RetentionItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ retentionCompliancePolicyTemplate = 'tpl-r' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ComplianceRetentionPolicies-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-r'; JSON = '{"Name":"7 Year Retention"}' } }
    }

    It 'is compliant when the policy is deployed' {
        Mock New-CIPPDbRequest { @(@{ Name = '7 Year Retention' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineRetentionCompliancePolicyTemplateState -Item $script:RetentionItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports a policy the tenant does not have as drift' {
        Mock New-CIPPDbRequest { @(@{ Name = 'Something Else' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineRetentionCompliancePolicyTemplateState -Item $script:RetentionItem -TenantFilter $script:Tenant
        $Prepared.Current.missingPolicies | Should -Contain '7 Year Retention'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports unknown when the retention cache has never been collected' {
        Mock New-CIPPDbRequest { @() }
        Mock Get-CIPPDbItem { $null }
        (Get-CIPPBaselineRetentionCompliancePolicyTemplateState -Item $script:RetentionItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'reports unknown when the selected template no longer resolves' {
        # A deleted template is not a compliant tenant. Grading an empty template as
        # compliant would report success for a standard that is deploying nothing.
        Mock New-CIPPDbRequest { @(@{ Name = '7 Year Retention' } | ConvertTo-Cached) }
        Mock Get-CIPPAzDataTableEntity { $null }
        (Get-CIPPBaselineRetentionCompliancePolicyTemplateState -Item $script:RetentionItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineSensitiveInfoTypeTemplateState' {
    # The only template family that diffs rather than checking presence, and the only one
    # whose non-compliant set and remediable set are DIFFERENT sets.
    BeforeAll {
        $script:SitItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ sensitiveInfoTypeTemplate = 'tpl-s' } }
    }
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-s'; JSON = '{"Name":"Employee ID"}' } }
    }

    It 'treats an in-sync SIT as compliant' {
        Mock Compare-CIPPSensitiveInfoType { [PSCustomObject]@{ Name = 'Employee ID'; State = 'InSync'; Differences = @() } }
        $Prepared = Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'treats a built-in Microsoft SIT as compliant, not as a permanent failure' {
        # A built-in cannot be modified, so reporting it non-compliant would fail forever
        # and no amount of remediation could ever resolve it.
        Mock Compare-CIPPSensitiveInfoType { [PSCustomObject]@{ Name = 'Employee ID'; State = 'BuiltIn'; Differences = @() } }
        $Prepared = Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
        @($Prepared.Current.remediableTemplates).Count | Should -Be 0
    }

    It 'reports a drifted SIT and hands it to the executor' {
        Mock Compare-CIPPSensitiveInfoType { [PSCustomObject]@{ Name = 'Employee ID'; State = 'Drift'; Differences = @([PSCustomObject]@{ Scope = 'Entity'; Field = 'confidence' }) } }
        $Prepared = Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        @($Prepared.Current.remediableTemplates).Count | Should -Be 1
    }

    It 'reports a missing SIT and hands it to the executor' {
        Mock Compare-CIPPSensitiveInfoType { [PSCustomObject]@{ Name = 'Employee ID'; State = 'Missing'; Differences = @() } }
        $Prepared = Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        @($Prepared.Current.remediableTemplates).Count | Should -Be 1
    }

    It 'reports an invalid template but never hands it to the executor' {
        # Invalid is a broken TEMPLATE - neither Pattern nor rule pack - so deploying fails.
        Mock Compare-CIPPSensitiveInfoType { [PSCustomObject]@{ Name = 'Employee ID'; State = 'Invalid'; Differences = @([PSCustomObject]@{ Scope = 'Template'; Field = 'source' }) } }
        $Prepared = Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
        @($Prepared.Current.remediableTemplates).Count | Should -Be 0
    }

    It 'reports unknown when the tenant read fails, rather than reporting the SIT broken' {
        # A failed read is not drift. Grading it as drift would hand the executor a rewrite
        # on the strength of an outage.
        Mock Compare-CIPPSensitiveInfoType { throw 'compliance endpoint unavailable' }
        (Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'reports unknown when the selected template no longer resolves' {
        Mock Get-CIPPAzDataTableEntity { $null }
        (Get-CIPPBaselineSensitiveInfoTypeTemplateState -Item $script:SitItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPBaselineTransportRuleTemplateState' {
    # Presence by name against Identity, DisplayName AND Name - Exchange returns the rule
    # under different ones depending on how it was created.
    BeforeAll {
        $script:TransportItem = [PSCustomObject]@{ Variables = [PSCustomObject]@{ transportRuleTemplate = 'tpl-t' } }
    }
    BeforeEach {
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'ExoTransportRules-Count'; DataCount = 1 } }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ RowKey = 'tpl-t'; JSON = '{"name":"Block Autoforward","FromScope":"InOrganization"}' } }
    }

    It 'is compliant when the rule exists under any of Identity, DisplayName or Name' {
        Mock New-CIPPDbRequest { @(@{ Identity = 'some-guid'; DisplayName = 'Block Autoforward'; Name = 'other' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineTransportRuleTemplateState -Item $script:TransportItem -TenantFilter $script:Tenant
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -Be 0
    }

    It 'reports a rule the tenant does not have as drift' {
        Mock New-CIPPDbRequest { @(@{ Identity = 'x'; DisplayName = 'Another rule'; Name = 'Another rule' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineTransportRuleTemplateState -Item $script:TransportItem -TenantFilter $script:Tenant
        $Prepared.Current.missingTransportRules | Should -Contain 'Block Autoforward'
        (Get-Verdict -Expected $Prepared.Expected -Current $Prepared.Current).Count | Should -BeGreaterThan 0
    }

    It 'reports unknown when the selected template no longer resolves' {
        # The classic continued past an unresolvable template and read as compliant. Under
        # the instance model the template IS the instance - a deleted template means the
        # standard cannot evaluate, and compliant-by-deletion would be a lie.
        Mock New-CIPPDbRequest { @(@{ Identity = 'x'; DisplayName = 'y'; Name = 'y' } | ConvertTo-Cached) }
        Mock Get-CIPPAzDataTableEntity { $null }
        (Get-CIPPBaselineTransportRuleTemplateState -Item $script:TransportItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'reports unknown when the transport rule cache has never been collected' {
        Mock New-CIPPDbRequest { @() }
        Mock Get-CIPPDbItem { $null }
        (Get-CIPPBaselineTransportRuleTemplateState -Item $script:TransportItem -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'carries the rule body for the executor' {
        Mock New-CIPPDbRequest { @(@{ Identity = 'x'; DisplayName = 'y'; Name = 'y' } | ConvertTo-Cached) }
        $Prepared = Get-CIPPBaselineTransportRuleTemplateState -Item $script:TransportItem -TenantFilter $script:Tenant
        @($Prepared.Current.ruleBodies).Count | Should -Be 1
        $Prepared.Current.ruleBodies[0].FromScope | Should -Be 'InOrganization'
    }
}

Describe 'Template family executors' {
    # The label and retention families write unconditionally (checkBeforeRun:false) because
    # their compare only grades presence - the rewrite is what repairs setting-level drift
    # they cannot see. The SIT family is the opposite: it writes only what it proved needs
    # writing.
    It 'rewrites the selected label even when it is already present' {
        Mock Set-CIPPSensitivityLabel { }
        $Current = [PSCustomObject]@{ missingLabels = @(); templateBodies = @([PSCustomObject]@{ Name = 'A' }) }
        Invoke-CIPPBaselineSensitivityLabelTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSensitivityLabel -Times 1 -Exactly
    }

    It 'rewrites the selected retention policy even when it is already present' {
        Mock Set-CIPPRetentionCompliancePolicy { }
        $Current = [PSCustomObject]@{ missingPolicies = @(); templateBodies = @([PSCustomObject]@{ Name = 'A' }) }
        Invoke-CIPPBaselineRetentionCompliancePolicyTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPRetentionCompliancePolicy -Times 1 -Exactly
    }

    It 'writes only the SITs the hook marked remediable' {
        Mock Set-CIPPSensitiveInfoType { 'Updated Employee ID' }
        $Current = [PSCustomObject]@{
            nonCompliantSensitiveInfoTypes = @([PSCustomObject]@{ Name = 'Broken'; State = 'Invalid' })
            remediableTemplates            = @()
        }
        Invoke-CIPPBaselineSensitiveInfoTypeTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSensitiveInfoType -Times 0 -Exactly
    }

    It 'logs a SIT deploy that did not report Created or Updated as an error' {
        # Set-CIPPSensitiveInfoType reports failure in its return string rather than by
        # throwing, so a failed deploy is silent unless the result is inspected.
        Mock Set-CIPPSensitiveInfoType { 'Failed to deploy Employee ID: rule pack rejected' }
        Mock Write-LogMessage { }
        $Current = [PSCustomObject]@{ remediableTemplates = @([PSCustomObject]@{ Name = 'Employee ID' }) }
        Invoke-CIPPBaselineSensitiveInfoTypeTemplate -Remediate $null -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'does nothing at all when there is nothing to deploy' {
        Mock Set-CIPPSensitivityLabel { }
        Invoke-CIPPBaselineSensitivityLabelTemplate -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ templateBodies = @() })
        Should -Invoke Set-CIPPSensitivityLabel -Times 0 -Exactly
    }
}

Describe 'Instance row labeling' {
    # Ten instances of one standard are ten rows sharing one definition label - the suffix
    # is what tells them apart. CA/Intune surface it as ExpectedValue.displayName; the
    # presence-shaped families carry no name in Expected, so it comes from the identity
    # variable on the effective Inheritance entry, resolved through the DECLARED partition
    # and name field. The executor-name default would look in the wrong partition for every
    # family whose partition does not match its executor.
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Convert-CIPPBaselineResolvedEntity.ps1')
        $script:CaDefinition = [PSCustomObject]@{
            name = 'ConditionalAccessTemplate'; label = 'Conditional Access Template'
            instanceIdentity = 'caTemplate'
            remediate = [PSCustomObject]@{ executor = 'CATemplate' }
        }
        # Transport is the fixture ON PURPOSE: its partition ('TransportTemplate') differs
        # from its executor ('TransportRuleTemplate'), so a resolver that falls back to the
        # executor-name convention queries the wrong partition and these tests fail. A
        # family whose two names coincide could never detect that regression.
        $script:TransportDefinition = [PSCustomObject]@{
            name = 'TransportRuleTemplate'; label = 'Transport Rule Template'
            instanceIdentity = 'transportRuleTemplate'
            identity = [PSCustomObject]@{ partition = 'TransportTemplate'; nameField = 'name' }
            remediate = [PSCustomObject]@{ executor = 'TransportRuleTemplate' }
        }
        $script:Lookup = {
            param($Partition, $Id, $NameField)
            $script:LookupCalls.Add(@{ Partition = $Partition; Id = $Id; NameField = $NameField })
            if ($Partition -eq 'TransportTemplate' -and $Id -eq 'tpl-t') { 'Block Autoforward' }
            elseif ($Partition -eq 'CATemplate' -and $Id -eq 'ca-guid') { 'Block legacy auth' }
        }
    }
    BeforeEach { $script:LookupCalls = [System.Collections.Generic.List[object]]::new() }

    It 'labels a CA-style row from ExpectedValue.displayName, via the executor partition' {
        $Entity = [PSCustomObject]@{
            PartitionKey = 'contoso.onmicrosoft.com'; StandardName = 'ConditionalAccessTemplate#ab12cd34'
            ExpectedValue = '{"displayName":"ca-guid","state":"enabled"}'
        }
        $Row = Convert-CIPPBaselineResolvedEntity -Entity $Entity -Definitions @($script:CaDefinition) -ResolveTemplateName $script:Lookup
        $Row.standardLabel | Should -Be 'Conditional Access Template - Block legacy auth'
        $script:LookupCalls[0].Partition | Should -Be 'CATemplate'
    }

    It 'labels a presence-shaped row from the Inheritance identity variable, via the declared partition' {
        $Entity = [PSCustomObject]@{
            PartitionKey = 'contoso.onmicrosoft.com'; StandardName = 'TransportRuleTemplate#ab12cd34'
            ExpectedValue = '{"deployedTransportRules":[],"missingTransportRules":[]}'
            Inheritance = '[{"templateName":"Third baseline","effective":true,"value":{"transportRuleTemplate":{"label":"Block Autoforward","value":"tpl-t"}}}]'
        }
        $Row = Convert-CIPPBaselineResolvedEntity -Entity $Entity -Definitions @($script:TransportDefinition) -ResolveTemplateName $script:Lookup
        $Row.standardLabel | Should -Be 'Transport Rule Template - Block Autoforward'
        $script:LookupCalls[0].Partition | Should -Be 'TransportTemplate'
        $script:LookupCalls[0].NameField | Should -Be 'name'
    }

    It 'unwraps a plain-string identity variable the same way' {
        $Entity = [PSCustomObject]@{
            PartitionKey = 'contoso.onmicrosoft.com'; StandardName = 'TransportRuleTemplate#ab12cd34'
            ExpectedValue = '{"deployedTransportRules":[],"missingTransportRules":[]}'
            Inheritance = '[{"templateName":"Third baseline","effective":true,"value":{"transportRuleTemplate":"tpl-t"}}]'
        }
        $Row = Convert-CIPPBaselineResolvedEntity -Entity $Entity -Definitions @($script:TransportDefinition) -ResolveTemplateName $script:Lookup
        $Row.standardLabel | Should -Be 'Transport Rule Template - Block Autoforward'
    }

    It 'falls back to the definition label when nothing identifies the instance' {
        $Entity = [PSCustomObject]@{
            PartitionKey = 'contoso.onmicrosoft.com'; StandardName = 'TransportRuleTemplate#ab12cd34'
            ExpectedValue = '{"deployedTransportRules":[],"missingTransportRules":[]}'
        }
        $Row = Convert-CIPPBaselineResolvedEntity -Entity $Entity -Definitions @($script:TransportDefinition) -ResolveTemplateName $script:Lookup
        $Row.standardLabel | Should -Be 'Transport Rule Template'
    }
}
