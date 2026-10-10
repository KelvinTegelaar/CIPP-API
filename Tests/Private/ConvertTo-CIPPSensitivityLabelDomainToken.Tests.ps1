# Pester tests for ConvertTo-CIPPSensitivityLabelDomainToken
# A label that encrypts for its own organization names the source tenant's domain in its rights definitions.
# Captured into a template, that domain has to become %defaultdomain% so a deploy grants the rights to the
# tenant the label lands in rather than the one it came from.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSensitivityLabelField.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSensitivityLabelRights.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSensitivityLabelParams.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSensitivityLabelDomainToken.ps1')

    # Get-Label returns each LabelAction as a JSON string whose 'rightsdefinitions' value is itself a JSON string.
    $RightsJson = '[{"Identity":"contoso.com","Rights":"VIEW,DOCEDIT"},{"Identity":"user@contoso.com","Rights":"VIEW"},{"Identity":"notcontoso.com","Rights":"VIEW"}]'
    $EncryptAction = [ordered]@{
        Type     = 'encrypt'
        SubType  = $null
        Settings = @(
            @{ Key = 'protectiontype'; Value = 'template' }
            @{ Key = 'rightsdefinitions'; Value = $RightsJson }
        )
    } | ConvertTo-Json -Depth 5 -Compress

    $Captured = [PSCustomObject]@{
        Name                        = 'Confidential - Internal'
        DisplayName                 = 'Confidential - Internal'
        EncryptionRightsDefinitions = @([PSCustomObject]@{ Identity = 'Contoso.com'; Rights = 'VIEW,DOCEDIT' })
        LabelActions                = @($EncryptAction)
    }
    $Json = $Captured | ConvertTo-Json -Depth 10
}

Describe 'ConvertTo-CIPPSensitivityLabelDomainToken' {

    Context 'a captured label granting rights to its own tenant domain' {
        BeforeAll {
            $Tokenised = ConvertTo-CIPPSensitivityLabelDomainToken -Json $Json -Domains @('contoso.com', 'contoso.onmicrosoft.com')
            $Template = $Tokenised | ConvertFrom-Json
            $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Template
        }

        It 'still produces valid JSON' {
            $Template | Should -Not -BeNullOrEmpty
        }

        It 'replaces the domain on the flat property regardless of case' {
            $Template.EncryptionRightsDefinitions[0].Identity | Should -Be '%defaultdomain%'
        }

        It 'replaces the domain nested inside the encrypt LabelAction' {
            @($Result.EncryptionRightsDefinitions)[0] | Should -Be '%defaultdomain%:VIEW,DOCEDIT'
        }

        It 'leaves users in the source tenant alone' {
            @($Result.EncryptionRightsDefinitions)[1] | Should -Be 'user@contoso.com:VIEW'
        }

        It 'leaves other domains alone' {
            @($Result.EncryptionRightsDefinitions)[2] | Should -Be 'notcontoso.com:VIEW'
        }
    }

    Context 'nothing to replace' {
        It 'returns the template unchanged when no domains are supplied' {
            ConvertTo-CIPPSensitivityLabelDomainToken -Json $Json -Domains @() | Should -Be $Json
        }

        It 'returns the template unchanged when the domains do not appear' {
            ConvertTo-CIPPSensitivityLabelDomainToken -Json $Json -Domains @('fabrikam.com') | Should -Be $Json
        }
    }
}
