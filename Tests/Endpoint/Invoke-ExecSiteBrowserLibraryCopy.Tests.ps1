# Pester tests for Invoke-ExecSiteBrowserLibraryCopy and Invoke-ListSiteBrowserLibraryCopy

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ExecPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecSiteBrowserLibraryCopy.ps1'
    $ListPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteBrowserLibraryCopy.ps1'
    if (-not (Test-Path $ExecPath)) { throw "Could not locate $ExecPath" }
    if (-not (Test-Path $ListPath)) { throw "Could not locate $ListPath" }
    $FolderNamePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSharePointLibraryCopyFolderName.ps1'
    if (-not (Test-Path $FolderNamePath)) { throw "Could not locate $FolderNamePath" }

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
            [int]$NameConflictBehavior,
            [string]$DestFolderName
        )
    }
    function Update-CIPPSharePointLibraryCopyStatus {
        param([string]$TenantFilter, [string]$OperationId)
    }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message ?? $Exception.Message } }

    . $ExecPath
    . $ListPath
    . $FolderNamePath

    function New-LibraryCopyRequest {
        param([hashtable]$Extra = @{})
        $Body = @{
            Action       = 'StartLibraryCopy'
            tenantFilter = 'contoso.com'
            SourceSiteId = 'site-a'
            SourceListId = 'list-a'
            DestSiteId   = 'site-b'
            DestListId   = 'list-b'
        }
        foreach ($Key in $Extra.Keys) { $Body[$Key] = $Extra[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSiteBrowserLibraryCopy' }
            Headers = @{ 'x-ms-client-principal-name' = 'admin@contoso.com' }
            Body    = [pscustomobject]$Body
        }
    }
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

    It 'does not pass DestFolderName when it is absent' {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request (New-LibraryCopyRequest)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrEmpty($DestFolderName)
        }
    }

    It 'treats an empty DestFolderName as absent' {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request (New-LibraryCopyRequest -Extra @{ DestFolderName = '' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrEmpty($DestFolderName)
        }
    }

    It 'passes a trimmed DestFolderName through to the copy' {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request (New-LibraryCopyRequest -Extra @{ DestFolderName = '  Archive - jane@contoso.com  ' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 1 -Exactly -ParameterFilter {
            $DestFolderName -eq 'Archive - jane@contoso.com'
        }
    }

    It 'rejects an invalid DestFolderName (<Name>) without starting a copy' -ForEach @(
        @{ Name = 'Archive/jane' }
        @{ Name = 'Archive\jane' }
        @{ Name = 'what?' }
        @{ Name = '...' }
        @{ Name = '   ' }
    ) {
        $Response = Invoke-ExecSiteBrowserLibraryCopy -Request (New-LibraryCopyRequest -Extra @{ DestFolderName = $Name })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'DestFolderName'
        Should -Invoke Start-CIPPSharePointLibraryCopy -Times 0 -Exactly
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
