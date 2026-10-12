BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) $true }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox) }
    function Get-CippTable { param($tablename) @{} }
    function Get-AzDataTableEntity { param($Filter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Get-NormalizedError { param($Message) $Message }
    function Set-CIPPStandardsCompareField { param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPTransportRuleTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardTransportRuleTemplate.ps1')
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardTransportRuleTemplate variables' {
    BeforeEach {
        Mock Get-CIPPTextReplacement { $Text -replace '%tenantname%', 'Contoso' }
        Mock Get-AzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-1'; JSON = '{"name":"%tenantname% external tag","PrependSubject":"[%tenantname%] "}' } }
        Mock Set-CIPPStandardsCompareField { }
        $script:Settings = [pscustomobject]@{ transportRuleTemplate = @([pscustomobject]@{ value = 'tpl-1' }); remediate = $true; report = $true; overwrite = $false }
    }

    It 'creates the rule with the resolved name and text' {
        Mock New-ExoRequest { @() } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        Mock New-ExoRequest { }
        Invoke-CIPPStandardTransportRuleTemplate -Tenant $script:Tenant -Settings $script:Settings
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'New-TransportRule' -and $cmdParams.name -eq 'Contoso external tag' -and $cmdParams.PrependSubject -eq '[Contoso] '
        }
    }

    It 'reports a rule deployed under the resolved name as compliant' {
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'Contoso external tag'; DisplayName = 'Contoso external tag' }) } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        Mock New-ExoRequest { }
        Invoke-CIPPStandardTransportRuleTemplate -Tenant $script:Tenant -Settings $script:Settings
        Should -Invoke New-ExoRequest -Times 0 -Exactly -ParameterFilter { $cmdlet -eq 'New-TransportRule' }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($CurrentValue.MissingTransportRules).Count -eq 0 -and @($CurrentValue.DeployedTransportRules) -contains 'Contoso external tag'
        }
    }

    It 'overwrites an existing rule without Enabled and applies the state with <Expected>' -ForEach @(
        @{ Enabled = 'true'; Expected = 'Enable-TransportRule' }
        @{ Enabled = 'false'; Expected = 'Disable-TransportRule' }
    ) {
        Mock Get-AzDataTableEntity { [pscustomobject]@{ RowKey = 'tpl-1'; JSON = "{`"name`":`"Tag`",`"PrependSubject`":`"[EXT] `",`"Enabled`":$Enabled}" } }
        Mock New-ExoRequest { @([pscustomobject]@{ Identity = 'Tag'; DisplayName = 'Tag' }) } -ParameterFilter { $cmdlet -eq 'Get-TransportRule' }
        Mock New-ExoRequest { }
        $script:Settings.overwrite = $true
        Invoke-CIPPStandardTransportRuleTemplate -Tenant $script:Tenant -Settings $script:Settings
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter {
            $cmdlet -eq 'Set-TransportRule' -and $cmdParams.PSObject.Properties.Name -notcontains 'Enabled' -and $cmdParams.Identity -eq 'Tag'
        }
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq $Expected -and $cmdParams.Identity -eq 'Tag' }
    }
}

