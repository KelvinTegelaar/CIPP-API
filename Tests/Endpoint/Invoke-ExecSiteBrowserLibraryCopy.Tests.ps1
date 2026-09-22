# Pester tests for Invoke-ExecSiteBrowserLibraryCopy and Invoke-ListSiteBrowserLibraryCopy

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ExecPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecSiteBrowserLibraryCopy.ps1'
    $ListPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteBrowserLibraryCopy.ps1'
    if (-not (Test-Path $ExecPath)) { throw "Could not locate $ExecPath" }
    if (-not (Test-Path $ListPath)) { throw "Could not locate $ListPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Start-CIPPSharePointLibraryCopy {
        param(
            [string]$Mode,
            [string]$TenantFilter,
            [int]$NameConflictBehavior
        )
    }
    function Update-CIPPSharePointLibraryCopyStatus {
        param([string]$TenantFilter, [string]$OperationId)
    }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Message } }

    . $ExecPath
    . $ListPath
}

Describe 'Invoke-ExecSiteBrowserLibraryCopy' {
    BeforeEach {
        Mock Start-CIPPSharePointLibraryCopy { [PSCustomObject]@{ EligibleRootCount = 3; WarnLevel = 'none'; Message = 'ok' } }
    }

    It 'returns BadRequest when tenantFilter is missing' {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecSiteBrowserLibraryCopy' }
                Headers = @{}
                Body    = [pscustomobject]@{ Action = 'PreflightLibraryCopy' }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 0 -Exactly
    }

    It 'calls PreflightLibraryCopy with conflict behavior mapping' {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecSiteBrowserLibraryCopy' }
                Headers = @{ 'x-ms-client-principal-name' = 'admin@contoso.com' }
                Body    = [pscustomobject]@{
                    Action               = 'PreflightLibraryCopy'
                    tenantFilter         = 'contoso.com'
                    SourceSiteId         = 'site-a'
                    SourceListId         = 'list-a'
                    DestSiteId           = 'site-b'
                    DestListId           = 'list-b'
                    NameConflictBehavior = 'Fail'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 1 -Exactly
    }
}

Describe 'Invoke-ListSiteBrowserLibraryCopy' {
    BeforeEach {
        Mock Update-CIPPSharePointLibraryCopyStatus {
            [PSCustomObject]@{
                OperationId  = 'op-1'
                Status       = 'Processing'
                JobsComplete = 1
                JobsTotal    = 2
            }
        }
    }

    It 'returns BadRequest when OperationId is missing' {
        $Response = Invoke-ListSiteBrowserLibraryCopy -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteBrowserLibraryCopy' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.com' }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns sanitized status in Results' {
        $Response = Invoke-ListSiteBrowserLibraryCopy -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteBrowserLibraryCopy' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.com'; OperationId = 'op-1' }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.Status | Should -Be 'Processing'
        $Response.Body.Results.JobsTotal | Should -Be 2
    }
}
