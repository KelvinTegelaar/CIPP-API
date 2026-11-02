# Pester tests for Set-CIPPSensitivityLabel
# Regression guard for https://github.com/CyberDrain/CIPP/issues/775: a captured label with template-based
# encryption failed to deploy because EncryptionRightsDefinitions was sent as a JSON array of
# 'identity:rights' strings. The cmdlet parameter is a single EncryptionRightsDefinitionsParameter value
# ('Identity1:Rights;Identity2:Rights'), so the AdminApi could not bind the List[string] it deserialized.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, [switch]$Compliance, $useSystemMailbox) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text -replace '%defaultdomain%', 'target.onmicrosoft.com' }

    . (Join-Path $Public 'Get-CIPPSensitivityLabelField.ps1')
    . (Join-Path $Public 'ConvertTo-CIPPSensitivityLabelRights.ps1')
    . (Join-Path $Public 'ConvertTo-CIPPSensitivityLabelParams.ps1')
    . (Join-Path $Public 'Format-CIPPCompliancePolicyParams.ps1')
    . (Join-Path $Public 'ConvertTo-CIPPComplianceSetParams.ps1')
    . (Join-Path $Public 'ConvertTo-CIPPExoHashtable.ps1')
    . (Join-Path $Public 'Set-CIPPSensitivityLabel.ps1')

    # The label from the issue report, as captured by Get-Label and stored as a template.
    $script:IssueTemplate = @'
{"DisplayName":"Confidential","Name":"Confidential","Comment":"Client data","Settings":["[isparent, False]","[contenttype, File, Email, Teamwork]","[tooltip, Client data]","[displayname, Confidential]","[color, #EAA300]"],"LabelActions":["{\"Type\":\"encrypt\",\"SubType\":null,\"Settings\":[{\"Key\":\"protectiontype\",\"Value\":\"template\"},{\"Key\":\"disabled\",\"Value\":\"false\"},{\"Key\":\"templateid\",\"Value\":\"2dcacb2f-6b6b-49d1-9625-c0ae349ac5c9\"},{\"Key\":\"templatearchived\",\"Value\":\"False\"},{\"Key\":\"linkedtemplateid\",\"Value\":\"2dcacb2f-6b6b-49d1-9625-c0ae349ac5c9\"},{\"Key\":\"contentexpiredondateindaysornever\",\"Value\":\"Never\"},{\"Key\":\"offlineaccessdays\",\"Value\":\"-1\"},{\"Key\":\"rightsdefinitions\",\"Value\":\"[{\\\"Identity\\\":\\\"%defaultdomain%\\\",\\\"Rights\\\":\\\"VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,EXTRACT,REPLY,REPLYALL,FORWARD,OBJMODEL\\\"}]\"},{\"Key\":\"disableautomaticownerrights\",\"Value\":\"False\"}]}","{\"Type\":\"applycontentmarking\",\"SubType\":\"footer\",\"Settings\":[{\"Key\":\"text\",\"Value\":\"Confidential\"},{\"Key\":\"fontsize\",\"Value\":\"10\"},{\"Key\":\"fontcolor\",\"Value\":\"#000000\"},{\"Key\":\"alignment\",\"Value\":\"Left\"},{\"Key\":\"margin\",\"Value\":\"5\"},{\"Key\":\"placement\",\"Value\":\"Footer\"},{\"Key\":\"disabled\",\"Value\":\"false\"}]}"],"Conditions":[],"LocaleSettings":[],"ParentId":null,"Tooltip":"Client data","ContentType":"File, Email, Teamwork","ParentLabelDisplayName":null,"Priority":2,"Disabled":false,"GUID":"6d4cdb63-adb4-4d2c-a988-3f7f5a4b99b9"}
'@ | ConvertFrom-Json
}

