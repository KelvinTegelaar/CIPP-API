# CrossTenantPartner is an instance standard: one partner tenant ID per instance. The hook
# pins how a partner's settings read (allowed/blocked only for all users AND all apps,
# inherit when the partner has no override, custom otherwise), and that an empty but
# collected cache is drift while an uncollected one is No Data. The shared writer pins the
# Graph bodies: inherit is a null override, trust merges with what is there, and a missing
# partner is created rather than patched.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type) }
    function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $headers) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineCrossTenantPartnerState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineCrossTenantPartner.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Set-CIPPCrossTenantAccess.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:PartnerId = '11111111-2222-3333-4444-555555555555'
    function New-Access { param($Access, $User = 'AllUsers', $App = 'AllApplications') [PSCustomObject]@{ usersAndGroups = [PSCustomObject]@{ accessType = $Access; targets = @([PSCustomObject]@{ target = $User }) }; applications = [PSCustomObject]@{ accessType = $Access; targets = @([PSCustomObject]@{ target = $App }) } } }
    $script:Partner = [PSCustomObject]@{
        tenantId                     = $script:PartnerId
        b2bCollaborationInbound      = New-Access 'allowed'
        b2bCollaborationOutbound     = New-Access 'blocked'
        b2bDirectConnectInbound      = New-Access 'allowed' -User 'group-id'
        b2bDirectConnectOutbound     = $null
        inboundTrust                 = [PSCustomObject]@{ isMfaAccepted = $true; isCompliantDeviceAccepted = $false; isHybridAzureADJoinedDeviceAccepted = $false }
        automaticUserConsentSettings = [PSCustomObject]@{ inboundAllowed = $null; outboundAllowed = $true }
    }
    function Invoke-Hook { param($Variables) Get-CIPPBaselineCrossTenantPartnerState -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant }
    function Get-PostBody { param($Type) $script:Posts.Where({ $_.type -eq $Type })[0].body | ConvertFrom-Json }
}

Describe 'Get-CIPPBaselineCrossTenantPartnerState' {
    BeforeEach {
        Mock Get-CIPPBaselineCacheRows { @($script:Partner) }
        Mock Test-CIPPBaselineCacheCollected { $true }
    }

    It 'reads all-users/all-apps access as allowed or blocked, targeted access as custom and no override as inherit' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ partnerTenantId = $script:PartnerId; b2bCollaborationInbound = 'allowed'; b2bCollaborationOutbound = 'allowed'; b2bDirectConnectInbound = 'allowed'; b2bDirectConnectOutbound = 'blocked' })
        $Prepared.Current.exists | Should -BeTrue
        $Prepared.Current.b2bCollaborationInbound | Should -Be 'allowed'
        $Prepared.Current.b2bCollaborationOutbound | Should -Be 'blocked'
        $Prepared.Current.b2bDirectConnectInbound | Should -Be 'custom'
        $Prepared.Current.b2bDirectConnectOutbound | Should -Be 'inherit'
    }

    It 'grades only the configured settings, unwrapping option objects' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ partnerTenantId = [PSCustomObject]@{ value = $script:PartnerId }; isMfaAccepted = [PSCustomObject]@{ label = 'Trust'; value = 'true' }; outboundAllowed = 'false' })
        @($Prepared.Expected.PSObject.Properties.Name) | Should -Be @('exists', 'isMfaAccepted', 'outboundAllowed')
        $Prepared.Expected.isMfaAccepted | Should -BeTrue
        $Prepared.Current.isMfaAccepted | Should -BeTrue
        $Prepared.Expected.outboundAllowed | Should -BeFalse
        $Prepared.Current.outboundAllowed | Should -BeTrue
    }

    It 'reads a partner without its own trust as inherit, so an explicit trust drifts' {
        $Inheriting = $script:Partner.PSObject.Copy()
        $Inheriting.inboundTrust = $null
        Mock Get-CIPPBaselineCacheRows { @($Inheriting) }
        $Prepared = Invoke-Hook ([PSCustomObject]@{ partnerTenantId = $script:PartnerId; isMfaAccepted = 'true' })
        $Prepared.Current.isMfaAccepted | Should -Be 'inherit'
    }

    It 'drifts on a missing partner when the cache was collected empty' {
        Mock Get-CIPPBaselineCacheRows { @() }
        $Prepared = Invoke-Hook ([PSCustomObject]@{ partnerTenantId = $script:PartnerId; isMfaAccepted = 'true' })
        $Prepared.Current.exists | Should -BeFalse
        $Prepared.Expected.exists | Should -BeTrue
    }

    It 'returns No Data when the cache was never collected' {
        Mock Get-CIPPBaselineCacheRows { @() }
        Mock Test-CIPPBaselineCacheCollected { $false }
        (Invoke-Hook ([PSCustomObject]@{ partnerTenantId = $script:PartnerId })).Current | Should -BeNullOrEmpty
    }

    It 'returns a config error for a partner that is not a tenant ID' {
        $Prepared = Invoke-Hook ([PSCustomObject]@{ partnerTenantId = 'contoso.com' })
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.ConfigError | Should -BeTrue
        $Prepared.NoDataReason | Should -Match 'not a tenant ID'
    }
}

