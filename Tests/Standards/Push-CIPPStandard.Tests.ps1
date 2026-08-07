# Pester tests for Push-CIPPStandard's settings handling.
#
# The dispatcher round-trips a standard's settings through JSON so %variables% can be resolved in
# one pass. Two things went wrong there when an Intune template was deployed from Standards
# Management, while the same template deployed fine from Endpoint > Configuration Policies:
#
#   1. The template picker attaches the whole API row it was populated from to the selected value,
#      as .rawData - so the settings carried a second copy of the policy payload, a JSON document
#      nested inside the settings as an escaped string.
#   2. Replacement ran against that serialized document without escaping the values it spliced in,
#      so a logon banner reading 'property of "Contoso"' closed the string it landed in and the
#      reparse threw:
#        Conversion from JSON failed ... unexpected character was encountered: O.
#        Path 'TemplateList.rawData.RAWJson'
#
# Get-CIPPTextReplacement and Remove-CIPPStandardSettingsRawData are dot-sourced for real here, so
# these exercise the actual escaping and stripping rather than a mock of them.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'

    function Resolve-CippFunctionFile {
        param([string]$Name)
        $Found = Get-ChildItem -Path $ModulesRoot -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $Found) { throw "Could not locate $Name under Modules/" }
        return $Found
    }

    # Stubs mirror the real signatures and are advanced functions on purpose: strict parameter
    # binding makes signature drift fail loudly here instead of silently landing in $args.
    function Test-CIPPRerun { [CmdletBinding()] param($Type, $Tenant, $API, $BaseTime, $Settings) }
    function Set-CippStandardInfoContext { [CmdletBinding()] param($StandardInfo) }
    function Set-CippUserAgentContext { [CmdletBinding()] param($Source, $TemplateId) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData, $headers) }
    function Get-CippException { [CmdletBinding()] param($Exception) }
    function Get-CIPPTable { [CmdletBinding()] param($tablename) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter) }
    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSchemaExtensions { [CmdletBinding()] param() }

    # Stand-ins for the real standards. Each captures what the dispatcher handed it. Three shapes are
    # covered: the two template standards, which compose their rerun key from the selected template,
    # and an ordinary standard, which does not.
    function Invoke-CIPPStandardIntuneTemplate {
        [CmdletBinding()]
        param($Tenant, $Settings)
        $script:CapturedSettings = $Settings
        $script:CapturedTenant = $Tenant
        $script:CapturedStandard = 'IntuneTemplate'
        if ($script:StandardShouldThrow) { throw 'Graph exploded' }
    }
    function Invoke-CIPPStandardConditionalAccessTemplate {
        [CmdletBinding()]
        param($Tenant, $Settings)
        $script:CapturedSettings = $Settings
        $script:CapturedTenant = $Tenant
        $script:CapturedStandard = 'ConditionalAccessTemplate'
    }
    function Invoke-CIPPStandardAntiPhishPolicy {
        [CmdletBinding()]
        param($Tenant, $Settings)
        $script:CapturedSettings = $Settings
        $script:CapturedTenant = $Tenant
        $script:CapturedStandard = 'AntiPhishPolicy'
    }

    . (Resolve-CippFunctionFile -Name 'Get-CIPPTextReplacement.ps1')
    . (Resolve-CippFunctionFile -Name 'Remove-CIPPStandardSettingsRawData.ps1')
    . (Resolve-CippFunctionFile -Name 'Push-CIPPStandard.ps1')

    # A stored Intune template row, shaped the way CippAutocomplete hands it back: the policy itself
    # lives in RAWJson as a JSON document carried inside a string.
    function New-IntuneTemplateRow {
        param([int]$SettingCount = 40)
        $Settings = @(
            '{"value":"%endpointdisclaimertitle%"}'
            '{"value":"%endpointdisclaimermessagel1%"}'
            '{"value":"%localadminacct%"}'
            for ($i = 0; $i -lt $SettingCount; $i++) { '{"value":"%SystemRoot%\\\\system32\\\\setting' + $i + '"}' }
        ) -join ','
        [pscustomobject]@{
            RowKey      = '1e020af9-3969-4eab-8156-f942cbeeea4f'
            Displayname = 'GCT-Device-Baseline-Policy'
            Type        = 'Catalog'
            RAWJson     = '{"platforms":"windows10","settings":[' + $Settings + ']}'
        }
    }

    function New-QueueItem {
        param($Settings, [string]$Standard = 'IntuneTemplate')
        [pscustomobject]@{
            Tenant     = 'contoso.onmicrosoft.com'
            Standard   = $Standard
            TemplateId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            QueuedTime = 0
            Settings   = $Settings
        }
    }

    function New-TemplateSettings {
        [pscustomobject]@{
            TemplateList = [pscustomobject]@{
                label       = 'GCT-Device-Baseline-Policy'
                value       = '1e020af9-3969-4eab-8156-f942cbeeea4f'
                addedFields = [pscustomobject]@{ package = 'baseline' }
                rawData     = New-IntuneTemplateRow
            }
            AssignTo     = 'AllDevices'
            remediate    = $true
            report       = $true
        }
    }
}

