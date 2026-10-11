# Pester tests for Set-CIPPIntuneTemplate's validation gate.
#
# The gate is deliberately asymmetric and that asymmetry is the whole point: a template that is
# already broken has to stay editable, or its owner cannot rename it, repackage it, or do anything
# else to it without first fixing a problem the template screen cannot fix. A payload the caller is
# submitting now is a different matter - that is someone replacing a working template with one that
# cannot deploy, and it is refused.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Add-CIPPAzDataTableEntity { param($Entity) $script:Written = $Entity }
    function Write-LogMessage { param($Headers, $API, $message, $Sev) $script:Logs.Add("$Sev|$message") }

    # Stands in for the validator so each test can state the verdict it is exercising, rather than
    # depending on a payload that happens to produce it.
    function Test-CIPPIntuneTemplate {
        param($RawJSON, $TemplateType, $DisplayName, $TenantFilter, [switch]$IncludeCatalogChecks)
        return $script:Verdict
    }

    . (Join-Path $Public 'Set-CIPPIntuneTemplate.ps1')

    function New-Verdict {
        param([bool]$IsValid, [string[]]$Errors = @(), [string[]]$Warnings = @())
        [pscustomobject]@{ IsValid = $IsValid; Errors = $Errors; Warnings = $Warnings; Type = 'Device'; DisplayName = 'x'; Findings = @() }
    }

    # Set here rather than in the Describe body: Pester evaluates that body during discovery, and a
    # variable assigned there is not in scope when the It blocks actually run.
    $script:ValidJson = '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","displayName":"Baseline"}'
}

Describe 'Set-CIPPIntuneTemplate' {
    BeforeEach {
        $script:Written = $null
        $script:Logs = [System.Collections.Generic.List[string]]::new()
        $script:Verdict = New-Verdict -IsValid $true
    }

    Context 'a valid template' {
        It 'is stored' {
            Set-CIPPIntuneTemplate -RawJSON $script:ValidJson -GUID 'g1' -DisplayName 'Baseline' -templateType 'Device'
            $script:Written | Should -Not -BeNullOrEmpty
            $script:Written.RowKey | Should -Be 'g1'
            $script:Written.PartitionKey | Should -Be 'IntuneTemplate'
        }

        It 'still logs warnings so they are not lost' {
            $script:Verdict = New-Verdict -IsValid $true -Warnings @('a setting is not in the catalog')
            Set-CIPPIntuneTemplate -RawJSON $script:ValidJson -GUID 'g1' -DisplayName 'Baseline' -templateType 'Device'
            $script:Written | Should -Not -BeNullOrEmpty
            ($script:Logs -join ' ') | Should -Match 'not in the catalog'
        }
    }

    Context 'an invalid payload the caller is submitting now' {
        It 'is refused, so a working template cannot be replaced by a broken one' {
            $script:Verdict = New-Verdict -IsValid $false -Errors @('A device configuration must carry @odata.type.')

            { Set-CIPPIntuneTemplate -RawJSON '{"displayName":"Baseline"}' -GUID 'g1' -DisplayName 'Baseline' -templateType 'Device' -PayloadChanged } |
                Should -Throw '*would not deploy*'

            $script:Written | Should -BeNullOrEmpty -Because 'nothing should be written when the write is refused'
        }
    }

    Context 'an edit that does not touch an already broken payload' {
        It 'is allowed through, so the template does not become uneditable' {
            $script:Verdict = New-Verdict -IsValid $false -Errors @('The template type could not be determined.')

            Set-CIPPIntuneTemplate -RawJSON '{"displayName":"Legacy"}' -GUID 'g1' -DisplayName 'Legacy renamed' -templateType $null

            $script:Written | Should -Not -BeNullOrEmpty
            $script:Written.RowKey | Should -Be 'g1'
        }

        It 'records why it was allowed through' {
            $script:Verdict = New-Verdict -IsValid $false -Errors @('The template type could not be determined.')

            Set-CIPPIntuneTemplate -RawJSON '{"displayName":"Legacy"}' -GUID 'g1' -DisplayName 'Legacy renamed' -templateType $null

            $Warned = @($script:Logs | Where-Object { $_ -like 'Warning|*' })
            $Warned | Should -Not -BeNullOrEmpty
            ($Warned -join ' ') | Should -Match 'did not change the policy'
        }
    }

    Context 'the display name' {
        It 'is still required' {
            { Set-CIPPIntuneTemplate -RawJSON $script:ValidJson -GUID 'g1' -DisplayName '' -templateType 'Device' } |
                Should -Throw '*displayname*'
        }
    }
}