Describe 'Set-CIPPCrossTenantAccess' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphPostRequest { $script:Posts.Add([PSCustomObject]@{ uri = $uri; type = $type; body = $body; AsApp = $AsApp }) }
        Mock New-GraphGetRequest {
            if ($uri -like '*/partners') { @($script:Partner) }
            else { [PSCustomObject]@{ inboundTrust = [PSCustomObject]@{ isMfaAccepted = $false; isCompliantDeviceAccepted = $true; isHybridAzureADJoinedDeviceAccepted = $true } } }
        }
    }

    It 'patches an existing partner with all-users/all-apps access, a null override for inherit, and merged trust' {
        $Result = Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{ b2bCollaborationInbound = 'blocked'; b2bDirectConnectInbound = 'inherit'; isCompliantDeviceAccepted = 'true' }
        $Result | Should -Match 'Updated partner'
        $script:Posts.Count | Should -Be 1
        $script:Posts[0].uri | Should -Be "https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners/$($script:PartnerId)"
        $script:Posts[0].AsApp | Should -BeTrue
        $Body = Get-PostBody 'PATCH'
        $Body.b2bCollaborationInbound.usersAndGroups.accessType | Should -Be 'blocked'
        $Body.b2bCollaborationInbound.usersAndGroups.targets[0].target | Should -Be 'AllUsers'
        $Body.b2bCollaborationInbound.applications.targets[0].target | Should -Be 'AllApplications'
        $Body.PSObject.Properties.Name | Should -Contain 'b2bDirectConnectInbound'
        $Body.b2bDirectConnectInbound | Should -BeNullOrEmpty
        $Body.inboundTrust.isMfaAccepted | Should -BeTrue
        $Body.inboundTrust.isCompliantDeviceAccepted | Should -BeTrue
        $Body.inboundTrust.isHybridAzureADJoinedDeviceAccepted | Should -BeFalse
        $Body.PSObject.Properties.Name | Should -Not -Contain 'automaticUserConsentSettings'
    }

    It 'creates a missing partner, starting its trust from the default settings' {
        Mock New-GraphGetRequest {
            if ($uri -like '*/partners') { @() }
            else { [PSCustomObject]@{ inboundTrust = [PSCustomObject]@{ isMfaAccepted = $false; isCompliantDeviceAccepted = $true; isHybridAzureADJoinedDeviceAccepted = $true } } }
        }
        $Result = Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{ isMfaAccepted = $true; inboundAllowed = 'true' }
        $Result | Should -Match 'Added partner'
        $script:Posts[0].uri | Should -Be 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners'
        $Body = Get-PostBody 'POST'
        $Body.tenantId | Should -Be $script:PartnerId
        $Body.inboundTrust.isMfaAccepted | Should -BeTrue
        $Body.inboundTrust.isCompliantDeviceAccepted | Should -BeTrue
        $Body.automaticUserConsentSettings.inboundAllowed | Should -BeTrue
        $Body.automaticUserConsentSettings.outboundAllowed | Should -BeFalse
    }

    It 'keeps the other redemption direction and reads the string false as false' {
        Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{ inboundAllowed = 'false' }
        $Body = Get-PostBody 'PATCH'
        $Body.automaticUserConsentSettings.inboundAllowed | Should -BeFalse
        $Body.automaticUserConsentSettings.outboundAllowed | Should -BeTrue
    }

    It 'clears the partner trust on inboundTrust inherit' {
        Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{ inboundTrust = 'inherit' }
        $Body = Get-PostBody 'PATCH'
        $Body.PSObject.Properties.Name | Should -Contain 'inboundTrust'
        $Body.inboundTrust | Should -BeNullOrEmpty
    }

    It 'patches the default settings without reading partners' {
        $Result = Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -Settings @{ b2bDirectConnectOutbound = 'allowed'; isMfaAccepted = 'true' }
        $Result | Should -Match 'default'
        $script:Posts[0].uri | Should -Be 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default'
        $Body = Get-PostBody 'PATCH'
        $Body.b2bDirectConnectOutbound.applications.accessType | Should -Be 'allowed'
        $Body.inboundTrust.isMfaAccepted | Should -BeTrue
        $Body.inboundTrust.isCompliantDeviceAccepted | Should -BeTrue
        Should -Invoke New-GraphGetRequest -Times 0 -ParameterFilter { $uri -like '*/partners' }
    }

    It 'refuses partner-only settings on the default, unknown access values, bad ids and empty changes' {
        { Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -Settings @{ b2bCollaborationInbound = 'inherit' } } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -Settings @{ inboundAllowed = 'true' } } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{ b2bCollaborationInbound = 'custom' } } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId 'contoso.com' -Settings @{ isMfaAccepted = 'true' } } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Set-CIPPCrossTenantAccess -TenantFilter $script:Tenant -PartnerTenantId $script:PartnerId -Settings @{} } | Should -Throw -ExceptionType ([System.ArgumentException])
        $script:Posts.Count | Should -Be 0
    }
}

Describe 'Invoke-CIPPBaselineCrossTenantPartner' {
    BeforeEach {
        Mock Set-CIPPCrossTenantAccess { 'ok' }
    }

    It 'passes only the configured settings, unwrapped' {
        $Remediate = [PSCustomObject]@{ partnerTenantId = $script:PartnerId; isMfaAccepted = [PSCustomObject]@{ value = 'true' }; b2bCollaborationOutbound = 'blocked' }
        Invoke-CIPPBaselineCrossTenantPartner -Remediate $Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ exists = $true })
        Should -Invoke Set-CIPPCrossTenantAccess -Times 1 -Exactly -ParameterFilter {
            $PartnerTenantId -eq $script:PartnerId -and $Settings.Count -eq 2 -and $Settings.isMfaAccepted -eq 'true' -and $Settings.b2bCollaborationOutbound -eq 'blocked'
        }
    }

    It 'still creates a missing partner when only the partner is configured' {
        Invoke-CIPPBaselineCrossTenantPartner -Remediate ([PSCustomObject]@{ partnerTenantId = $script:PartnerId }) -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ exists = $false })
        Should -Invoke Set-CIPPCrossTenantAccess -Times 1 -Exactly -ParameterFilter { $Settings.Count -eq 1 -and $Settings.b2bCollaborationInbound -eq 'inherit' }
    }
}
