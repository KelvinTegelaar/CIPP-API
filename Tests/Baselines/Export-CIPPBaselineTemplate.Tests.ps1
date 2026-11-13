BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPBaseline { param($ID) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Expand-CIPPBaselineTemplatePackage { param($Definition, $Config, $TemplateRows) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines/Export-CIPPBaselineTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTemplateLink.ps1')

    $Folder = Join-Path $RepoRoot 'Config/BaselineStandards'
    $script:Definitions = @(
        Get-Content (Join-Path $Folder 'Templates/ConditionalAccessTemplate.json') -Raw | ConvertFrom-Json
        Get-Content (Join-Path $Folder 'Global Secure Access/GlobalSecureAccessProfileTemplate.json') -Raw | ConvertFrom-Json
    )
    function New-Row([string]$Partition, [string]$Guid, [hashtable]$Json) { [pscustomobject]@{ PartitionKey = $Partition; RowKey = $Guid; GUID = $Guid; JSON = ($Json | ConvertTo-Json -Depth 10 -Compress) } }
    function New-Link([string]$Label, [string]$Guid) { @{ policy = @{ label = $Label; value = $Guid }; priority = 100 } }
    $script:Rows = @{
        CATemplate                 = @(New-Row 'CATemplate' 'ca-1' @{ displayName = 'Staff web filtering'; sessionControls = @{ globalSecureAccessFilteringProfile = @{ profileId = @{ label = 'Contractors'; value = 'prof-2' }; isEnabled = $true } } })
        GSASecurityProfileTemplate = @(
            New-Row 'GSASecurityProfileTemplate' 'prof-1' @{ name = 'Staff'; policies = @(New-Link 'Block risky' 'pol-1') }
            New-Row 'GSASecurityProfileTemplate' 'prof-2' @{ name = 'Contractors'; policies = @((New-Link 'Block risky' 'pol-1'), (New-Link 'Block social' 'pol-2')) }
        )
        GSAFilteringPolicyTemplate = @(
            New-Row 'GSAFilteringPolicyTemplate' 'pol-1' @{ name = 'Block risky' }
            New-Row 'GSAFilteringPolicyTemplate' 'pol-2' @{ name = 'Block social' }
        )
    }
    function Invoke-Export {
        Export-CIPPBaselineTemplate -GUID 'baseline-1'
    }
}

Describe 'Export-CIPPBaselineTemplate' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definitions }
        Mock Get-CIPPAzDataTableEntity { $script:Rows[($Filter -replace "^PartitionKey eq '([^']+)'.*$", '$1')] }
        Mock Get-CIPPBaseline {
            [pscustomobject]@{
                templateName = 'GSA'; description = ''
                stages       = @([pscustomobject]@{
                        name = 'Stage 1'; standardsConfig = @(
                            [pscustomobject]@{ standard = 'ConditionalAccessTemplate'; instance = 'ConditionalAccessTemplate#ca000001'; variables = [pscustomobject]@{ caTemplate = 'ca-1'; state = 'disabled' } }
                            [pscustomobject]@{ standard = 'GlobalSecureAccessProfileTemplate'; instance = 'GlobalSecureAccessProfileTemplate#gsa00001'; variables = [pscustomobject]@{ profileTemplate = [pscustomobject]@{ label = 'Staff'; value = 'prof-1' } } }
                        )
                    })
            }
        }
    }

    It 'bundles the template each instance references, under its partition folder' {
        $Export = Invoke-Export
        @($Export.Baseline.stages[0].standards.instance) | Should -Be @('ConditionalAccessTemplate#ca000001', 'GlobalSecureAccessProfileTemplate#gsa00001')
        @($Export.Baseline.referencedTemplates | ForEach-Object { $_.path }) | Should -Contain 'CATemplate/Staff_web_filtering.json'
        @($Export.Baseline.referencedTemplates | ForEach-Object { $_.path }) | Should -Contain 'GSASecurityProfileTemplate/Staff.json'
    }

    It 'bundles the templates they link too, once each: a CA template''s security profile template and every profile''s filtering policy templates' {
        $Export = Invoke-Export
        @($Export.Templates | ForEach-Object { "$($_.PartitionKey)/$($_.RowKey)" } | Sort-Object) | Should -Be @(
            'CATemplate/ca-1'
            'GSAFilteringPolicyTemplate/pol-1'
            'GSAFilteringPolicyTemplate/pol-2'
            'GSASecurityProfileTemplate/prof-1'
            'GSASecurityProfileTemplate/prof-2'
        )
        @($Export.Baseline.referencedTemplates | ForEach-Object { $_.path } | Sort-Object) | Should -Be @(
            'CATemplate/Staff_web_filtering.json'
            'GSAFilteringPolicyTemplate/Block_risky.json'
            'GSAFilteringPolicyTemplate/Block_social.json'
            'GSASecurityProfileTemplate/Contractors.json'
            'GSASecurityProfileTemplate/Staff.json'
        )
    }

    It 'still exports when a linked template no longer exists, leaving that one out' {
        $script:Saved = $script:Rows.GSAFilteringPolicyTemplate
        $script:Rows.GSAFilteringPolicyTemplate = @($script:Rows.GSAFilteringPolicyTemplate[0])
        try {
            $Export = Invoke-Export
            @($Export.Templates | Where-Object PartitionKey -EQ 'GSAFilteringPolicyTemplate' | ForEach-Object { $_.RowKey }) | Should -Be @('pol-1')
            @($Export.Baseline.stages[0].standards).Count | Should -Be 2
        } finally { $script:Rows.GSAFilteringPolicyTemplate = $script:Saved }
    }

    It 'bundles nothing extra for a CA template without a security profile link' {
        $script:SavedCa = $script:Rows.CATemplate
        $script:Rows.CATemplate = @(New-Row 'CATemplate' 'ca-1' @{ displayName = 'Require MFA'; sessionControls = @{ signInFrequency = @{ value = 4 } } })
        Mock Get-CIPPBaseline { [pscustomobject]@{ templateName = 'MFA'; stages = @([pscustomobject]@{ name = 'Stage 1'; standardsConfig = @([pscustomobject]@{ standard = 'ConditionalAccessTemplate'; instance = 'ConditionalAccessTemplate#ca000001'; variables = [pscustomobject]@{ caTemplate = 'ca-1' } }) }) } }
        try {
            @((Invoke-Export).Templates | ForEach-Object { "$($_.PartitionKey)/$($_.RowKey)" }) | Should -Be @('CATemplate/ca-1')
        } finally { $script:Rows.CATemplate = $script:SavedCa }
    }
}
