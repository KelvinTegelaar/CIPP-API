# Pester tests for Invoke-ExecEmptySiteRecycleBin and Invoke-ListSiteRecycleBinSummary

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ExecPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecEmptySiteRecycleBin.ps1'
    $SummaryPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteRecycleBinSummary.ps1'
    if (-not (Test-Path $ExecPath)) { throw "Could not locate $ExecPath" }
    if (-not (Test-Path $SummaryPath)) { throw "Could not locate $SummaryPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com'; AdminUrl = 'https://contoso-admin.sharepoint.com' } }
    function Resolve-CIPPSharePointRestContext {
        param($TenantFilter, $SiteUrl)
        $BaseUri = 'https://contoso.sharepoint.com/sites/a/_api'
        [PSCustomObject]@{
            Scope   = 'https://contoso.sharepoint.com/.default'
            Headers = @{ Accept = 'application/json;odata=nometadata' }
            BaseUri = $BaseUri
            WebUri  = "$BaseUri/web"
        }
    }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Message } }

    . $ExecPath
    . $SummaryPath
}

Describe 'Invoke-ExecEmptySiteRecycleBin' {
    BeforeEach {
        $script:GraphPostCalls = 0
        function global:New-GraphPostRequest {
            param(
                $uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders,
                [switch]$UseCertificate,
                $AsApp
            )
            $script:GraphPostCalls++
        }
        function global:New-GraphGetRequest {
            param(
                $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                [switch]$UseCertificate,
                [bool]$noPagination,
                [switch]$SkipValueExtraction
            )
        }
    }

    It 'returns BadRequest when SiteUrl is missing' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; Stage = 'Both' }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns BadRequest for invalid Stage' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'Nope'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'Invalid Stage'
    }

    It 'calls deleteAll endpoints for Both' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'Both'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:GraphPostCalls | Should -Be 2
        $Response.Body.Results | Should -Match 'Emptied recycle bin'
    }
}

Describe 'Invoke-ListSiteRecycleBinSummary' {
    BeforeEach {
        function global:New-GraphGetRequest {
            param(
                $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                [switch]$UseCertificate,
                [bool]$noPagination,
                [switch]$SkipValueExtraction
            )
            [PSCustomObject]@{
                value             = @(
                    [PSCustomObject]@{ Id = '1'; Size = 100; ItemState = 1 }
                    [PSCustomObject]@{ Id = '2'; Size = 50; ItemState = 2 }
                )
                '@odata.nextLink' = $null
            }
        }
    }

    It 'returns BadRequest when SiteUrl is missing' {
        $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.onmicrosoft.com' }
                Body    = @{}
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'aggregates sizes without returning names' {
        $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                Headers = @{}
                Query   = @{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                }
                Body    = @{}
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.totalBytes | Should -Be 150
        $Response.Body.Results.firstStageBytes | Should -Be 100
        $Response.Body.Results.secondStageBytes | Should -Be 50
        ($Response.Body.Results.PSObject.Properties.Name -contains 'Title') | Should -BeFalse
        ($Response.Body.Results.PSObject.Properties.Name -contains 'LeafName') | Should -BeFalse
    }
}