Describe 'Push-CIPPStandard settings handling' {
    BeforeEach {
        $script:CapturedSettings = $null
        $script:CapturedTenant = $null
        $script:CapturedStandard = $null
        $script:CapturedApi = $null
        $script:CapturedStandardInfo = $null
        $script:StandardShouldThrow = $false
        $script:LoggedErrors = @()
        $script:LoggedWarnings = @()

        # The tenant's custom variables. The banner line carrying a quote is the payload that broke
        # the reparse in production.
        $script:GlobalRows = @(
            [pscustomobject]@{ RowKey = 'endpointdisclaimertitle'; Value = 'Authorised Use Only' }
            [pscustomobject]@{ RowKey = 'endpointdisclaimermessagel1'; Value = 'This system is the property of "Onelife Dermatology HB".' }
            [pscustomobject]@{ RowKey = 'localadminacct'; Value = 'LocalAdmin' }
            [pscustomobject]@{ RowKey = 'sitecode'; Value = 'FAB01' }
            [pscustomobject]@{ RowKey = 'sharepath'; Value = '\\srv\share$\folder' }
        )

        Mock -CommandName Test-CIPPRerun -MockWith {
            param($Type, $Tenant, $API, $BaseTime, $Settings)
            $script:CapturedApi = $API
            $false
        }
        Mock -CommandName Set-CippStandardInfoContext -MockWith {
            param($StandardInfo)
            # Called twice: once with the context, once with $null to clear it in the finally block.
            if ($null -ne $StandardInfo) { $script:CapturedStandardInfo = $StandardInfo }
        }
        Mock -CommandName Set-CippUserAgentContext -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPSchemaExtensions -MockWith { @() }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev, $LogData, $headers)
            if ($sev -eq 'Error') { $script:LoggedErrors += $message }
            if ($sev -eq 'Warning') { $script:LoggedWarnings += $message }
        }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{
                customerId        = '11111111-1111-1111-1111-111111111111'
                defaultDomainName = 'contoso.onmicrosoft.com'
                initialDomainName = 'contoso.onmicrosoft.com'
                displayName       = 'Contoso Ltd'
            }
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            if ($Filter -match "PartitionKey eq 'AllTenants'") { return $script:GlobalRows }
            return @()
        }
        # The dispatcher gates on the standard existing in the CIPPStandards module, which is not
        # loaded here. Only that lookup is intercepted.
        Mock -CommandName Get-Command -MockWith {
            [pscustomobject]@{ Name = 'Invoke-CIPPStandardIntuneTemplate' }
        } -ParameterFilter { $Module -contains 'CIPPStandards' }
    }

    Context 'the reported failure' {
        It 'does not throw when a custom variable contains a double quote' {
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            { Push-CIPPStandard -Item $Item } | Should -Not -Throw
        }

        It 'runs the standard instead of failing before it' {
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            Push-CIPPStandard -Item $Item

            $script:CapturedSettings | Should -Not -BeNullOrEmpty
            $script:CapturedTenant | Should -Be 'contoso.onmicrosoft.com'
        }

        It 'logs no error' {
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            Push-CIPPStandard -Item $Item

            $script:LoggedErrors | Should -BeNullOrEmpty
        }
    }

    Context 'what the standard receives' {
        BeforeEach {
            $Item = New-QueueItem -Settings (New-TemplateSettings)
            Push-CIPPStandard -Item $Item
        }

        It 'gets the template id it resolves the template by' {
            $script:CapturedSettings.TemplateList.value | Should -Be '1e020af9-3969-4eab-8156-f942cbeeea4f'
        }

        It 'does not get the rawData snapshot' {
            $script:CapturedSettings.TemplateList.PSObject.Properties.Name | Should -Not -Contain 'rawData'
        }

        It 'keeps the rest of the settings intact' {
            $script:CapturedSettings.AssignTo | Should -Be 'AllDevices'
            $script:CapturedSettings.remediate | Should -BeTrue
            $script:CapturedSettings.report | Should -BeTrue
            $script:CapturedSettings.TemplateList.addedFields.package | Should -Be 'baseline'
        }
    }

    Context 'variable replacement still happens' {
        It 'resolves a custom variable in an ordinary setting' {
            $Settings = [pscustomobject]@{ customGroup = 'SG-%sitecode%-Devices'; remediate = $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings)

            $script:CapturedSettings.customGroup | Should -Be 'SG-FAB01-Devices'
        }

        It 'resolves a built-in tenant token' {
            $Settings = [pscustomobject]@{ customGroup = 'SG-%tenantfilter%'; remediate = $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings)

            $script:CapturedSettings.customGroup | Should -Be 'SG-contoso.onmicrosoft.com'
        }

        It 'round-trips a value containing a quote rather than corrupting the document' {
            $Settings = [pscustomobject]@{ customGroup = '%endpointdisclaimermessagel1%'; remediate = $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings)

            $script:CapturedSettings.customGroup | Should -Be 'This system is the property of "Onelife Dermatology HB".'
        }

        It 'passes settings through untouched when there is nothing to replace' {
            $Settings = [pscustomobject]@{ customGroup = 'SG-Devices'; remediate = $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings)

            $script:CapturedSettings.customGroup | Should -Be 'SG-Devices'
            $script:CapturedSettings.remediate | Should -BeTrue
        }
    }

    Context 'the caller object' {
        It 'still has its rawData afterwards' {
            # The dispatcher reads $Item.Settings for telemetry after building the run copy.
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            Push-CIPPStandard -Item $Item

            $Item.Settings.TemplateList.PSObject.Properties.Name | Should -Contain 'rawData'
            $Item.Settings.TemplateList.rawData.RAWJson | Should -Not -BeNullOrEmpty
        }

        It 'still exposes the template id the telemetry reads' {
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            Push-CIPPStandard -Item $Item

            $Item.Settings.TemplateList.value | Should -Be '1e020af9-3969-4eab-8156-f942cbeeea4f'
        }
    }

    Context 'Conditional Access templates' {
        BeforeEach {
            $script:CASettings = [pscustomobject]@{
                TemplateList = [pscustomobject]@{
                    label       = 'Require MFA for admins'
                    value       = 'ca-template-guid'
                    addedFields = [pscustomobject]@{}
                    rawData     = [pscustomobject]@{
                        RowKey  = 'ca-template-guid'
                        JSON    = '{"displayName":"Require MFA for admins - %tenantname%"}'
                        GUID    = 'ca-template-guid'
                        RAWJson = '{"displayName":"%endpointdisclaimermessagel1%"}'
                    }
                }
                remediate    = $true
            }
        }

        It 'strips the rawData snapshot for CA templates too' {
            Push-CIPPStandard -Item (New-QueueItem -Settings $script:CASettings -Standard 'ConditionalAccessTemplate')

            $script:CapturedStandard | Should -Be 'ConditionalAccessTemplate'
            $script:CapturedSettings.TemplateList.PSObject.Properties.Name | Should -Not -Contain 'rawData'
            $script:CapturedSettings.TemplateList.value | Should -Be 'ca-template-guid'
        }

        It 'does not throw on a CA template whose payload holds a quoted variable' {
            { Push-CIPPStandard -Item (New-QueueItem -Settings $script:CASettings -Standard 'ConditionalAccessTemplate') } |
                Should -Not -Throw
        }

        It 'records the CA template id on the standard context' {
            Push-CIPPStandard -Item (New-QueueItem -Settings $script:CASettings -Standard 'ConditionalAccessTemplate')

            $script:CapturedStandardInfo.ConditionalAccessTemplateId | Should -Be 'ca-template-guid'
            $script:CapturedStandardInfo.Standard | Should -Be 'ConditionalAccessTemplate'
        }
    }

    Context 'the rerun key' {
        It 'includes the selected template for a template standard' {
            # Two Intune templates in one standards template must not collapse onto one rerun key.
            Push-CIPPStandard -Item (New-QueueItem -Settings (New-TemplateSettings))

            $script:CapturedApi | Should -Be 'IntuneTemplate_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee_1e020af9-3969-4eab-8156-f942cbeeea4f'
        }

        It 'is the standard and template id for an ordinary standard' {
            $Settings = [pscustomobject]@{ remediate = $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            $script:CapturedApi | Should -Be 'AntiPhishPolicy_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        }
    }

    Context 'ordinary standards' {
        It 'runs a standard that has no template picker at all' {
            $Settings = [pscustomobject]@{
                remediate       = $true
                report          = $true
                alert           = $false
                ExcludedTenants = @()
                PhishThreshold  = 2
            }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            $script:CapturedStandard | Should -Be 'AntiPhishPolicy'
            $script:CapturedSettings.PhishThreshold | Should -Be 2
            $script:CapturedSettings.remediate | Should -BeTrue
            $script:CapturedSettings.alert | Should -BeFalse
        }

        It 'records no template id on the standard context' {
            Push-CIPPStandard -Item (New-QueueItem -Settings ([pscustomobject]@{ remediate = $true }) -Standard 'AntiPhishPolicy')

            $script:CapturedStandardInfo.Standard | Should -Be 'AntiPhishPolicy'
            $script:CapturedStandardInfo.Keys | Should -Not -Contain 'IntuneTemplateId'
            $script:CapturedStandardInfo.Keys | Should -Not -Contain 'ConditionalAccessTemplateId'
        }

        It 'resolves variables inside a nested settings object' {
            $Settings = [pscustomobject]@{
                remediate = $true
                Advanced  = [pscustomobject]@{
                    Naming = [pscustomobject]@{ Prefix = 'SG-%sitecode%' }
                }
            }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            $script:CapturedSettings.Advanced.Naming.Prefix | Should -Be 'SG-FAB01'
        }

        It 'resolves variables inside an array setting' {
            $Settings = [pscustomobject]@{
                remediate = $true
                Groups    = @('SG-%sitecode%-A', 'SG-%sitecode%-B')
            }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            @($script:CapturedSettings.Groups) | Should -Be @('SG-FAB01-A', 'SG-FAB01-B')
        }

        It 'accepts hashtable settings' {
            $Settings = @{ remediate = $true; customGroup = 'SG-%sitecode%' }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            $script:CapturedSettings.customGroup | Should -Be 'SG-FAB01'
        }

        It 'writes a value containing a dollar sign through unmangled' {
            # -replace would otherwise read $& in the value as a substitution pattern.
            $Settings = [pscustomobject]@{ remediate = $true; sharePath = '%sharepath%' }

            Push-CIPPStandard -Item (New-QueueItem -Settings $Settings -Standard 'AntiPhishPolicy')

            $script:CapturedSettings.sharePath | Should -Be '\\srv\share$\folder'
        }
    }

    Context 'standards that no longer exist' {
        It 'logs a warning and does not invoke anything' {
            Mock -CommandName Get-Command -MockWith { $null } -ParameterFilter { $Module -contains 'CIPPStandards' }

            { Push-CIPPStandard -Item (New-QueueItem -Settings (New-TemplateSettings) -Standard 'RemovedStandard') } |
                Should -Not -Throw

            $script:CapturedSettings | Should -BeNullOrEmpty
            $script:LoggedWarnings -join ' ' | Should -BeLike '*RemovedStandard*deprecated*'
        }
    }

    Context 'error handling is unchanged' {
        It 'rethrows and logs when the standard itself fails' {
            $script:StandardShouldThrow = $true
            $Item = New-QueueItem -Settings (New-TemplateSettings)

            { Push-CIPPStandard -Item $Item } | Should -Throw -ExpectedMessage 'Graph exploded'
            $script:LoggedErrors | Should -Not -BeNullOrEmpty
            $script:LoggedErrors[0] | Should -BeLike '*Error running standard IntuneTemplate*'
        }

        It 'exits cleanly on a detected rerun without invoking the standard' {
            Mock -CommandName Test-CIPPRerun -MockWith { $true }

            Push-CIPPStandard -Item (New-QueueItem -Settings (New-TemplateSettings))

            $script:CapturedSettings | Should -BeNullOrEmpty
        }
    }
}
