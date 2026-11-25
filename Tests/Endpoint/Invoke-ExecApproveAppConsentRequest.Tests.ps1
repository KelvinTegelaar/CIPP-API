# Pester tests for Invoke-ExecApproveAppConsentRequest.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function Add-CIPPDelegatedPermission { param($RequiredResourceAccess, $ApplicationId, $TenantFilter) }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApproveAppConsentRequest.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:App = '11111111-1111-1111-1111-111111111111'
    $script:Request = [pscustomobject]@{
        Params  = @{ CIPPEndpoint = 'ExecApproveAppConsentRequest' }
        Headers = @{}
        Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; appId = $script:App }
    }

    function Set-GraphMocks {
        param($ConsentType = 'Dynamic', [string[]]$Scopes = @('openid', 'User.Read'), $ServicePrincipal = ([pscustomobject]@{ id = 'sp' }), $Grants = @())
        $App = $script:App
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*appConsentRequests' } -MockWith {
            [pscustomobject]@{ appId = 'other'; consentType = 'Static'; pendingScopes = @([pscustomobject]@{ displayName = '.default' }) }
            [pscustomobject]@{ appId = $App; appDisplayName = 'Graph Explorer'; consentType = $ConsentType; pendingScopes = @($Scopes | ForEach-Object { [pscustomobject]@{ displayName = $_ } }) }
        }.GetNewClosure()
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*servicePrincipals*' } -MockWith { $ServicePrincipal }.GetNewClosure()
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*servicePrincipals(appId=*' } -MockWith { [pscustomobject]@{ id = 'graph' } }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*oauth2PermissionGrants' } -MockWith { $Grants }.GetNewClosure()
        Mock New-GraphPOSTRequest
        Mock Add-CIPPDelegatedPermission -MockWith { 'Successfully added permissions for Microsoft Graph' }
    }
}

Describe 'Invoke-ExecApproveAppConsentRequest' {
    It 'grants the requested scopes on Microsoft Graph through Add-CIPPDelegatedPermission' {
        Set-GraphMocks
        $Response = Invoke-ExecApproveAppConsentRequest -Request $script:Request
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Successfully added permissions for Microsoft Graph'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Add-CIPPDelegatedPermission -Times 1 -Exactly -ParameterFilter {
            $ApplicationId -eq $script:App -and $RequiredResourceAccess.resourceAppId -eq '00000003-0000-0000-c000-000000000000' -and
            ($RequiredResourceAccess.resourceAccess.id -join ' ') -eq 'openid User.Read' -and $RequiredResourceAccess.resourceAccess[0].type -eq 'Scope'
        }
    }

    It 'keeps the scopes already granted for all users' {
        Set-GraphMocks -Grants @(
            [pscustomobject]@{ consentType = 'Principal'; resourceId = 'graph'; scope = 'Files.Read' }
            [pscustomobject]@{ consentType = 'AllPrincipals'; resourceId = 'other'; scope = 'user_impersonation' }
            [pscustomobject]@{ consentType = 'AllPrincipals'; resourceId = 'graph'; scope = 'Mail.Read openid' }
        )
        (Invoke-ExecApproveAppConsentRequest -Request $script:Request).StatusCode | Should -Be 200
        Should -Invoke Add-CIPPDelegatedPermission -Times 1 -Exactly -ParameterFilter { ($RequiredResourceAccess.resourceAccess.id -join ' ') -eq 'Mail.Read openid User.Read' }
    }

    It 'creates the service principal when the app is not in the tenant yet' {
        Set-GraphMocks -ServicePrincipal $null
        (Invoke-ExecApproveAppConsentRequest -Request $script:Request).StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/servicePrincipals' -and $body -match $script:App }
    }

    It 'refuses a static request' {
        Set-GraphMocks -ConsentType 'Static' -Scopes '.default'
        (Invoke-ExecApproveAppConsentRequest -Request $script:Request).StatusCode | Should -Be 500
        Should -Invoke Add-CIPPDelegatedPermission -Times 0 -Exactly
    }
}