Describe 'Set-CIPPSensitivityLabel encryption rights (issue #775)' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock New-ExoRequest {
            $script:Calls.Add(@{ Cmdlet = $cmdlet; Params = $cmdParams })
            if ($cmdlet -in @('Get-Label', 'Get-LabelPolicy')) { return @() }
        }
    }

    It 'sends EncryptionRightsDefinitions to New-Label as a single string, not an array' {
        $Result = Set-CIPPSensitivityLabel -TenantFilter 'target.onmicrosoft.com' -Template $script:IssueTemplate -APIName 'Test'

        $Result | Should -BeLike 'Created sensitivity label*'
        $NewLabel = $script:Calls | Where-Object { $_.Cmdlet -eq 'New-Label' } | Select-Object -First 1
        $NewLabel | Should -Not -BeNullOrEmpty

        $Rights = $NewLabel.Params['EncryptionRightsDefinitions']
        $Rights | Should -BeOfType [string]
        $Rights | Should -Be 'target.onmicrosoft.com:VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,EXTRACT,REPLY,REPLYALL,FORWARD,OBJMODEL'

        # The tenant-scoped RMS template ids must not travel with the label.
        $NewLabel.Params.ContainsKey('EncryptionTemplateId') | Should -BeFalse
        $NewLabel.Params.ContainsKey('EncryptionLinkedTemplateId') | Should -BeFalse
        $NewLabel.Params['EncryptionProtectionType'] | Should -Be 'Template'
        $NewLabel.Params['ApplyContentMarkingFooterText'] | Should -Be 'Confidential'
    }

    It 'joins several grants with ";" into one value' {
        $Template = [PSCustomObject]@{
            Name                        = 'Multi'
            DisplayName                 = 'Multi'
            EncryptionEnabled           = $true
            EncryptionProtectionType    = 'Template'
            EncryptionRightsDefinitions = @('AuthenticatedUsers:VIEW', 'admin@contoso.com:VIEW,EDIT,PRINT')
        }

        $null = Set-CIPPSensitivityLabel -TenantFilter 'target.onmicrosoft.com' -Template $Template -APIName 'Test'

        $NewLabel = $script:Calls | Where-Object { $_.Cmdlet -eq 'New-Label' } | Select-Object -First 1
        $NewLabel.Params['EncryptionRightsDefinitions'] | Should -BeOfType [string]
        $NewLabel.Params['EncryptionRightsDefinitions'] | Should -Be 'AuthenticatedUsers:VIEW;admin@contoso.com:VIEW,EDIT,PRINT'
    }

    It 'passes a manually authored single-string value through unchanged' {
        $Template = [PSCustomObject]@{
            Name                        = 'Manual'
            DisplayName                 = 'Manual'
            EncryptionEnabled           = $true
            EncryptionProtectionType    = 'Template'
            EncryptionRightsDefinitions = 'AuthenticatedUsers:VIEW;admin@contoso.com:EDIT'
        }

        $null = Set-CIPPSensitivityLabel -TenantFilter 'target.onmicrosoft.com' -Template $Template -APIName 'Test'

        $NewLabel = $script:Calls | Where-Object { $_.Cmdlet -eq 'New-Label' } | Select-Object -First 1
        $NewLabel.Params['EncryptionRightsDefinitions'] | Should -Be 'AuthenticatedUsers:VIEW;admin@contoso.com:EDIT'
    }

    It 'uses the same single-string shape on the Set-Label update path' {
        Mock New-ExoRequest {
            $script:Calls.Add(@{ Cmdlet = $cmdlet; Params = $cmdParams })
            if ($cmdlet -eq 'Get-Label') { return @([PSCustomObject]@{ Name = 'Confidential'; DisplayName = 'Confidential'; Guid = 'abc'; ImmutableId = 'abc' }) }
            if ($cmdlet -eq 'Get-LabelPolicy') { return @() }
        }

        $Result = Set-CIPPSensitivityLabel -TenantFilter 'target.onmicrosoft.com' -Template $script:IssueTemplate -APIName 'Test'

        $Result | Should -BeLike 'Updated sensitivity label*'
        $SetLabel = $script:Calls | Where-Object { $_.Cmdlet -eq 'Set-Label' -and $_.Params.ContainsKey('EncryptionRightsDefinitions') } | Select-Object -First 1
        $SetLabel | Should -Not -BeNullOrEmpty
        $SetLabel.Params['EncryptionRightsDefinitions'] | Should -BeOfType [string]
        $SetLabel.Params['EncryptionRightsDefinitions'] | Should -Be 'target.onmicrosoft.com:VIEW,VIEWRIGHTSDATA,DOCEDIT,EDIT,PRINT,EXTRACT,REPLY,REPLYALL,FORWARD,OBJMODEL'
    }
}
