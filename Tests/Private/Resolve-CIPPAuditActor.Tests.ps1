BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/Resolve-CIPPAuditActor.ps1')
    $script:OriginalAppId = $env:ApplicationID
    $script:OriginalTenantId = $env:TenantID
    $env:ApplicationID = '11111111-2222-4333-8444-555555555555'
    $env:TenantID = '99999999-8888-4777-8666-555555555555'
    # partner-tenant object id 0123abcd-4567-4890-8abc-def012345678, as it appears without dashes in Entra records
    $script:Lookup = @{ '0123abcd-4567-4890-8abc-def012345678' = @{ userPrincipalName = 'tech@msp.example'; displayName = 'Tech' } }
}

AfterAll {
    $env:ApplicationID = $script:OriginalAppId
    $env:TenantID = $script:OriginalTenantId
}

Describe 'Resolve-CIPPAuditActor' {
    It 'leaves an ordinary user principal name as the tenant''s own user' {
        $R = Resolve-CIPPAuditActor -Actor 'victim@contoso.com' -PartnerUserLookup $script:Lookup
        $R.Kind | Should -Be 'User'
        $R.Actor | Should -Be 'victim@contoso.com'
        $R.PartnerTenantId | Should -BeNullOrEmpty
    }

    It 'resolves the Entra partner shape (user_<id>@tenant) to the partner user' {
        $R = Resolve-CIPPAuditActor -Actor 'user_0123abcd456748908abcdef012345678@contoso.onmicrosoft.com' -PartnerUserLookup $script:Lookup
        $R.Kind | Should -Be 'Partner'
        $R.Actor | Should -Be 'tech@msp.example'
    }

    It 'calls an unknown id in the partner shape another partner when this partner''s users are known' {
        $R = Resolve-CIPPAuditActor -Actor 'user_ffffffffffff4fff8fffffffffffffff@contoso.onmicrosoft.com' -PartnerUserLookup $script:Lookup
        $R.Kind | Should -Be 'OtherPartner'
        $R.Actor | Should -Be 'user_ffffffffffff4fff8fffffffffffffff@contoso.onmicrosoft.com'
        # without a lookup the shape alone still says partner, and nothing can say which
        (Resolve-CIPPAuditActor -Actor 'user_ffffffffffff4fff8fffffffffffffff@contoso.onmicrosoft.com').Kind | Should -Be 'Partner'
    }

    It 'tells this partner tenant from another by the tenant id in the Exchange shape' {
        $Mine = Resolve-CIPPAuditActor -Actor 'contoso.onmicrosoft.com\tenant: 99999999-8888-4777-8666-555555555555, object: 0123abcd-4567-4890-8abc-def012345678' -PartnerUserLookup $script:Lookup
        $Mine.Kind | Should -Be 'Partner'
        $Mine.Actor | Should -Be 'tech@msp.example'
        $Mine.PartnerTenantId | Should -Be '99999999-8888-4777-8666-555555555555'

        $Other = Resolve-CIPPAuditActor -Actor 'contoso.onmicrosoft.com\tenant: 12345678-1234-4123-8123-123456789012, object: 0123abcd-4567-4890-8abc-def012345678' -PartnerUserLookup $script:Lookup
        $Other.Kind | Should -Be 'OtherPartner'
        $Other.PartnerTenantId | Should -Be '12345678-1234-4123-8123-123456789012'
    }

    It 'recognises CIPP''s own application by app id, in either position' {
        (Resolve-CIPPAuditActor -Actor 'CIPP-SAM' -ActorType 'Application' -AppId '11111111-2222-4333-8444-555555555555').Kind | Should -Be 'CIPP'
        (Resolve-CIPPAuditActor -Actor '11111111-2222-4333-8444-555555555555').Kind | Should -Be 'CIPP'
        (Resolve-CIPPAuditActor -Actor 'CIPP-SAM' -ActorType 'Application' -AppId '11111111-2222-4333-8444-555555555555').Actor | Should -Be 'CIPP (service principal)'
    }

    It 'classifies other applications, system accounts and empty actors without guessing' {
        $App = Resolve-CIPPAuditActor -Actor 'Sync Tool' -ActorType 'Application' -AppId 'app-1'
        $App.Kind | Should -Be 'Application'
        $App.Actor | Should -Be 'Sync Tool'
        (Resolve-CIPPAuditActor -Actor 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee').Kind | Should -Be 'Application'
        (Resolve-CIPPAuditActor -Actor 'NT AUTHORITY\SYSTEM (Microsoft.Exchange.ServiceHost)').Kind | Should -Be 'System'
        (Resolve-CIPPAuditActor -Actor '').Kind | Should -Be 'User'
    }
}
