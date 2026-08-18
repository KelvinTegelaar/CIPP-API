# Pester tests for Invoke-ListGuestUsers
# Validates lifecycle status classification, the sign-in date selection, the staleDays
# override, the fallback for tenants without an Entra ID P1 license, and the
# reporting-database cache branch.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListGuestUsers.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListGuestUsers.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception } }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $RequiredCapabilities, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$ComplexFilter) }
    function Get-CIPPGuestUsersReport { param($TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-GuestRequest {
        param([hashtable]$Query = @{})
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        foreach ($Key in $Query.Keys) { $Merged[$Key] = $Query[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListGuestUsers' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject]$Merged
        }
    }
}

Describe 'Invoke-ListGuestUsers' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { param($Exception) @{ NormalizedError = "$Exception" } }
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
    }

    It 'classifies each lifecycle status on the happy path' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                # Interactive sign-in is old, but the successful sign-in is recent - the most
                # recent of the three must win or this guest would be misreported as Stale.
                [pscustomobject]@{
                    id = 'g-active'; displayName = 'Active Guest'; mail = 'active@partner.com'
                    userPrincipalName = 'active_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-400).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = (Get-Date).AddDays(-399).ToString('o')
                    signInActivity = [pscustomobject]@{
                        lastSignInDateTime               = (Get-Date).AddDays(-120).ToString('o')
                        lastNonInteractiveSignInDateTime = $null
                        lastSuccessfulSignInDateTime     = (Get-Date).AddDays(-4).ToString('o')
                    }
                }
                [pscustomobject]@{
                    id = 'g-stale'; displayName = 'Stale Guest'; mail = 'stale@partner.com'
                    userPrincipalName = 'stale_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-400).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = [pscustomobject]@{
                        lastSignInDateTime               = (Get-Date).AddDays(-120).ToString('o')
                        lastNonInteractiveSignInDateTime = $null
                        lastSuccessfulSignInDateTime     = $null
                    }
                }
                [pscustomobject]@{
                    id = 'g-pending'; displayName = 'Pending Guest'; mail = 'pending@partner.com'
                    userPrincipalName = 'pending_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-10).ToString('o'); accountEnabled = $true
                    externalUserState = 'PendingAcceptance'; externalUserStateChangeDateTime = $null
                    signInActivity = $null
                }
                [pscustomobject]@{
                    id = 'g-never'; displayName = 'Never Guest'; mail = 'never@partner.com'
                    userPrincipalName = 'never_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-200).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = $null
                }
                # Disabled must win over PendingAcceptance.
                [pscustomobject]@{
                    id = 'g-disabled'; displayName = 'Disabled Guest'; mail = $null
                    userPrincipalName = 'disabled_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-200).ToString('o'); accountEnabled = $false
                    externalUserState = 'PendingAcceptance'; externalUserStateChangeDateTime = $null
                    signInActivity = $null
                }
            )
        }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 5
        $ByStatus = @{}
        foreach ($Row in $response.Body) { $ByStatus[$Row.id] = $Row }
        $ByStatus['g-active'].status | Should -Be 'Active'
        $ByStatus['g-stale'].status | Should -Be 'Stale'
        $ByStatus['g-pending'].status | Should -Be 'Pending Acceptance'
        $ByStatus['g-never'].status | Should -Be 'Never Signed In'
        $ByStatus['g-disabled'].status | Should -Be 'Disabled'

        # The reported last sign-in is the most recent of the three signInActivity fields.
        $ByStatus['g-active'].daysSinceSignIn | Should -Be 4
        ([datetime]$ByStatus['g-active'].lastSignInDateTime).Date | Should -Be (Get-Date).AddDays(-4).Date
        $ByStatus['g-stale'].daysSinceSignIn | Should -Be 120
        $ByStatus['g-never'].lastSignInDateTime | Should -BeNullOrEmpty

        $ByStatus['g-active'].sourceDomain | Should -Be 'partner.com'
        $ByStatus['g-disabled'].sourceDomain | Should -BeNullOrEmpty

        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter {
            $uri -like "*userType eq 'Guest'*" -and $uri -like '*signInActivity*' -and $uri -like '*$top=500*' -and $tenantid -eq 'contoso.onmicrosoft.com' -and $ComplexFilter
        }
    }

    It 'honours the staleDays override' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    id = 'g-1'; displayName = 'Guest'; mail = 'g@partner.com'
                    userPrincipalName = 'g_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-100).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = [pscustomobject]@{
                        lastSignInDateTime               = (Get-Date).AddDays(-4).ToString('o')
                        lastNonInteractiveSignInDateTime = $null
                        lastSuccessfulSignInDateTime     = $null
                    }
                }
            )
        }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest -Query @{ staleDays = '1' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body[0].status | Should -Be 'Stale'
    }

    It 'lists without signInActivity and reports Unknown on tenants without Entra P1' {
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    id = 'g-accepted'; displayName = 'Accepted Guest'; mail = 'a@partner.com'
                    userPrincipalName = 'a_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-100).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                }
                [pscustomobject]@{
                    id = 'g-pending'; displayName = 'Pending Guest'; mail = 'p@partner.com'
                    userPrincipalName = 'p_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-10).ToString('o'); accountEnabled = $true
                    externalUserState = 'PendingAcceptance'; externalUserStateChangeDateTime = $null
                }
            )
        }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $ByStatus = @{}
        foreach ($Row in $response.Body) { $ByStatus[$Row.id] = $Row }
        # Without sign-in data there is no way to tell Active from Stale - never guess.
        $ByStatus['g-accepted'].status | Should -Be 'Unknown'
        $ByStatus['g-pending'].status | Should -Be 'Pending Acceptance'

        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter {
            $uri -notlike '*signInActivity*' -and $uri -like '*$top=999*'
        }
    }

    It 'returns InternalServerError and logs when Graph fails' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Graph exploded' }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body[0].Error | Should -Match 'Graph exploded'
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'serves classified rows from the report cache when UseReportDB is true' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'live Graph should not be called' }
        Mock -CommandName Get-CIPPGuestUsersReport -MockWith {
            @(
                # Capable tenant, recent sign-in - Active, with sponsors joined for display
                [pscustomobject]@{
                    id = 'g-active'; displayName = 'Active Guest'; mail = 'active@partner.com'
                    userPrincipalName = 'active_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-400).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = [pscustomobject]@{
                        lastSignInDateTime               = (Get-Date).AddDays(-4).ToString('o')
                        lastNonInteractiveSignInDateTime = $null
                        lastSuccessfulSignInDateTime     = $null
                    }
                    signInLogsCapable = $true
                    sponsors = @(
                        [pscustomobject]@{ displayName = 'Sponsor One' }
                        [pscustomobject]@{ userPrincipalName = 'two@partner.com' }
                    )
                    CacheTimestamp = '2026-08-18T10:00:00Z'
                }
                # Capable tenant, no sign-in data - genuinely never signed in
                [pscustomobject]@{
                    id = 'g-never'; displayName = 'Never Guest'; mail = 'never@partner.com'
                    userPrincipalName = 'never_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-200).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = $null; signInLogsCapable = $true; sponsors = $null
                    CacheTimestamp = '2026-08-18T10:00:00Z'
                }
                # Not capable at cache time - sign-in state cannot be known
                [pscustomobject]@{
                    id = 'g-unknown'; displayName = 'Unknown Guest'; mail = 'u@partner.com'
                    userPrincipalName = 'u_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-200).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                    signInActivity = $null; signInLogsCapable = $false; sponsors = $null
                    CacheTimestamp = '2026-08-18T10:00:00Z'
                }
                # Legacy cache row without the capability stamp - never guess sign-in state
                [pscustomobject]@{
                    id = 'g-legacy'; displayName = 'Legacy Guest'; mail = 'l@partner.com'
                    userPrincipalName = 'l_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-200).ToString('o'); accountEnabled = $true
                    externalUserState = 'Accepted'; externalUserStateChangeDateTime = $null
                }
            )
        }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest -Query @{ UseReportDB = 'true' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $ByStatus = @{}
        foreach ($Row in $response.Body) { $ByStatus[$Row.id] = $Row }
        $ByStatus['g-active'].status | Should -Be 'Active'
        $ByStatus['g-active'].sponsors | Should -Be 'Sponsor One, two@partner.com'
        $ByStatus['g-active'].CacheTimestamp | Should -Be '2026-08-18T10:00:00Z'
        $ByStatus['g-never'].status | Should -Be 'Never Signed In'
        $ByStatus['g-unknown'].status | Should -Be 'Unknown'
        $ByStatus['g-legacy'].status | Should -Be 'Unknown'

        Should -Invoke Get-CIPPGuestUsersReport -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.onmicrosoft.com' }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'always uses the report cache for AllTenants and passes Tenant through' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'live Graph should not be called' }
        Mock -CommandName Get-CIPPGuestUsersReport -MockWith {
            @(
                [pscustomobject]@{
                    id = 'g-1'; displayName = 'Guest'; mail = 'g@partner.com'
                    userPrincipalName = 'g_partner.com#EXT#@contoso.onmicrosoft.com'
                    createdDateTime = (Get-Date).AddDays(-10).ToString('o'); accountEnabled = $true
                    externalUserState = 'PendingAcceptance'; externalUserStateChangeDateTime = $null
                    signInLogsCapable = $true
                    CacheTimestamp = '2026-08-18T10:00:00Z'; Tenant = 'contoso.onmicrosoft.com'
                }
            )
        }

        $response = Invoke-ListGuestUsers -Request (New-GuestRequest -Query @{ tenantFilter = 'AllTenants' }) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body[0].status | Should -Be 'Pending Acceptance'
        $response.Body[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
        Should -Invoke Get-CIPPGuestUsersReport -Times 1 -ParameterFilter { $TenantFilter -eq 'AllTenants' }
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
