# Pester tests for Invoke-ExecEnterpriseAppPermission.

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
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecEnterpriseAppPermission.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Sp = '11111111-1111-1111-1111-111111111111'
    $script:Graph = '22222222-2222-2222-2222-222222222222'
    $script:MailRead = '33333333-3333-3333-3333-333333333333'
    $script:UserRead = '44444444-4444-4444-4444-444444444444'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com'; ServicePrincipalId = $script:Sp }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecEnterpriseAppPermission' }
            Headers = @{}
            Body    = [pscustomobject]$Merged
        }
    }

    function New-GraphResource {
        [pscustomobject]@{
            displayName            = 'Microsoft Graph'
            appRoles               = @(
                [pscustomobject]@{ id = $script:MailRead; value = 'Mail.Read'; allowedMemberTypes = @('Application') }
                [pscustomobject]@{ id = $script:UserRead; value = 'User.Read.All'; allowedMemberTypes = @('Application') }
            )
            oauth2PermissionScopes = @(
                [pscustomobject]@{ value = 'User.Read' }
                [pscustomobject]@{ value = 'Mail.Send' }
            )
        }
    }
}

Describe 'Input validation' {
    It 'rejects a non-GUID ServicePrincipalId' {
        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ ServicePrincipalId = 'x/../y'; Action = 'Remove'; Type = 'Application'; AppRoleAssignmentIds = @('abc') })
        $Response.StatusCode | Should -Be 400
    }
    It 'rejects an unknown action' {
        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Nuke'; Type = 'Application' })
        $Response.StatusCode | Should -Be 400
    }
    It 'rejects an empty item list' {
        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Add'; Type = 'Delegated'; ResourceId = $script:Graph; Scopes = @() })
        $Response.StatusCode | Should -Be 400
    }
}

Describe 'Application permissions' {
    It 'grants new app roles and skips ones already assigned' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*appRoleAssignments' } -MockWith { [pscustomobject]@{ id = 'a1'; resourceId = $script:Graph; appRoleId = $script:MailRead } }
        Mock New-GraphGetRequest -MockWith { New-GraphResource }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Add'; Type = 'Application'; ResourceId = $script:Graph; AppRoleIds = @(@{ label = 'Mail.Read'; value = $script:MailRead }, $script:UserRead) })

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' -and $body -match $script:UserRead }
        $Response.Body.Results.resultText | Should -Contain 'Mail.Read is already granted on Microsoft Graph'
    }

    It 'refuses an app role the resource does not publish' {
        Mock New-GraphGetRequest -MockWith { New-GraphResource }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Add'; Type = 'Application'; ResourceId = $script:Graph; AppRoleIds = @('55555555-5555-5555-5555-555555555555') })

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'removes assignments and reports 207 when one is missing' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*appRoleAssignments' } -MockWith { [pscustomobject]@{ id = 'a1'; resourceId = $script:Graph; resourceDisplayName = 'Microsoft Graph'; appRoleId = $script:MailRead } }
        Mock New-GraphGetRequest -MockWith { New-GraphResource }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Remove'; Type = 'Application'; AppRoleAssignmentIds = @('a1', 'gone') })

        $Response.StatusCode | Should -Be 207
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $uri -like '*/appRoleAssignments/a1' }
    }

    It 'returns 404 when no assignment exists' {
        Mock New-GraphGetRequest -MockWith { @() }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Remove'; Type = 'Application'; AppRoleAssignmentIds = @('gone') })

        $Response.StatusCode | Should -Be 404
    }
}

Describe 'Delegated permissions' {
    It 'adds scopes to the existing tenant-wide grant in the published casing' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*oauth2PermissionGrants*' } -MockWith {
            [pscustomobject]@{ id = 'g1'; resourceId = $script:Graph; consentType = 'AllPrincipals'; scope = 'User.Read' }
        }
        Mock New-GraphGetRequest -MockWith { New-GraphResource }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Add'; Type = 'Delegated'; ResourceId = $script:Graph; Scopes = @('mail.send', 'User.Read') })

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PATCH' -and $uri -like '*/oauth2PermissionGrants/g1' -and ($body | ConvertFrom-Json).scope -ceq 'User.Read Mail.Send' }
    }

    It 'creates a tenant-wide grant when there is none' {
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*oauth2PermissionGrants*' } -MockWith { @() }
        Mock New-GraphGetRequest -MockWith { New-GraphResource }
        Mock New-GraphPOSTRequest

        $null = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Add'; Type = 'Delegated'; ResourceId = $script:Graph; Scopes = @('User.Read') })

        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'POST' -and ($body | ConvertFrom-Json).consentType -eq 'AllPrincipals' }
    }

    It 'strips scopes from every grant and deletes grants left empty' {
        Mock New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'g1'; resourceId = $script:Graph; consentType = 'AllPrincipals'; scope = 'User.Read Mail.Send' }
            [pscustomobject]@{ id = 'g2'; resourceId = $script:Graph; consentType = 'Principal'; principalId = 'u1'; scope = 'Mail.Send' }
            [pscustomobject]@{ id = 'g3'; resourceId = 'other'; consentType = 'AllPrincipals'; scope = 'Mail.Send' }
        }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Remove'; Type = 'Delegated'; ResourceId = $script:Graph; Scopes = @('Mail.Send') })

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'PATCH' -and $uri -like '*/g1' -and ($body | ConvertFrom-Json).scope -eq 'User.Read' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $type -eq 'DELETE' -and $uri -like '*/g2' }
        Should -Invoke New-GraphPOSTRequest -Times 2 -Exactly
    }

    It 'returns 404 when the scope is not granted' {
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'g1'; resourceId = $script:Graph; consentType = 'AllPrincipals'; scope = 'User.Read' } }
        Mock New-GraphPOSTRequest

        $Response = Invoke-ExecEnterpriseAppPermission -Request (New-Request @{ Action = 'Remove'; Type = 'Delegated'; ResourceId = $script:Graph; Scopes = @('Mail.Send') })

        $Response.StatusCode | Should -Be 404
    }
}
