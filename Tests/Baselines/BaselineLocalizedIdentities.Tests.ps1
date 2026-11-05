# Declarative definitions must not hardcode English object names (they do not exist in
# localized tenants), and the two Authenticator feature standards must write through the
# read-modify-write helper so they do not reset each other.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, [switch]$Compliance) }
    function Set-CIPPAuthenticationPolicy { param($Tenant, $APIName, $AuthenticationMethodId, $Enabled, $MicrosoftAuthenticatorCompanionApp, $MicrosoftAuthenticatorDisplayAppInfo) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }

    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoRequest.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineAuthenticationPolicy.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Spec { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }
    function Get-Definition { param($Path) Get-Content -Raw (Join-Path $script:RepoRoot "Config/BaselineStandards/$Path") | ConvertFrom-Json }
}

Describe 'Invoke-CIPPBaselineExoRequest read-record tokens' {
    BeforeEach { Mock New-ExoRequest {} }

    It 'resolves a token from a single read record' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-SharingPolicy'; params = @{ Identity = '%Id%'; Enabled = $false } }) } | ConvertTo-Spec
        $Record = [PSCustomObject]@{ Id = 'Standardfreigaberichtlinie'; Default = $true }
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $Record
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdParams.Identity -eq 'Standardfreigaberichtlinie' -and $cmdParams.Enabled -eq $false }
    }

    It 'leaves a step without tokens unchanged, whatever Current is' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-Thing'; params = @{ Identity = 'Default'; Count = 3 } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current @()
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter { $cmdParams.Identity -eq 'Default' -and $cmdParams.Count -eq 3 }
    }

    It 'throws on an unresolved token when the read returned no record' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-Thing'; params = @{ Identity = '%Id%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $null } | Should -Throw '*0 records*'
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'throws on an unresolved token when the read returned several records' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-Thing'; params = @{ Identity = '%Id%' } }) } | ConvertTo-Spec
        $Records = @([PSCustomObject]@{ Id = 'a' }, [PSCustomObject]@{ Id = 'b' })
        { Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current $Records } | Should -Throw '*2 records*'
        Should -Invoke New-ExoRequest -Times 0
    }

    It 'throws when the single record lacks the named property' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-Thing'; params = @{ Identity = '%Name%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ Id = 'a' }) } | Should -Throw '*unresolved*'
    }
}

Describe 'Invoke-CIPPBaselineAuthenticationPolicy' {
    BeforeEach { Mock Set-CIPPAuthenticationPolicy {}; Mock New-GraphGetRequest { [PSCustomObject]@{ state = 'disabled' } } }

    It 'splats the params and adds Tenant and APIName' {
        $Spec = @{ params = @{ AuthenticationMethodId = 'MicrosoftAuthenticator'; Enabled = $true; MicrosoftAuthenticatorDisplayAppInfo = 'enabled' } } | ConvertTo-Spec
        Invoke-CIPPBaselineAuthenticationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -ParameterFilter {
            $Tenant -eq $script:Tenant -and $APIName -eq 'Baselines' -and $AuthenticationMethodId -eq 'MicrosoftAuthenticator' -and
            $Enabled -eq $true -and $MicrosoftAuthenticatorDisplayAppInfo -eq 'enabled'
        }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'keeps the live method state when Enabled is omitted' {
        Mock New-GraphGetRequest { [PSCustomObject]@{ state = 'enabled' } }
        $Spec = @{ params = @{ AuthenticationMethodId = 'MicrosoftAuthenticator'; MicrosoftAuthenticatorCompanionApp = 'enabled' } } | ConvertTo-Spec
        Invoke-CIPPBaselineAuthenticationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -ParameterFilter { $Enabled -eq $true -and $MicrosoftAuthenticatorCompanionApp -eq 'enabled' }
    }

    It 'propagates a failed write' {
        Mock Set-CIPPAuthenticationPolicy { throw 'boom' }
        $Spec = @{ params = @{ AuthenticationMethodId = 'MicrosoftAuthenticator'; Enabled = $true } } | ConvertTo-Spec
        { Invoke-CIPPBaselineAuthenticationPolicy -Remediate $Spec -TenantFilter $script:Tenant -Current $null } | Should -Throw 'boom'
    }
}

Describe 'Definitions' {
    It 'writes the Authenticator feature settings through AuthenticationPolicy, not a partial PATCH' {
        foreach ($Name in 'PWcompanionAppAllowedState', 'PWdisplayAppInformationRequiredState') {
            $Definition = Get-Definition "Entra (AAD) Standards/$Name.json"
            $Definition.remediate.executor | Should -Be 'AuthenticationPolicy'
            (ConvertTo-Json -Depth 20 $Definition.remediate) | Should -Not -Match 'featureSettings'
        }
        (Get-Definition 'Entra (AAD) Standards/PWcompanionAppAllowedState.json').remediate.params.MicrosoftAuthenticatorCompanionApp | Should -Be '%state%'
        (Get-Definition 'Entra (AAD) Standards/PWdisplayAppInformationRequiredState.json').remediate.params.MicrosoftAuthenticatorDisplayAppInfo | Should -Be 'enabled'
    }

    It 'takes the policy identity from the read record, not an English name' {
        $Sharing = Get-Definition 'Exchange Standards/DisableExternalCalendarSharing.json'
        $Sharing.remediate.cmdlets[0].params.Identity | Should -Be '%Id%'
        $Zap = Get-Definition 'Defender Standards/TeamsZAP.json'
        $Zap.remediate.cmdlets[0].params.Identity | Should -Be '%Name%'
        foreach ($Definition in $Sharing, $Zap) {
            (ConvertTo-Json -Depth 20 $Definition.remediate) | Should -Not -Match 'Default (Sharing|Teams Protection) Policy'
            # A declared variable with the same name would be spliced before the executor sees it.
            @($Definition.variables.PSObject.Properties.Name) | Should -Not -Contain 'Id'
            @($Definition.variables.PSObject.Properties.Name) | Should -Not -Contain 'Name'
        }
    }
}
