# Pester tests for Invoke-ExecEnterpriseAppRole.

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

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecEnterpriseAppRole.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Sp = '11111111-1111-1111-1111-111111111111'
    $script:ExoAdmin = '29232cdf-9323-42fd-ade2-1d097af3e4de'
    $script:Reader = '88d8e3e3-8f55-4a1e-953a-9b9898b8876b'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = $script:Sp }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecEnterpriseAppRole' }
            Headers = @{}
            Body    = [pscustomobject]$Merged
        }
    }

    function Set-GraphMocks {
        param($Assignments = @(), $AppId = 'app-1')
        $script:MockAssignments = $Assignments
        $script:MockAppId = $AppId
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/servicePrincipals/*' } -MockWith { [pscustomobject]@{ id = $script:Sp; appId = $script:MockAppId; displayName = 'Contoso App' } }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/roleDefinitions*' } -MockWith {
            [pscustomobject]@{ id = $script:ExoAdmin; displayName = 'Exchange Administrator' }
            [pscustomobject]@{ id = $script:Reader; displayName = 'Directory Readers' }
        }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/roleAssignments*' } -MockWith { $script:MockAssignments }
        Mock New-GraphPOSTRequest
    }
}

Describe 'Input validation' {
    It 'rejects a non-GUID ServicePrincipalId' {
        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ ServicePrincipalId = 'x'; Action = 'Add'; RoleDefinitionIds = @($script:Reader) })
        $Response.StatusCode | Should -Be 400
    }
    It 'rejects a malformed role assignment id' {
        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Remove'; RoleAssignmentIds = @('a/../b') })
        $Response.StatusCode | Should -Be 400
    }
}

Describe 'Add' {
    It 'assigns new roles tenant-wide and skips held ones' {
        Set-GraphMocks -Assignments @([pscustomobject]@{ id = 'ra1'; roleDefinitionId = $script:Reader; directoryScopeId = '/' })

        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Add'; RoleDefinitionIds = @(@{ label = 'Exchange Administrator'; value = $script:ExoAdmin }, $script:Reader) })

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Parsed = $body | ConvertFrom-Json
            $type -eq 'POST' -and $Parsed.roleDefinitionId -eq $script:ExoAdmin -and $Parsed.directoryScopeId -eq '/' -and $Parsed.principalId -eq $script:Sp
        }
        $Response.Body.Results.resultText | Should -Contain 'Contoso App already holds Directory Readers'
    }

    It 'refuses an unknown role' {
        Set-GraphMocks

        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Add'; RoleDefinitionIds = @('55555555-5555-5555-5555-555555555555') })

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'refuses to change the CIPP-SAM application' {
        Set-GraphMocks -AppId 'sam-app'
        $env:ApplicationID = 'sam-app'
        try {
            $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Add'; RoleDefinitionIds = @($script:Reader) })
        } finally {
            $env:ApplicationID = $null
        }

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }
}

Describe 'Remove' {
    It 'deletes held assignments and reports 207 when one is missing' {
        Set-GraphMocks -Assignments @([pscustomobject]@{ id = 'ra1'; roleDefinitionId = $script:ExoAdmin; directoryScopeId = '/' })

        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Remove'; RoleAssignmentIds = @('ra1', 'gone') })

        $Response.StatusCode | Should -Be 207
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $uri -like '*/roleAssignments/ra1' }
        $Response.Body.Results.resultText | Should -Contain 'Removed Exchange Administrator from Contoso App'
    }

    It 'returns 404 when no assignment exists' {
        Set-GraphMocks

        $Response = Invoke-ExecEnterpriseAppRole -Request (New-Request @{ Action = 'Remove'; RoleAssignmentIds = @('gone') })

        $Response.StatusCode | Should -Be 404
    }
}
