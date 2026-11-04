# Pester tests for the federated credential support in Invoke-ExecManageAppCredentials, and for
# Get-CIPPAppFederatedCredential and Set-CIPPDBCacheAppFederatedCredentials, which feed the exposure report.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Get-Tenants { param($TenantFilter) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPAppFederatedCredential.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheAppFederatedCredentials.ps1')
    $Endpoint = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecManageAppCredentials.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    $script:AppObj = 'aaaaaaaa-0000-0000-0000-000000000001'
    $script:FicId = 'bbbbbbbb-0000-0000-0000-000000000002'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com'; Id = $script:AppObj; AppType = 'applications'; CredentialType = 'federated' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecManageAppCredentials' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]$Merged }
    }
    function Get-SentCredential { ConvertFrom-Json -InputObject $script:Posts[0].Body }
}

Describe 'Invoke-ExecManageAppCredentials federated credentials' {
    BeforeEach {
        $script:Posts = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphPOSTRequest { $script:Posts.Add([pscustomobject]@{ Uri = $uri; Type = $type; Body = $body }) }
        Mock Get-Tenants { [pscustomobject]@{ customerId = '11111111-2222-3333-4444-555555555555' } }
    }

    It 'builds a GitHub Actions credential for an environment, with the token exchange audience' {
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; Scenario = @{ value = 'GitHub' }; Name = 'deploy-prod'; GitHubOrganization = 'contoso'; GitHubRepository = 'infra'; GitHubEntityType = 'Environment'; GitHubEntityValue = 'production' })

        $Response.Body.Results.state | Should -Be 'success'
        $script:Posts[0].Uri | Should -Be "https://graph.microsoft.com/beta/applications/$($script:AppObj)/federatedIdentityCredentials"
        $Sent = Get-SentCredential
        $Sent.issuer | Should -Be 'https://token.actions.githubusercontent.com'
        $Sent.subject | Should -Be 'repo:contoso/infra:environment:production'
        $Sent.audiences | Should -Be @('api://AzureADTokenExchange')
        $Sent.PSObject.Properties['description'] | Should -BeNullOrEmpty
    }

    It 'builds GitHub pull request, Kubernetes, managed identity and other issuer credentials' {
        $null = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; Scenario = 'GitHub'; Name = 'pr'; GitHubOrganization = 'contoso'; GitHubRepository = 'infra'; GitHubEntityType = 'PullRequest' })
        $null = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; Scenario = 'Kubernetes'; Name = 'aks'; KubernetesIssuer = 'https://westeurope.oic.prod-aks.azure.com/t/c/'; KubernetesNamespace = 'apps'; KubernetesServiceAccount = 'worker' })
        $null = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; Scenario = 'ManagedIdentity'; Name = 'mi'; ManagedIdentity = @{ label = 'Automation'; value = 'cccccccc-0000-0000-0000-000000000003' } })
        $null = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; Scenario = 'Other'; Name = 'other'; Issuer = 'https://idp.contoso.com'; Subject = 'svc-1'; Audience = 'api://custom'; Description = 'Our IdP' })

        $Sent = @($script:Posts | ForEach-Object { ConvertFrom-Json -InputObject $_.Body })
        $Sent.subject | Should -Be @('repo:contoso/infra:pull_request', 'system:serviceaccount:apps:worker', 'cccccccc-0000-0000-0000-000000000003', 'svc-1')
        $Sent[2].issuer | Should -Be 'https://login.microsoftonline.com/11111111-2222-3333-4444-555555555555/v2.0'
        $Sent[3].audiences | Should -Be @('api://custom')
        $Sent[3].description | Should -Be 'Our IdP'
    }

    It 'refuses incomplete or invalid input without calling Graph' {
        $Cases = @(
            @{ Action = 'Add'; Scenario = 'GitHub'; Name = 'x'; GitHubOrganization = 'contoso'; GitHubRepository = 'infra'; GitHubEntityType = 'Branch' }
            @{ Action = 'Add'; Scenario = 'Other'; Name = 'x'; Issuer = 'http://insecure.example'; Subject = 's' }
            @{ Action = 'Add'; Scenario = 'ManagedIdentity'; Name = 'x'; ManagedIdentity = 'not-a-guid' }
            @{ Action = 'Add'; Scenario = 'Other'; Name = ''; Issuer = 'https://idp.contoso.com'; Subject = 's' }
            @{ Action = 'Add'; Scenario = 'Carrier pigeon'; Name = 'x' }
        )
        foreach ($Case in $Cases) {
            (Invoke-ExecManageAppCredentials -Request (New-Request $Case)).Body.Results.state | Should -Be 'error'
        }
        $script:Posts.Count | Should -Be 0
    }

    It 'refuses federated credentials on a service principal' {
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Add'; AppType = 'servicePrincipals'; Scenario = 'Other'; Name = 'x'; Issuer = 'https://idp.contoso.com'; Subject = 's' })

        $Response.StatusCode | Should -Be 400
        $script:Posts.Count | Should -Be 0
    }

    It 'removes a federated credential by its id' {
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request @{ Action = 'Remove'; KeyId = $script:FicId; DisplayName = 'deploy-prod' })

        $Response.Body.Results.state | Should -Be 'success'
        $script:Posts[0].Uri | Should -Be "https://graph.microsoft.com/beta/applications/$($script:AppObj)/federatedIdentityCredentials/$($script:FicId)"
        $script:Posts[0].Type | Should -Be 'DELETE'
    }
}

Describe 'Get-CIPPAppFederatedCredential and its cache' {
    BeforeEach {
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'obj-1'; appId = 'app-1'; displayName = 'Deployer' }, [pscustomobject]@{ id = 'obj-2'; appId = 'app-2'; displayName = 'Plain' }) }
        $script:BulkFails = $false
        Mock New-GraphBulkRequest {
            [pscustomobject]@{ id = 'obj-1'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'fic-1'; name = 'deploy'; issuer = 'https://token.actions.githubusercontent.com'; subject = 'repo:c/i:ref:refs/heads/main'; audiences = @('api://AzureADTokenExchange') }) } }
            if ($script:BulkFails) {
                [pscustomobject]@{ id = 'obj-2'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Forbidden' } } }
            } else {
                [pscustomobject]@{ id = 'obj-2'; status = 200; body = [pscustomobject]@{ value = @() } }
            }
        }
        Mock Add-CIPPDbItem { }
    }

    It 'returns one row per credential with its app registration' {
        $Rows = @(Get-CIPPAppFederatedCredential -TenantFilter 'contoso.onmicrosoft.com')

        $Rows.Count | Should -Be 1
        $Rows[0].id | Should -Be 'obj-1|fic-1'
        $Rows[0].appId | Should -Be 'app-1'
        $Rows[0].appDisplayName | Should -Be 'Deployer'
        $Rows[0].issuer | Should -Be 'https://token.actions.githubusercontent.com'
    }

    It 'throws when any app could not be read, and the cache then writes nothing' {
        $script:BulkFails = $true

        { Get-CIPPAppFederatedCredential -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*1 of 2 app registrations*Plain (Forbidden)*'
        { Set-CIPPDBCacheAppFederatedCredentials -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }

    It 'caches the rows, and records an empty set when no app has one' {
        Set-CIPPDBCacheAppFederatedCredentials -TenantFilter 'contoso.onmicrosoft.com'
        Mock New-GraphGetRequest { }
        Set-CIPPDBCacheAppFederatedCredentials -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'AppFederatedCredentials' -and @($Data).Count -eq 1 -and -not $ClearOnEmpty }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'AppFederatedCredentials' -and $ClearOnEmpty }
    }
}
