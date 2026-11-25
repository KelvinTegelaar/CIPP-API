# The one path every managed write takes: the package's templates first, always overwritten,
# then the baseline with its CyberDrain id and version.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Import-CommunityTemplate { param($Template, $SHA, $Source, [switch]$Force) }
    function New-CIPPBaseline { param($Baseline, $User, $Managed) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Import-CIPPManagedBaseline.ps1')

    $script:Package = [pscustomobject]@{
        id        = 'managed-1'
        version   = 4
        Baseline  = [pscustomobject]@{ templateName = 'CyberDrain Essentials' }
        Templates = @(
            [pscustomobject]@{ RowKey = 'tpl-1'; PartitionKey = 'CATemplate'; JSON = '{}' }
            [pscustomobject]@{ RowKey = 'tpl-2.IntuneTemplate.json'; GUID = 'tpl-2'; PartitionKey = 'IntuneTemplate'; JSON = '{}' }
        )
    }
    $script:Payload = [pscustomobject]@{ templateName = 'Contoso baseline' }
}

Describe 'Import-CIPPManagedBaseline' {
    BeforeEach {
        Mock Import-CommunityTemplate {}
        Mock New-CIPPBaseline { @{ GUID = 'baseline-1'; DeltaCount = 3 } }
    }

    It 'overwrites every template in the package and stamps it with the package version' {
        $Result = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload -User 'admin@partner.example'

        $Result.Templates | Should -Be 2
        Should -Invoke Import-CommunityTemplate -Times 2 -Exactly -ParameterFilter {
            $Force -and $SHA -eq 'managed-1@4' -and $Source -eq 'CyberDrain Managed Baselines'
        }
    }

    It 'saves the payload it was handed, marked with the CyberDrain id and version' {
        $Result = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload -Kind 'custom' -RequestId 'request-9' -User 'admin@partner.example'

        $Result.GUID | Should -Be 'baseline-1'
        Should -Invoke New-CIPPBaseline -Times 1 -Exactly -ParameterFilter {
            $Baseline.templateName -eq 'Contoso baseline' -and $User -eq 'admin@partner.example' -and
            $Managed.Id -eq 'managed-1' -and $Managed.Version -eq '4' -and $Managed.Kind -eq 'custom' -and $Managed.RequestId -eq 'request-9'
        }
    }

    It 'leaves the request id alone when it is not given one' {
        $null = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload

        Should -Invoke New-CIPPBaseline -Times 1 -Exactly -ParameterFilter { -not $Managed.ContainsKey('RequestId') -and $Managed.Kind -eq 'template' }
    }

    It 'writes only the templates it is told to, matched on row key or id' {
        $null = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload -TemplateIds @('tpl-2')

        Should -Invoke Import-CommunityTemplate -Times 1 -Exactly -ParameterFilter { $Template.GUID -eq 'tpl-2' }
    }

    It 'writes no template when it is told to write none' {
        $Result = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload -TemplateIds @()

        $Result.Templates | Should -Be 0
        Should -Invoke Import-CommunityTemplate -Times 0 -Exactly
        Should -Invoke New-CIPPBaseline -Times 1 -Exactly
    }

    It 'still saves the baseline when a template cannot be written, and says which one' {
        Mock Import-CommunityTemplate { if ($Template.RowKey -eq 'tpl-1') { throw 'table said no' } }

        $Result = Import-CIPPManagedBaseline -Package $script:Package -Baseline $script:Payload

        $Result.Templates | Should -Be 1
        $Result.Failures | Should -Be @('tpl-1: table said no')
        Should -Invoke New-CIPPBaseline -Times 1 -Exactly
    }
}
