BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp) }
    function Get-CIPPBecRogueAppFeed { param($MaxAgeHours, [switch]$Force) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecUserGrants.ps1')

    $script:Heuristics = [pscustomobject]@{
        riskyScopes = [pscustomobject]@{
            regex        = '(?i)(\.ReadWrite(\.All)?$|\.All$|Mail\.|Files\.|Directory\.|RoleManagement\.|offline_access)'
            catalogNames = @('EWS.AccessAsUser.All')
        }
    }
    $script:CatalogAppId = '2ef68ccc-8a4d-42ff-ae88-2d7bb89ad139'
    $script:Feed = [pscustomobject]@{
        Apps              = @{ $script:CatalogAppId = [pscustomobject]@{ Name = 'Mail_Backup'; Source = 'CIPP'; Categories = @('Mailbox exfiltration'); Description = 'x' } }
        HuntressAvailable = $true
    }
    $script:Sps = @{
        'sp-rogue'  = [pscustomobject]@{ id = 'sp-rogue'; appId = $script:CatalogAppId.ToUpperInvariant(); displayName = 'Mail_Backup'; publisherName = $null; verifiedPublisher = [pscustomobject]@{ verifiedPublisherId = $null }; appOwnerOrganizationId = 'aaaa'; accountEnabled = $true; createdDateTime = '2026-08-01T00:00:00Z' }
        'sp-shady'  = [pscustomobject]@{ id = 'sp-shady'; appId = '11111111-1111-1111-1111-111111111111'; displayName = 'Shady Sync'; publisherName = 'Shady Ltd'; verifiedPublisher = [pscustomobject]@{ verifiedPublisherId = $null }; appOwnerOrganizationId = 'bbbb'; accountEnabled = $true; createdDateTime = '2026-08-02T00:00:00Z' }
        'sp-ms'     = [pscustomobject]@{ id = 'sp-ms'; appId = '22222222-2222-2222-2222-222222222222'; displayName = 'Microsoft Teams'; publisherName = 'Microsoft'; verifiedPublisher = [pscustomobject]@{ verifiedPublisherId = 'ms' }; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; accountEnabled = $true; createdDateTime = '2020-01-01T00:00:00Z' }
        'sp-benign' = [pscustomobject]@{ id = 'sp-benign'; appId = '33333333-3333-3333-3333-333333333333'; displayName = 'Survey Tool'; publisherName = 'Survey Inc'; verifiedPublisher = [pscustomobject]@{ verifiedPublisherId = 'sv' }; appOwnerOrganizationId = 'cccc'; accountEnabled = $true; createdDateTime = '2026-08-03T00:00:00Z' }
        'sp-graph'  = [pscustomobject]@{ id = 'sp-graph'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'; publisherName = 'Microsoft'; verifiedPublisher = [pscustomobject]@{ verifiedPublisherId = 'ms' }; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; accountEnabled = $true; createdDateTime = '2020-01-01T00:00:00Z' }
    }

    # Fixture-driven stand-in for the Graph batch: grants/app roles come from script-scope fixtures,
    # service principal lookups resolve against $script:Sps.
    function Invoke-FakeBulk {
        param($Requests)
        foreach ($Request in $Requests) {
            switch -Wildcard ($Request.id) {
                'Grants' { [pscustomobject]@{ id = 'Grants'; status = $script:GrantStatus; body = [pscustomobject]@{ value = @($script:GrantsFixture); error = [pscustomobject]@{ message = 'grants failed' } } } }
                'AppRoles' { [pscustomobject]@{ id = 'AppRoles'; status = $script:AppRoleStatus; body = [pscustomobject]@{ value = @($script:AppRolesFixture); error = [pscustomobject]@{ message = 'roles failed' } } } }
                'sp*' {
                    $script:SpRequests.Add($Request)
                    $Ids = [regex]::Matches($Request.url, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
                    [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @($Ids | ForEach-Object { $script:Sps[$_] } | Where-Object { $_ }) } }
                }
            }
        }
    }
}

Describe 'Get-CIPPBecUserGrants' {
    BeforeEach {
        Mock Get-CIPPBecRogueAppFeed { $script:Feed }
        Mock New-GraphBulkRequest { Invoke-FakeBulk -Requests $Requests }
        $script:GrantsFixture = @()
        $script:AppRolesFixture = @()
        $script:GrantStatus = 200
        $script:AppRoleStatus = 200
        $script:SpRequests = [System.Collections.Generic.List[object]]::new()
    }

    It 'flags catalog matches, high-risk scopes from unverified publishers, and leaves Microsoft and verified apps alone' {
        $script:GrantsFixture = @(
            [pscustomobject]@{ id = 'g1'; clientId = 'sp-rogue'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'User.Read Mail.Read offline_access' }
            [pscustomobject]@{ id = 'g2'; clientId = 'sp-shady'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'Mail.ReadWrite offline_access' }
            [pscustomobject]@{ id = 'g3'; clientId = 'sp-ms'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'Files.ReadWrite.All offline_access' }
            [pscustomobject]@{ id = 'g4'; clientId = 'sp-benign'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'User.Read openid' }
        )
        $Result = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $Result.Complete | Should -BeTrue
        $Result.Data.Count | Should -Be 4
        $Rogue = $Result.Data | Where-Object { $_.Id -eq 'g1' }
        $Rogue.Risk | Should -Be 'CatalogMatch'
        $Rogue.Flagged | Should -BeTrue
        $Rogue.CatalogMatch.Name | Should -Be 'Mail_Backup'
        $Rogue.HighRiskScopes | Should -Contain 'Mail.Read'
        $Shady = $Result.Data | Where-Object { $_.Id -eq 'g2' }
        $Shady.Risk | Should -Be 'High'
        $Shady.Flagged | Should -BeTrue
        $Shady.PublisherVerified | Should -BeFalse
        $Ms = $Result.Data | Where-Object { $_.Id -eq 'g3' }
        $Ms.Risk | Should -Be 'Review'
        $Ms.Flagged | Should -BeFalse
        $Ms.IsMicrosoft | Should -BeTrue
        $Benign = $Result.Data | Where-Object { $_.Id -eq 'g4' }
        $Benign.Risk | Should -Be 'Low'
        $Benign.HighRiskScopes.Count | Should -Be 0
        $Result.Data[0].Flagged | Should -BeTrue -Because 'flagged rows sort first'
        $Result.Data[0].ResourceDisplayName | Should -Be 'Microsoft Graph'
    }

    It 'matches scope names from the RiskyPermissions catalog as well as the regex' {
        $script:GrantsFixture = @([pscustomobject]@{ id = 'g1'; clientId = 'sp-shady'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'EWS.AccessAsUser.All' })
        $Result = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $Result.Data[0].HighRiskScopes | Should -Contain 'EWS.AccessAsUser.All'
        $Result.Data[0].Risk | Should -Be 'High'
    }

    It 'flags an app role assignment to a catalog application' {
        $script:AppRolesFixture = @([pscustomobject]@{ id = 'a1'; resourceId = 'sp-rogue'; resourceDisplayName = 'Mail_Backup'; appRoleId = '00000000-0000-0000-0000-000000000000'; createdDateTime = '2026-08-10T00:00:00Z' })
        $Result = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $Result.Data.Count | Should -Be 1
        $Result.Data[0].Type | Should -Be 'AppRoleAssignment'
        $Result.Data[0].Risk | Should -Be 'CatalogMatch'
        $Result.Data[0].Flagged | Should -BeTrue
    }

    It 'reports a failed Graph query as incomplete instead of an empty grant list' {
        $script:GrantStatus = 403
        $Result = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Match 'grants failed'
        $Result.Data.Count | Should -Be 0
    }

    It 'resolves service principals in chunks of at most 15 ids' {
        $script:GrantsFixture = @(1..40 | ForEach-Object { [pscustomobject]@{ id = "g$_"; clientId = "sp-$_"; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'User.Read' } })
        $null = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $script:SpRequests.Count | Should -Be 3
        foreach ($Request in $script:SpRequests) {
            ([regex]::Matches($Request.url, "'([^']+)'").Count) | Should -BeLessOrEqual 15
        }
    }

    It 'fetches the rogue-app feed itself when none is supplied and still works when the feed is down' {
        Mock Get-CIPPBecRogueAppFeed { [pscustomobject]@{ Apps = @{}; HuntressAvailable = $false } }
        $script:GrantsFixture = @([pscustomobject]@{ id = 'g1'; clientId = 'sp-rogue'; resourceId = 'sp-graph'; consentType = 'Principal'; scope = 'User.Read' })
        $Result = Get-CIPPBecUserGrants -TenantFilter 'contoso.com' -UserId 'user-1' -Heuristics $script:Heuristics
        $Result.Data[0].CatalogMatch | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPBecRogueAppFeed -Times 1
    }
}
