# Pester tests for Invoke-ListDeletedApplications and Invoke-ExecDeletedApplication. Graph is mocked per URL; every
# write is recorded so tests can check what was sent.

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

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval'
    foreach ($Name in 'Invoke-ListDeletedApplications.ps1', 'Invoke-ExecDeletedApplication.ps1') {
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $Folder $Name) -Raw)))
    }

    $script:AppObj = '11111111-1111-1111-1111-111111111111'
    $script:SpObj = '22222222-2222-2222-2222-222222222222'
    $script:UserObj = '33333333-3333-3333-3333-333333333333'

    function New-Request {
        param([hashtable]$Body)
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecDeletedApplication' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]$Merged }
    }
    function Get-Writes { @($script:Writes) }
}

Describe 'Deleted applications' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:DeletedApps = @([pscustomobject]@{ id = $script:AppObj; appId = 'app-1'; displayName = 'Contoso App'; publisherDomain = 'contoso.com'; deletedDateTime = [datetimeoffset]::UtcNow.AddDays(-10).ToString('o') })
        $script:DeletedSps = @(
            [pscustomobject]@{ id = $script:SpObj; appId = 'app-1'; displayName = 'Contoso App'; publisherName = 'Contoso'; deletedDateTime = [datetimeoffset]::UtcNow.AddDays(-10).ToString('o') }
            [pscustomobject]@{ id = '44444444-4444-4444-4444-444444444444'; appId = 'app-2'; displayName = 'Vendor App'; publisherName = 'Vendor'; deletedDateTime = [datetimeoffset]::UtcNow.AddDays(-29.5).ToString('o') }
        )
        Mock New-GraphGetRequest {
            if ($uri -like '*deletedItems/microsoft.graph.application*') { return $script:DeletedApps }
            if ($uri -like '*deletedItems/microsoft.graph.servicePrincipal*') { return $script:DeletedSps }
            if ($uri -like "*deletedItems/$($script:AppObj)") { return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.application'; id = $script:AppObj; appId = 'app-1'; displayName = 'Contoso App' } }
            if ($uri -like "*deletedItems/$($script:SpObj)") { return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = $script:SpObj; appId = 'app-1'; displayName = 'Contoso App' } }
            if ($uri -like "*deletedItems/$($script:UserObj)") { return [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = $script:UserObj; displayName = 'Jane' } }
        }
        Mock New-GraphPOSTRequest { $script:Writes.Add([pscustomobject]@{ Uri = $uri; Type = $type }) }
    }

    Context 'Invoke-ListDeletedApplications' {
        It 'lists deleted app registrations and enterprise apps with days left and whether the other half is deleted' {
            $Response = Invoke-ListDeletedApplications -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com' }; Body = $null })
            $Rows = @($Response.Body.Results)

            $Response.StatusCode | Should -Be 200
            $Rows.Count | Should -Be 3
            $App = $Rows | Where-Object type -EQ 'App registration'
            $App.daysLeft | Should -Be 20
            $App.publisher | Should -Be 'contoso.com'
            $App.relatedDeleted | Should -BeTrue
            $App.relatedDeletedId | Should -Be $script:SpObj
            $Vendor = $Rows | Where-Object appId -EQ 'app-2'
            $Vendor.type | Should -Be 'Enterprise app'
            $Vendor.daysLeft | Should -Be 1
            $Vendor.relatedDeleted | Should -BeFalse
            # Most recently deleted first.
            $Rows[-1].appId | Should -Be 'app-2'
        }

        It 'refuses all tenants' {
            (Invoke-ListDeletedApplications -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = 'AllTenants' }; Body = $null })).StatusCode | Should -Be 400
        }
    }

    Context 'Invoke-ExecDeletedApplication' {
        It 'restores an app registration and says its enterprise app is still deleted' {
            $Response = Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:AppObj; Action = 'Restore' })

            $Response.StatusCode | Should -Be 200
            (Get-Writes).Uri | Should -Be @("https://graph.microsoft.com/v1.0/directory/deletedItems/$($script:AppObj)/restore")
            $Response.Body.Results[0].resultText | Should -BeLike "Restored the app registration 'Contoso App'. Its enterprise app is still deleted*"
        }

        It 'restores an enterprise app without a note when its app registration is not deleted' {
            $script:DeletedApps = @()
            $Response = Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:SpObj; Action = 'Restore' })

            $Response.Body.Results[0].resultText | Should -Be "Restored the enterprise app 'Contoso App'"
        }

        It 'permanently deletes an enterprise app' {
            $Response = Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:SpObj; Action = @{ value = 'Delete' } })

            $Response.StatusCode | Should -Be 200
            (Get-Writes)[0].Uri | Should -Be "https://graph.microsoft.com/v1.0/directory/deletedItems/$($script:SpObj)"
            (Get-Writes)[0].Type | Should -Be 'DELETE'
        }

        It 'refuses a deleted object that is not an application, such as a user' {
            $Response = Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:UserObj; Action = 'Restore' })

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results[0].resultText | Should -BeLike '*not a deleted app registration or enterprise app*'
            Get-Writes | Should -BeNullOrEmpty
        }

        It 'rejects an unknown action, all tenants and an invalid ID' {
            (Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:AppObj; Action = 'Purge' })).StatusCode | Should -Be 400
            (Invoke-ExecDeletedApplication -Request (New-Request @{ ID = $script:AppObj; Action = 'Restore'; tenantFilter = 'AllTenants' })).StatusCode | Should -Be 400
            (Invoke-ExecDeletedApplication -Request (New-Request @{ ID = 'x'; Action = 'Restore' })).StatusCode | Should -Be 400
            Get-Writes | Should -BeNullOrEmpty
        }
    }
}
