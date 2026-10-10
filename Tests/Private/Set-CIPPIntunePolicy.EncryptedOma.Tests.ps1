# Pester tests for encrypted OMA-URI secrets in custom device configuration templates.
#
# Graph returns an OMA-URI secret as a placeholder (value 'PGEvPg==', isEncrypted, secretReferenceValueId)
# tied to the source tenant. Capture decrypts it; if that fails, or a template arrives from elsewhere still
# encrypted, the placeholder can never be deployed ("SecretReferenceValueId invalid for create") and the
# source tenant can't be identified to recover it. Both capture and deploy therefore refuse it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # Stubs mirror the real signatures so signature drift fails loudly here.
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $ComplexFilter) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $type, $body, $AddedHeaders) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $Sev2, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) }
    function Get-CIPPTextReplacement { [CmdletBinding()] param([string]$TenantFilter, $Text, [switch]$EscapeForJson) }
    function Find-CIPPFuzzyPolicyMatch { [CmdletBinding()] param($DisplayName, $ExistingPolicies, $MaxDistance, $ODataType, $NameProperty, $TemplateId) }
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $PolicyId, $PlatformType, $Type, $TenantFilter, $ExcludeGroup, $AssignmentMode, $AssignmentFilterName, $AssignmentFilterType) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPIntunePolicy.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPOmaSettingDecryptedValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPIntuneTemplate.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    function New-CustomPolicy {
        param([switch]$Encrypted)
        $Setting = if ($Encrypted) {
            [ordered]@{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'AppLocker EXE'; omaUri = './Vendor/MSFT/AppLocker/x'; value = 'PGEvPg=='; isEncrypted = $true; secretReferenceValueId = 'abc_1' }
        } else {
            [ordered]@{ '@odata.type' = '#microsoft.graph.omaSettingStringXml'; displayName = 'AppLocker EXE'; omaUri = './Vendor/MSFT/AppLocker/x'; value = 'PFJ1bGVzLz4='; isEncrypted = $false }
        }
        [pscustomobject]@{
            '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
            displayName   = 'App Locker'
            omaSettings   = @([pscustomobject]$Setting)
        }
    }
}

Describe 'Set-CIPPIntunePolicy -TemplateType Device (encrypted OMA-URI settings)' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName Find-CIPPFuzzyPolicyMatch -MockWith { $null }
        Mock -CommandName Set-CIPPAssignedPolicy -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [PSCustomObject]@{ id = 'new-policy-id' } }
    }

    It 'refuses a template still holding the encrypted placeholder, naming the setting, without posting' {
        $RawJSON = New-CustomPolicy -Encrypted | ConvertTo-Json -Depth 10

        { Set-CIPPIntunePolicy -TemplateType 'Device' -DisplayName 'App Locker' -RawJSON $RawJSON -TenantFilter $script:Tenant } |
            Should -Throw -ExpectedMessage "*undecrypted OMA-URI setting(s) 'AppLocker EXE'*Recapture*"

        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'deploys a template whose OMA-URI values are plaintext' {
        $RawJSON = New-CustomPolicy | ConvertTo-Json -Depth 10

        Set-CIPPIntunePolicy -TemplateType 'Device' -DisplayName 'App Locker' -RawJSON $RawJSON -TenantFilter $script:Tenant |
            Should -BeLike 'Successfully added policy*'

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly
    }
}

Describe 'New-CIPPIntuneTemplate -URLName deviceConfigurations (encrypted OMA-URI settings)' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith { New-CustomPolicy -Encrypted }
    }

    It 'throws instead of storing the placeholder when decryption leaves it in place' {
        Mock -CommandName Get-CIPPOmaSettingDecryptedValue -MockWith { $DeviceConfiguration }

        { New-CIPPIntuneTemplate -URLName 'deviceConfigurations' -ID 'policy-id' -TenantFilter $script:Tenant } |
            Should -Throw -ExpectedMessage "*Could not decrypt*'AppLocker EXE'*not saved*logbook*DeviceManagementConfiguration.Read.All*"
    }

    It 'captures the template once the secret is decrypted' {
        Mock -CommandName Get-CIPPOmaSettingDecryptedValue -MockWith { New-CustomPolicy }

        $Result = New-CIPPIntuneTemplate -URLName 'deviceConfigurations' -ID 'policy-id' -TenantFilter $script:Tenant

        $Result.Type | Should -Be 'Device'
        $Result.TemplateJson | Should -Not -Match 'PGEvPg=='
    }
}

Describe 'Get-CIPPOmaSettingDecryptedValue (decrypt failure)' {
    It 'writes the Graph error to the logbook so the capture error can point there' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }
        Mock -CommandName Get-NormalizedError -MockWith { $Message }
        Mock -CommandName Write-LogMessage -MockWith { }

        $Result = Get-CIPPOmaSettingDecryptedValue -DeviceConfiguration (New-CustomPolicy -Encrypted) -DeviceConfigurationId 'policy-id' -TenantFilter $script:Tenant -WarningAction SilentlyContinue

        $Result.omaSettings[0].secretReferenceValueId | Should -Be 'abc_1'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like "*'AppLocker EXE'*Forbidden*" -and $tenant -eq $script:Tenant }
    }
}
