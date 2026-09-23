BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $AsApp, $body) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $Sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Remove-CIPPBecSharingLinks.ps1')

    # A drive item carrying every permission shape: an anonymous link, an org link, a direct user grant
    # (no .link), and an inherited link. Only the two own link permissions should be deleted.
    $script:ItemWithLinks = {
        [pscustomobject]@{
            id              = 'item1'
            name            = 'payroll.xlsx'
            parentReference = [pscustomobject]@{ driveId = 'drive1' }
            permissions     = @(
                [pscustomobject]@{ id = 'perm-anon'; link = [pscustomobject]@{ scope = 'anonymous' } }
                [pscustomobject]@{ id = 'perm-org'; link = [pscustomobject]@{ scope = 'organization' } }
                [pscustomobject]@{ id = 'perm-user'; grantedToV2 = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1' } } }
                [pscustomobject]@{ id = 'perm-inherited'; link = [pscustomobject]@{ scope = 'anonymous' }; inheritedFrom = [pscustomobject]@{ id = 'root' } }
            )
        }
    }
}

Describe 'Remove-CIPPBecSharingLinks' {
    BeforeEach {
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
    }

    It 'resolves each URL through the shares endpoint and deletes only the own link permissions' {
        Mock New-GraphGetRequest { & $script:ItemWithLinks }
        $Rows = Remove-CIPPBecSharingLinks -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -ItemUrls @('https://contoso-my.sharepoint.com/personal/victim/Documents/payroll.xlsx')

        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like 'https://graph.microsoft.com/v1.0/shares/u!*/driveItem*' }
        # the direct grant and the inherited link are left alone
        Should -Invoke New-GraphPostRequest -Times 2 -ParameterFilter { $type -eq 'DELETE' }
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*/drives/drive1/items/item1/permissions/perm-anon' }
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $uri -like '*/permissions/perm-org' }
        Should -Invoke New-GraphPostRequest -Times 0 -ParameterFilter { $uri -like '*perm-user' -or $uri -like '*perm-inherited' }
        @($Rows | Where-Object { $_.state -eq 'success' }).Count | Should -Be 2
    }

    It 'de-duplicates repeated URLs so a link is only resolved once' {
        Mock New-GraphGetRequest { & $script:ItemWithLinks }
        $null = Remove-CIPPBecSharingLinks -TenantFilter 'contoso.com' -ItemUrls @('https://x/a', 'https://x/a', 'https://x/a')
        Should -Invoke New-GraphGetRequest -Times 1
    }

    It 'returns an info row and deletes nothing when the item has no link permissions' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'i'; name = 'clean.txt'; parentReference = [pscustomobject]@{ driveId = 'd' }; permissions = @([pscustomobject]@{ id = 'g'; grantedToV2 = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u' } } }) } }
        $Rows = Remove-CIPPBecSharingLinks -TenantFilter 'contoso.com' -ItemUrls @('https://x/clean.txt')
        $Rows[0].state | Should -Be 'info'
        Should -Invoke New-GraphPostRequest -Times 0
    }

    It 'returns an error row when the item cannot be resolved' {
        Mock New-GraphGetRequest { throw 'Item not found' }
        $Rows = Remove-CIPPBecSharingLinks -TenantFilter 'contoso.com' -ItemUrls @('https://x/gone.txt')
        $Rows[0].state | Should -Be 'error'
        $Rows[0].resultText | Should -Match 'Item not found'
    }

    It 'keeps going to the next URL when one delete fails' {
        Mock New-GraphGetRequest { & $script:ItemWithLinks }
        Mock New-GraphPostRequest { throw 'Access denied' }
        $Rows = Remove-CIPPBecSharingLinks -TenantFilter 'contoso.com' -ItemUrls @('https://x/a')
        @($Rows | Where-Object { $_.state -eq 'error' }).Count | Should -Be 2
        $Rows[0].resultText | Should -Match 'Access denied'
    }
}
