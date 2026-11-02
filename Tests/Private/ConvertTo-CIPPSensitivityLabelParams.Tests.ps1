# Pester tests for ConvertTo-CIPPSensitivityLabelParams / ConvertTo-CIPPSensitivityLabelRights
# Guards cross-tenant portability of captured sensitivity labels: Azure RMS templates are provisioned per
# tenant, so a label captured from one tenant that carries its source template id fails to deploy anywhere
# else with RmsTemplateNotFoundException. The template id has to be dropped and the (portable) rights
# definitions carried instead, so Purview mints a fresh tenant-local template on deploy.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSensitivityLabelField.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSensitivityLabelRights.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPSensitivityLabelParams.ps1')

    function New-CapturedLabel {
        param(
            [hashtable] $EncryptSettings,
            [hashtable] $ExtraProperties = @{}
        )

        $Settings = foreach ($Key in $EncryptSettings.Keys) {
            [PSCustomObject]@{ Key = $Key; Value = $EncryptSettings[$Key] }
        }

        $Label = [ordered]@{
            Name         = 'Confidential - View Only'
            DisplayName  = 'Confidential - View Only'
            LabelActions = @([PSCustomObject]@{ Type = 'encrypt'; SubType = $null; Settings = @($Settings) })
            Settings     = @()
        }
        foreach ($Key in $ExtraProperties.Keys) { $Label[$Key] = $ExtraProperties[$Key] }

        return [PSCustomObject]$Label
    }
}

Describe 'ConvertTo-CIPPSensitivityLabelParams' {

    Context 'template-based encryption captured from another tenant' {
        BeforeAll {
            $Captured = New-CapturedLabel -EncryptSettings @{
                protectiontype                    = 'template'
                templateid                        = '7fb4b050-c987-43d4-94b0-fe93e07b2505'
                linkedtemplateid                  = '196087b2-9d05-4b05-80b8-832404cff4bb'
                rightsdefinitions                 = '[{"Identity":"AuthenticatedUsers","Rights":"VIEW,VIEWRIGHTSDATA,OBJMODEL"}]'
                contentexpiredondateindaysornever = 'Never'
                offlineaccessdays                 = '7'
            }
            $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Captured
        }

        It 'drops the source tenant RMS template id' {
            $Result.PSObject.Properties['EncryptionTemplateId'] | Should -BeNullOrEmpty
        }

        It 'drops the source tenant linked template id' {
            $Result.PSObject.Properties['EncryptionLinkedTemplateId'] | Should -BeNullOrEmpty
        }

        It 'carries the rights definitions Purview rebuilds the template from' {
            @($Result.EncryptionRightsDefinitions) | Should -Be @('AuthenticatedUsers:VIEW,VIEWRIGHTSDATA,OBJMODEL')
        }

        It 'keeps the rest of the template protection settings' {
            $Result.EncryptionEnabled | Should -BeTrue
            $Result.EncryptionProtectionType | Should -Be 'Template'
            $Result.EncryptionContentExpiredOnDateInDaysOrNever | Should -Be 'Never'
            $Result.EncryptionOfflineAccessDays | Should -Be 7
        }
    }

    It 'drops a flat template id carried alongside LabelActions' {
        # Get-Label has surfaced encryption state as flat properties as well as inside LabelActions, so the
        # non-portable ids have to be stripped from both or the capture smuggles one through.
        $Captured = New-CapturedLabel -EncryptSettings @{
            protectiontype    = 'template'
            rightsdefinitions = '[{"Identity":"AuthenticatedUsers","Rights":"VIEW"}]'
        } -ExtraProperties @{
            EncryptionTemplateId       = '7fb4b050-c987-43d4-94b0-fe93e07b2505'
            EncryptionLinkedTemplateId = '196087b2-9d05-4b05-80b8-832404cff4bb'
            EncryptionRMSTemplateId    = '7fb4b050-c987-43d4-94b0-fe93e07b2505'
        }

        $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Captured

        $Result.PSObject.Properties['EncryptionTemplateId'] | Should -BeNullOrEmpty
        $Result.PSObject.Properties['EncryptionLinkedTemplateId'] | Should -BeNullOrEmpty
        $Result.PSObject.Properties['EncryptionRMSTemplateId'] | Should -BeNullOrEmpty
    }

    It 'normalizes flat rights definitions objects into the write shape' {
        $Captured = New-CapturedLabel -EncryptSettings @{ protectiontype = 'template' } -ExtraProperties @{
            EncryptionRightsDefinitions = @([PSCustomObject]@{ Identity = 'admin@contoso.com'; Rights = 'VIEW, EDIT ,PRINT' })
        }

        $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Captured

        @($Result.EncryptionRightsDefinitions) | Should -Be @('admin@contoso.com:VIEW,EDIT,PRINT')
    }

    It 'does not send rights definitions with user-defined protection' {
        # EncryptionRightsDefinitions is only valid alongside the Template protection type.
        $Captured = New-CapturedLabel -EncryptSettings @{
            protectiontype = 'userdefined'
            donotforward   = 'true'
        } -ExtraProperties @{
            EncryptionRightsDefinitions = @([PSCustomObject]@{ Identity = 'AuthenticatedUsers'; Rights = 'VIEW' })
        }

        $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Captured

        $Result.EncryptionProtectionType | Should -Be 'UserDefined'
        $Result.EncryptionDoNotForward | Should -BeTrue
        $Result.PSObject.Properties['EncryptionRightsDefinitions'] | Should -BeNullOrEmpty
    }

    It 'leaves a deliberate template id on flat manual JSON alone' {
        # No LabelActions means hand-authored JSON, where a template id names a template the author knows
        # exists in the destination - the escape hatch for custom departmental RMS templates.
        $Manual = [PSCustomObject]@{
            Name                     = 'Departmental'
            EncryptionEnabled        = $true
            EncryptionProtectionType = 'Template'
            EncryptionTemplateId     = '7fb4b050-c987-43d4-94b0-fe93e07b2505'
        }

        $Result = ConvertTo-CIPPSensitivityLabelParams -Label $Manual

        $Result.EncryptionTemplateId | Should -Be '7fb4b050-c987-43d4-94b0-fe93e07b2505'
    }
}

