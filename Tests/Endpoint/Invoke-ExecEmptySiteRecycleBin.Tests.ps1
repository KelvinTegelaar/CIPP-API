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
    # Like the real helper, read the message from the ErrorRecord's exception.
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    . $ExecPath
    . $SummaryPath
}

Describe 'Invoke-ExecEmptySiteRecycleBin' {
    BeforeEach {
        $script:GraphPostCalls = 0
        $script:PostUris = [System.Collections.Generic.List[string]]::new()
        $script:PostBodies = [System.Collections.Generic.List[string]]::new()
        $script:GetUris = [System.Collections.Generic.List[string]]::new()
        # Pages the mocked recycle bin read returns, one per call; an empty bin once they run out.
        $script:BinPages = [System.Collections.Generic.Queue[object]]::new()
        function global:New-GraphPostRequest {
            param(
                $uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders,
                [switch]$UseCertificate,
                $AsApp
            )
            $script:GraphPostCalls++
            $script:PostUris.Add($uri)
            $script:PostBodies.Add([string]$body)
        }
        function global:New-GraphGetRequest {
            param(
                $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                [switch]$UseCertificate,
                [bool]$noPagination,
                [switch]$SkipValueExtraction
            )
            $script:GetUris.Add($uri)
            if ($script:BinPages.Count -gt 0) { return $script:BinPages.Dequeue() }
            [PSCustomObject]@{ value = @() }
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

    It 'deletes first-stage items by id and empties the second stage for Both' {
        $script:BinPages.Enqueue([PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 'a1' }) })
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
        $script:PostUris | Should -Be @(
            'https://contoso.sharepoint.com/sites/a/_api/site/RecycleBin/DeleteByIds'
            'https://contoso.sharepoint.com/sites/a/_api/site/RecycleBin/deleteAllSecondStageItems'
        )
        $Response.Body.Results | Should -Match 'Emptied recycle bin'
    }

    It 'deletes first-stage items by id from the site collection bin, not web deleteAll' {
        # web/RecycleBin/deleteAll() succeeds for the app-only caller without removing items other users deleted.
        $script:BinPages.Enqueue([PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 'a1' }, [PSCustomObject]@{ Id = 'a2' }) })
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'First'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:PostUris | Should -Be @('https://contoso.sharepoint.com/sites/a/_api/site/RecycleBin/DeleteByIds')
        ($script:PostBodies[0] | ConvertFrom-Json).ids | Should -Be @('a1', 'a2')
        $script:GetUris[0] | Should -Match '/_api/site/RecycleBin\?'
        $script:GetUris[0] | Should -Match '\$filter=ItemState eq 1'
        $script:GetUris.Count | Should -Be 2
        $Response.Body.Results | Should -Match 'Deleted 2 first-stage item'
    }

    It 'fails when SharePoint keeps first-stage items it accepted for deletion' {
        $Page = [PSCustomObject]@{ value = @([PSCustomObject]@{ Id = 'a1' }) }
        $script:BinPages.Enqueue($Page)
        $script:BinPages.Enqueue($Page)
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'First'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Match 'did not delete'
        $script:GraphPostCalls | Should -Be 1
    }

    It 'leaves first-stage items alone when only the second stage is emptied' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'Second'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:PostUris | Should -Be @('https://contoso.sharepoint.com/sites/a/_api/site/RecycleBin/deleteAllSecondStageItems')
        $script:GetUris.Count | Should -Be 0
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

    Context 'bin larger than one page' {
        BeforeEach {
            function global:New-GraphGetRequest {
                param(
                    $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                    [switch]$UseCertificate,
                    [bool]$noPagination,
                    [switch]$SkipValueExtraction
                )
                $Skip = if ($uri -match '\$skip=(\d+)') { [int]$Matches[1] } else { 0 }
                $Top = if ($uri -match '\$top=(\d+)') { [int]$Matches[1] } else { 100 }
                [PSCustomObject]@{ value = @($script:Bin | Select-Object -Skip $Skip -First $Top) }
            }
        }

        It 'counts every item' {
            $script:Bin = @(1..520 | ForEach-Object { [PSCustomObject]@{ Id = "$_"; Size = 10; ItemState = 1 } })
            $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                    Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                    Headers = @{}
                    Query   = @{ tenantFilter = 'contoso.onmicrosoft.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/a' }
                    Body    = @{}
                })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results.itemCount | Should -Be 520
            $Response.Body.Results.totalBytes | Should -Be 5200
            $Response.Body.Results.scannedItems | Should -Be 520
            $Response.Body.Results.capped | Should -BeFalse
        }

        It 'reports capped when MaxItems stops the scan on a later page' {
            $script:Bin = @(1..520 | ForEach-Object { [PSCustomObject]@{ Id = "$_"; Size = 10; ItemState = 1 } })
            $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                    Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                    Headers = @{}
                    Query   = @{ tenantFilter = 'contoso.onmicrosoft.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/a'; MaxItems = 510 }
                    Body    = @{}
                })

            $Response.Body.Results.itemCount | Should -Be 510
            $Response.Body.Results.scannedItems | Should -Be 510
            $Response.Body.Results.capped | Should -BeTrue
        }

        It 'does not report capped for a bin of exactly one page' {
            $script:Bin = @(1..500 | ForEach-Object { [PSCustomObject]@{ Id = "$_"; Size = 10; ItemState = 2 } })
            $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                    Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                    Headers = @{}
                    Query   = @{ tenantFilter = 'contoso.onmicrosoft.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/a' }
                    Body    = @{}
                })

            $Response.Body.Results.itemCount | Should -Be 500
            $Response.Body.Results.secondStageCount | Should -Be 500
            $Response.Body.Results.capped | Should -BeFalse
        }
    }
}
