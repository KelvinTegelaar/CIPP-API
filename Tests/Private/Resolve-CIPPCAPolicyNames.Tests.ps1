# Pester tests for Resolve-CIPPCAPolicyNames: names resolve to tenant IDs, keywords and GUIDs pass through, misses throw.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAUserNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Convert-CIPPCAGroupNameToId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Resolve-CIPPCAPolicyNames.ps1')

    $script:LocationId = '11111111-1111-1111-1111-111111111111'
    $script:GroupId = '22222222-2222-2222-2222-222222222222'
    $script:UserId = '33333333-3333-3333-3333-333333333333'
    $script:OtherId = '44444444-4444-4444-4444-444444444444'

    function New-GraphGETRequest {
        [CmdletBinding()] param($uri, $tenantid, $asApp)
        $script:GraphGets.Add($uri)
        @([pscustomobject]@{ id = $script:LocationId; displayName = 'CT-CA-Anthropic' })
    }
    # Answers each per-name $filter request from a small directory, the way Graph would.
    $script:Directory = @{
        users  = @([pscustomobject]@{ id = $script:UserId; displayName = 'Break Glass' }, [pscustomobject]@{ id = $script:OtherId; displayName = "Pat O'Brien" },
            [pscustomobject]@{ id = '55555555-5555-5555-5555-555555555555'; displayName = 'Admin' }, [pscustomobject]@{ id = '66666666-6666-6666-6666-666666666666'; displayName = 'Admin' })
        groups = @([pscustomobject]@{ id = $script:GroupId; displayName = 'CA-Exclude' },
            [pscustomobject]@{ id = '77777777-7777-7777-7777-777777777777'; displayName = 'Shared' }, [pscustomobject]@{ id = '88888888-8888-8888-8888-888888888888'; displayName = 'Shared' })
    }
    function New-GraphBulkRequest {
        [CmdletBinding()] param($Requests, $tenantid, $asapp)
        $script:BulkRequests.Add(@($Requests.url))
        foreach ($Request in $Requests) {
            $Kind, $Query = $Request.url -split '\?', 2
            $Filter = [System.Uri]::UnescapeDataString(($Query -split '&')[0] -replace '^\$filter=')
            $Name = ($Filter -replace "^displayName eq '(.*)'$", '$1') -replace "''", "'"
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @($script:Directory[$Kind].Where({ $_.displayName -eq $Name })) } }
        }
    }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $Headers, $message, $sev, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    function New-Policy ([hashtable]$Locations, [hashtable]$Users) {
        [pscustomobject]@{
            displayName = 'CA100'
            conditions  = [pscustomobject]@{
                locations = if ($Locations) { [pscustomobject]$Locations }
                users     = [pscustomobject]($Users ?? @{ includeUsers = @('All') })
            }
        }
    }
}

