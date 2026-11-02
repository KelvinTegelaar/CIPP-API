# Pester tests for the optional single-method filter and UPN encoding on Remove-CIPPUserMFA.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Remove-CIPPUserMFA.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $AsApp) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
}

Describe 'Remove-CIPPUserMFA -MethodId' {
    BeforeEach {
        $script:deletedUris = [System.Collections.Generic.List[string]]::new()

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.passwordAuthenticationMethod'; id = 'pwd-id' }
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.phoneAuthenticationMethod'; id = 'phone-id' }
                [pscustomobject]@{ '@odata.type' = '#microsoft.graph.fido2AuthenticationMethod'; id = 'fido-id' }
            )
        }
        Mock -CommandName New-GraphPOSTRequest -MockWith { $script:deletedUris.Add($uri) }
        Mock -CommandName Write-LogMessage -MockWith {}
    }

    It 'deletes only the requested method when MethodId is supplied' {
        $Result = Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com' -MethodId 'fido-id'

        $script:deletedUris.Count | Should -Be 1
        $script:deletedUris[0] | Should -Be 'https://graph.microsoft.com/v1.0/users/user%40contoso.com/authentication/fido2Methods/fido-id'
        $Result | Should -BeLike 'Successfully removed MFA method*'
    }

    It 'encodes a guest UPN so the #EXT# fragment does not truncate the Graph path' {
        $null = Remove-CIPPUserMFA -UserPrincipalName 'alice_fabrikam.com#EXT#@contoso.onmicrosoft.com' -TenantFilter 'contoso.com' -MethodId 'fido-id'

        $script:deletedUris[0] | Should -Be 'https://graph.microsoft.com/v1.0/users/alice_fabrikam.com%23EXT%23%40contoso.onmicrosoft.com/authentication/fido2Methods/fido-id'
        $script:deletedUris[0] | Should -Not -Match '#'
    }

    It 'deletes every removable method when MethodId is omitted' {
        $null = Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com'

        $script:deletedUris.Count | Should -Be 2
    }

    It 'never deletes the password method' {
        $null = Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com' -MethodId 'pwd-id'

        $script:deletedUris.Count | Should -Be 0
    }

    It 'reports the unknown id when MethodId matches nothing' {
        $Result = Remove-CIPPUserMFA -UserPrincipalName 'user@contoso.com' -TenantFilter 'contoso.com' -MethodId 'does-not-exist'

        $script:deletedUris.Count | Should -Be 0
        $Result | Should -BeLike '*does-not-exist*'
    }
}
