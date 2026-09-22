# Pester tests for Grant-CippAppGraphConsent
# The tenant-wide (AllPrincipals) Graph consent primitive that makes Entra issue a refresh token
# for an MCP client app. Verifies it creates a grant when none exists, adds only the missing
# scopes to an existing one, is a no-op when everything is already consented, ignores per-user
# grants, and throws (rather than silently succeeding) when the app service principal is missing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Grant-CippAppGraphConsent.ps1'

    function New-GraphGetRequest { param($uri, $NoAuthCheck, $asapp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $NoAuthCheck, $asapp) }

    . $FunctionPath

    $script:GraphAppId = '00000003-0000-0000-c000-000000000000'
}

Describe 'Grant-CippAppGraphConsent' {
    BeforeEach {
        $script:AppId = '44444444-4444-4444-4444-444444444444'
        $script:ClientSpId = 'client-sp-id'
        $script:GraphSpId = 'graph-sp-id'
        $script:ExistingGrants = @()

        Mock -CommandName Start-Sleep -MockWith { }
        Mock -CommandName New-GraphPOSTRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -match [regex]::Escape("appId='$script:AppId'")) { return [PSCustomObject]@{ id = $script:ClientSpId } }
            if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
            if ($uri -match 'oauth2PermissionGrants') { return $script:ExistingGrants }
            return @()
        }
    }

    It 'creates an AllPrincipals grant for the requested scopes when none exists' {
        Grant-CippAppGraphConsent -AppId $script:AppId -Scopes @('openid', 'profile', 'offline_access')

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'POST' -and
            $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -and
            ($body | ConvertFrom-Json).consentType -eq 'AllPrincipals' -and
            ($body | ConvertFrom-Json).clientId -eq $script:ClientSpId -and
            ($body | ConvertFrom-Json).resourceId -eq $script:GraphSpId -and
            ($body | ConvertFrom-Json).scope -eq 'openid profile offline_access'
        }
    }

    It 'adds only the missing scopes to an existing grant' {
        $script:ExistingGrants = @([PSCustomObject]@{
                id          = 'grant-1'
                resourceId  = $script:GraphSpId
                consentType = 'AllPrincipals'
                scope       = 'openid User.Read'
            })

        Grant-CippAppGraphConsent -AppId $script:AppId -Scopes @('openid', 'profile', 'offline_access')

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and
            $uri -eq 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants/grant-1' -and
            ($body | ConvertFrom-Json).scope -eq 'offline_access openid profile User.Read'
        }
    }

    It 'does nothing when every requested scope is already consented' {
        $script:ExistingGrants = @([PSCustomObject]@{
                id          = 'grant-1'
                resourceId  = $script:GraphSpId
                consentType = 'AllPrincipals'
                scope       = 'openid profile offline_access User.Read'
            })

        $Result = Grant-CippAppGraphConsent -AppId $script:AppId -Scopes @('openid', 'profile', 'offline_access')

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
        $Result.Action | Should -Be 'nochange'
    }

    It 'ignores a per-user grant and creates the tenant-wide one' {
        $script:ExistingGrants = @([PSCustomObject]@{
                id          = 'grant-user'
                resourceId  = $script:GraphSpId
                consentType = 'Principal'
                scope       = 'openid profile offline_access'
            })

        Grant-CippAppGraphConsent -AppId $script:AppId -Scopes @('openid', 'profile', 'offline_access')

        Should -Invoke -CommandName New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' }
    }

    It 'throws when the app service principal cannot be found' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            if ($uri -match [regex]::Escape("appId='$script:GraphAppId'")) { return [PSCustomObject]@{ id = $script:GraphSpId } }
            return @()
        }

        { Grant-CippAppGraphConsent -AppId $script:AppId -Scopes @('offline_access') } | Should -Throw
        Should -Invoke -CommandName New-GraphPOSTRequest -Times 0 -Exactly
    }
}