Describe 'Resolve-CIPPCAPolicyNames' {
    BeforeEach {
        $script:GraphGets = [System.Collections.Generic.List[string]]::new()
        $script:BulkRequests = [System.Collections.Generic.List[object]]::new()
    }

    Context 'named locations' {
        It 'replaces a location name with the tenant location id' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('CT-CA-Anthropic') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:LocationId)
        }

        It 'passes All, AllTrusted and GUIDs through unchanged, alongside a resolved name' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('AllTrusted', $script:OtherId, 'CT-CA-Anthropic') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.locations.includeLocations) | Should -Be @('All')
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('AllTrusted', $script:OtherId, $script:LocationId)
        }

        It 'does not query the tenant when every location is already an id or keyword' {
            $Policy = New-Policy -Locations @{ includeLocations = @('All'); excludeLocations = @('AllTrusted', $script:OtherId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:GraphGets.Count | Should -Be 0
            $script:BulkRequests.Count | Should -Be 0
        }

        It 'uses supplied named locations instead of fetching them' {
            $Policy = New-Policy -Locations @{ includeLocations = @('Head Office') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -NamedLocations @([pscustomobject]@{ id = $script:OtherId; displayName = 'Head Office' })
            @($Policy.conditions.locations.includeLocations) | Should -Be @($script:OtherId)
            $script:GraphGets.Count | Should -Be 0
        }

        It 'matches the display name exactly, not as a pattern' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('CT-CA-*') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }

        It 'throws a not-found error naming a location the tenant does not have' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('Nowhere') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Named location 'Nowhere' used by policy 'CA100' was not found in contoso.com*"
        }

        It 'refuses a name two named locations share, and changes nothing' {
            $Shared = @([pscustomobject]@{ id = $script:LocationId; displayName = 'Office' }, [pscustomobject]@{ id = $script:OtherId; displayName = 'Office' })
            $Policy = New-Policy -Locations @{ excludeLocations = @('Office') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -NamedLocations $Shared } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Named location 'Office' matches 2 named locations in contoso.com*"
            @($Policy.conditions.locations.excludeLocations) | Should -Be @('Office')
        }

        It 'keeps the first match for a shared location name with -LocationsOnly, as template deploys always have' {
            $Shared = @([pscustomobject]@{ id = $script:LocationId; displayName = 'Office' }, [pscustomobject]@{ id = $script:OtherId; displayName = 'Office' })
            $Policy = New-Policy -Locations @{ excludeLocations = @('Office') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -NamedLocations $Shared -LocationsOnly
            @($Policy.conditions.locations.excludeLocations) | Should -Be @($script:LocationId)
        }

        It 'leaves users and groups alone with -LocationsOnly' {
            $Policy = New-Policy -Locations @{ excludeLocations = @('CT-CA-Anthropic') } -Users @{ excludeGroups = @('CA-Exclude') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' -LocationsOnly
            @($Policy.conditions.users.excludeGroups) | Should -Be @('CA-Exclude')
            $script:BulkRequests.Count | Should -Be 0
        }
    }

    Context 'users and groups' {
        It 'replaces group and user names with their ids' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeUsers = @('Break Glass'); excludeGroups = @('CA-Exclude', $script:OtherId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.users.includeUsers) | Should -Be @('All')
            @($Policy.conditions.users.excludeUsers) | Should -Be @($script:UserId)
            @($Policy.conditions.users.excludeGroups) | Should -Be @($script:GroupId, $script:OtherId)
        }

        It 'passes user keywords through when they sit next to a name' {
            $Policy = New-Policy -Users @{ excludeUsers = @('GuestsOrExternalUsers', 'Break Glass') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($Policy.conditions.users.excludeUsers) | Should -Be @('GuestsOrExternalUsers', $script:UserId)
        }

        It 'looks up each typed name with a displayName filter instead of listing the directory' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeGroups = @('CA-Exclude') }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:BulkRequests.Count | Should -Be 1
            @($script:BulkRequests[0]) | Should -Be @("groups?`$filter=$([System.Uri]::EscapeDataString("displayName eq 'CA-Exclude'"))&`$select=id,displayName")
        }

        It 'doubles a single quote in a name and asks for a repeated name once' {
            $Policy = New-Policy -Users @{ includeUsers = @("Pat O'Brien"); excludeUsers = @("Pat O'Brien") }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            @($script:BulkRequests[0]).Count | Should -Be 1
            $script:BulkRequests[0][0] | Should -BeLike "*$([System.Uri]::EscapeDataString("'Pat O''Brien'"))*"
            @($Policy.conditions.users.includeUsers) | Should -Be @($script:OtherId)
        }

        It 'refuses a user name two users share, and changes nothing' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeUsers = @('Admin') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "User 'Admin' matches 2 users in contoso.com*"
            @($Policy.conditions.users.excludeUsers) | Should -Be @('Admin')
        }

        It 'refuses a group name two groups share' {
            $Policy = New-Policy -Users @{ excludeGroups = @('Shared') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Group 'Shared' matches 2 groups in contoso.com*"
        }

        It 'stops with the Graph error when a lookup fails' {
            function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $tenantid, $asapp) @([pscustomobject]@{ id = 'groups-0'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }) }
            $Policy = New-Policy -Users @{ excludeGroups = @('CA-Exclude') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } | Should -Throw '*Insufficient privileges*'
        }

        It 'does not query the directory when every assignment is an id or keyword' {
            $Policy = New-Policy -Users @{ includeUsers = @('All'); excludeUsers = @($script:UserId); excludeGroups = @($script:GroupId) }
            Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com'
            $script:BulkRequests.Count | Should -Be 0
        }

        It 'throws a not-found error naming a group the tenant does not have, and creates nothing' {
            $Policy = New-Policy -Users @{ excludeGroups = @('No Such Group') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "Group 'No Such Group' not found in tenant contoso.com. Create the group first*"
        }

        It 'throws a not-found error naming a user the tenant does not have' {
            $Policy = New-Policy -Users @{ excludeUsers = @('Nobody') }
            { Resolve-CIPPCAPolicyNames -Policy $Policy -TenantFilter 'contoso.com' } |
                Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage "User 'Nobody' not found in tenant contoso.com*"
        }
    }
}