Describe 'ConvertTo-CIPPSensitivityLabelRights' {

    It 'converts <Name>' -ForEach @(
        @{ Name = 'a JSON string of pairs'; Definitions ='[{"Identity":"AuthenticatedUsers","Rights":"VIEW,PRINT"}]'; Expected = @('AuthenticatedUsers:VIEW,PRINT') }
        @{ Name = 'multiple entries'; Definitions ='[{"Identity":"a@x.com","Rights":"VIEW"},{"Identity":"b@x.com","Rights":"EDIT"}]'; Expected = @('a@x.com:VIEW', 'b@x.com:EDIT') }
        @{ Name = 'an array of individual rights'; Definitions =@([PSCustomObject]@{ Identity = 'a@x.com'; Rights = @('VIEW', 'EDIT') }); Expected = @('a@x.com:VIEW,EDIT') }
        @{ Name = 'values already in the write shape'; Definitions ='a@x.com:VIEW;b@x.com:EDIT'; Expected = @('a@x.com:VIEW', 'b@x.com:EDIT') }
    ) {
        @(ConvertTo-CIPPSensitivityLabelRights -RightsDefinitions $Definitions) | Should -Be $Expected
    }

    It 'returns nothing for <Name>' -ForEach @(
        @{ Name = 'null'; Definitions =$null }
        @{ Name = 'an empty string'; Definitions ='' }
        @{ Name = 'an empty array'; Definitions =@() }
        @{ Name = 'malformed JSON'; Definitions ='[{"Identity":' }
        @{ Name = 'entries missing an identity'; Definitions =@([PSCustomObject]@{ Identity = ''; Rights = 'VIEW' }) }
        @{ Name = 'entries missing rights'; Definitions =@([PSCustomObject]@{ Identity = 'a@x.com'; Rights = $null }) }
    ) {
        @(ConvertTo-CIPPSensitivityLabelRights -RightsDefinitions $Definitions).Count | Should -Be 0
    }
}
