# Pester tests for Test-CIPPIntuneSchemaPayload
# Classic Intune payloads are checked against the property types in the generated Graph schema. Issue 1421:
# a feature update template stored a boolean as the text "false", which deployed but made every compare
# against the tenant report a difference.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPIntuneSchemaPayload.ps1')

    function Get-Finding {
        param([string]$Json, [string]$TemplateType)
        @(Test-CIPPIntuneSchemaPayload -Policy ($Json | ConvertFrom-Json -Depth 100) -TemplateType $TemplateType)
    }
}

Describe 'Test-CIPPIntuneSchemaPayload' {
    It 'flags the text boolean in the issue 1421 template and nothing else' {
        $Findings = Get-Finding -TemplateType 'windowsFeatureUpdateProfiles' -Json '{"displayName":"CBTS Feature Update - Test Devices V2","featureUpdateVersion":"Windows 11, version 26H2","roleScopeTagIds":["0"],"deployableContentDisplayName":"Windows 11, version 26H2","endOfSupportDate":"2029-10-09T00:00:00Z","installLatestWindows10OnWindows11IneligibleDevice":false,"installFeatureUpdatesOptional":"false","rolloutSettings":{"offerStartDateTimeInUTC":"%FUdateTest%"}}'
        $Findings | Should -HaveCount 1
        $Findings[0].Code | Should -Be 'TextBoolean'
        $Findings[0].Path | Should -Be 'installFeatureUpdatesOptional'
        $Findings[0].Severity | Should -Be 'Warning'
    }

    It 'passes the same template once the boolean is a boolean' {
        Get-Finding -TemplateType 'windowsFeatureUpdateProfiles' -Json '{"displayName":"x","installFeatureUpdatesOptional":false,"rolloutSettings":{"offerStartDateTimeInUTC":"2026-12-01T09:00:00.161Z","offerIntervalInDays":7}}' | Should -HaveCount 0
    }

    It 'leaves a %variable% unchecked whatever the declared type' {
        Get-Finding -TemplateType 'windowsFeatureUpdateProfiles' -Json '{"displayName":"x","installFeatureUpdatesOptional":"%FUOptional%","rolloutSettings":{"offerIntervalInDays":"%Days%"}}' | Should -HaveCount 0
    }

    It 'reports a property Graph does not define' {
        $Findings = Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.windows10EndpointProtectionConfiguration","displayName":"x","bitLockerPrebootRecoveryMsgURLOption":"default"}'
        $Findings.Code | Should -Be 'UnknownProperty'
        $Findings.Path | Should -Be 'bitLockerPrebootRecoveryMsgURLOption'
    }

    It 'reports an enum value Graph does not list, and accepts every listed one' {
        $Findings = Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","defenderCloudBlockLevel":"extreme"}'
        $Findings.Code | Should -Be 'UnknownEnumValue'
        Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","defenderCloudBlockLevel":"high"}' | Should -HaveCount 0
    }

    It 'checks each part of a flags enum' {
        $CertProfile = '{{"@odata.type":"#microsoft.graph.androidDeviceOwnerPkcsCertificateProfile","subjectAlternativeNameType":"{0}"}}'
        Get-Finding -TemplateType 'Device' -Json ($CertProfile -f 'emailAddress, userPrincipalName') | Should -HaveCount 0
        $Findings = Get-Finding -TemplateType 'Device' -Json ($CertProfile -f 'emailAddress,faxNumber')
        $Findings.Code | Should -Be 'UnknownEnumValue'
        $Findings.Message | Should -Match "'faxNumber'"
    }

    It 'reports a number stored as text, and a value of the wrong kind' {
        $Findings = Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.windows10GeneralConfiguration","passwordMinimumLength":"8","passwordRequired":"yes"}'
        ($Findings | Where-Object Path -EQ 'passwordMinimumLength').Code | Should -Be 'TextNumber'
        ($Findings | Where-Object Path -EQ 'passwordRequired').Code | Should -Be 'WrongType'
    }

    It 'reports a date that is not a date' {
        $Findings = Get-Finding -TemplateType 'windowsFeatureUpdateProfiles' -Json '{"displayName":"x","rolloutSettings":{"offerStartDateTimeInUTC":"next week"}}'
        $Findings.Code | Should -Be 'WrongType'
        $Findings.Path | Should -Be 'rolloutSettings.offerStartDateTimeInUTC'
    }

    It 'follows a subtype named by @odata.type inside a list' {
        $Findings = Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.windows10CustomConfiguration","displayName":"x","omaSettings":[{"@odata.type":"#microsoft.graph.omaSettingBoolean","displayName":"SkipUserSetupPage","omaUri":"./Device/x","value":"true"},{"@odata.type":"#microsoft.graph.omaSettingInteger","displayName":"n","omaUri":"./Device/y","value":5}]}'
        $Findings | Should -HaveCount 1
        $Findings[0].Code | Should -Be 'TextBoolean'
        $Findings[0].Path | Should -Be 'omaSettings[0].value'
    }

    It 'knows the contained actions a compliance policy carries' {
        Get-Finding -TemplateType 'deviceCompliancePolicies' -Json '{"@odata.type":"#microsoft.graph.windows10CompliancePolicy","displayName":"x","passwordRequired":true,"scheduledActionsForRule":[{"ruleName":"PasswordRequired","scheduledActionConfigurations":[{"actionType":"block","gracePeriodHours":0,"notificationTemplateId":"","notificationMessageCCList":[]}]}]}' | Should -HaveCount 0
    }

    It 'reports a single value where a list belongs' {
        $Findings = Get-Finding -TemplateType 'windowsFeatureUpdateProfiles' -Json '{"displayName":"x","roleScopeTagIds":"0"}'
        $Findings.Code | Should -Be 'WrongType'
    }

    It 'reports a type it does not know without checking its settings' {
        $Findings = Get-Finding -TemplateType 'Device' -Json '{"@odata.type":"#microsoft.graph.notARealConfiguration","anything":"x"}'
        $Findings.Code | Should -Be 'UnknownODataType'
    }

    It 'returns nothing for payloads the schema does not describe' {
        Get-Finding -TemplateType 'Catalog' -Json '{"name":"x","settings":[]}' | Should -HaveCount 0
    }
}
