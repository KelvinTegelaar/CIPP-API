# Pester tests for the SharePoint Advanced Management access reports: the request helper and
# the List / Exec endpoints built on it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Names = 'Invoke-CIPPSPOAccessReportRequest.ps1', 'Invoke-ListSharePointAccessReports.ps1', 'Invoke-ExecSharePointAccessReport.ps1', 'Get-CippErrorStatusCode.ps1'
    $Paths = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -File -Include $Names -ErrorAction SilentlyContinue
    if (@($Paths).Count -ne 4) { throw 'Could not locate the access report files under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) @{ AdminUrl = 'https://contoso-admin.sharepoint.com' } }
    function Assert-CIPPSharePointHost { param($Uri, $Scope) }
    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-AuthorisedRequestError { param($TenantID, $Context) 'not authorised' }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, [switch]$UseCertificate) @{ Authorization = 'Bearer x' } }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP' }
    # Sets the caller's status variable the way the real Invoke-CIPPRestMethod does.
    function Invoke-CIPPRestMethod {
        param($Uri, $Method, $Headers, $Body, $ContentType, [switch]$SkipHttpErrorCheck, $StatusCodeVariable)
        $script:RestCalls.Add(@{ Uri = $Uri; Method = $Method; Body = $Body })
        Set-Variable -Scope 1 -Name $StatusCodeVariable -Value $script:RestStatus
        $script:RestResult
    }

    foreach ($Path in $Paths) { . $Path.FullName }

    function New-ListRequest {
        param($TenantFilter = 'contoso.onmicrosoft.com', $ReportId)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListSharePointAccessReports' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = $TenantFilter; ReportId = $ReportId }
        }
    }

    function New-ExecRequest {
        param([hashtable]$Body)
        $Defaults = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        foreach ($Key in $Body.Keys) { $Defaults[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSharePointAccessReport' }
            Headers = @{}
            Body    = [pscustomobject]$Defaults
        }
    }

    $script:ReportId = '6f1d1c1e-0d55-4c55-9a9a-3c0d6d7e8f90'
}

Describe 'Invoke-CIPPSPOAccessReportRequest' {
    BeforeEach {
        $script:RestCalls = [System.Collections.Generic.List[hashtable]]::new()
        $script:RestStatus = 200
        $script:RestResult = [pscustomobject]@{ value = @() }
    }

    It 'calls the admin site analyticsReports API and returns the body on success' {
        $Result = Invoke-CIPPSPOAccessReportRequest -TenantFilter 'contoso.onmicrosoft.com' -Path '/abc' -Method DELETE

        $Result.value.Count | Should -Be 0
        $script:RestCalls[0].Uri | Should -Be 'https://contoso-admin.sharepoint.com/_api/v2.1/tenants/default/analyticsReports/abc'
        $script:RestCalls[0].Method | Should -Be 'DELETE'
    }

    It 'maps <Status> <Body> to <Type>' -TestCases @(
        @{ Status = 403; Body = '{"errorMessage":"MissingSAMLicense"}'; Type = 'System.ArgumentException' }
        @{ Status = 400; Body = '{"errorMessage":"ReportIsNotEnabled"}'; Type = 'System.ArgumentException' }
        @{ Status = 409; Body = '{"errorMessage":"DAGReportAlreadyExists"}'; Type = 'System.ArgumentException' }
        @{ Status = 400; Body = '{"error":{"message":"bad"}}'; Type = 'System.ArgumentException' }
        @{ Status = 404; Body = ''; Type = 'System.Management.Automation.ItemNotFoundException' }
        @{ Status = 500; Body = 'boom'; Type = 'System.Management.Automation.RuntimeException' }
    ) {
        $script:RestStatus = $Status
        $script:RestResult = $Body

        $Thrown = $null
        try { Invoke-CIPPSPOAccessReportRequest -TenantFilter 'contoso.onmicrosoft.com' -Path '/' } catch { $Thrown = $_ }

        $Thrown | Should -Not -BeNullOrEmpty
        $Thrown.Exception.GetType().FullName | Should -Be $Type
    }

    It 'throws when the tenant is not authorised' {
        Mock Get-AuthorisedRequest { $false }

        { Invoke-CIPPSPOAccessReportRequest -TenantFilter 'contoso.onmicrosoft.com' -Path '/' } | Should -Throw 'not authorised'
        $script:RestCalls.Count | Should -Be 0
    }
}

Describe 'Invoke-ListSharePointAccessReports' {
    It 'refuses <Tenant> with 400' -TestCases @(
        @{ Tenant = 'AllTenants' }
        @{ Tenant = $null }
    ) {
        Mock Invoke-CIPPSPOAccessReportRequest {}

        (Invoke-ListSharePointAccessReports -Request (New-ListRequest -TenantFilter $Tenant)).StatusCode | Should -Be 400
        Should -Invoke Invoke-CIPPSPOAccessReportRequest -Times 0 -Exactly
    }

    It 'refuses a ReportId that is not a GUID with 400' {
        Mock Invoke-CIPPSPOAccessReportRequest {}

        (Invoke-ListSharePointAccessReports -Request (New-ListRequest -ReportId "x/../y")).StatusCode | Should -Be 400
        Should -Invoke Invoke-CIPPSPOAccessReportRequest -Times 0 -Exactly
    }

    It 'lists site and user permissions reports as rows' {
        Mock Invoke-CIPPSPOAccessReportRequest -ParameterFilter { $Path -like "*'SitePermissions'" } {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = '1'; status = 'Completed'; workLoad = 'sharePoint'; triggerDateTime = 't1'; createdDateTime = 'c1'; sitePermissionsParameters = [pscustomobject]@{ reportName = 'Sites'; countOfSitesInReport = 12 } }) }
        }
        Mock Invoke-CIPPSPOAccessReportRequest -ParameterFilter { $Path -like "*'UserPermissions'" } {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = '2'; status = 'InProgress'; workLoad = 'oneDrive'; permissionsParameters = [pscustomobject]@{ reportName = 'Users'; userEmailList = @('a@contoso.com', 'b@contoso.com') } }) }
        }

        $Response = Invoke-ListSharePointAccessReports -Request (New-ListRequest)

        $Response.StatusCode | Should -Be 200
        $Response.Body.Count | Should -Be 2
        $Response.Body[0].name | Should -Be 'Sites'
        $Response.Body[0].reportType | Should -Be 'Site permissions'
        $Response.Body[0].workload | Should -Be 'SharePoint'
        $Response.Body[0].sitesInReport | Should -Be 12
        $Response.Body[1].reportType | Should -Be 'User permissions'
        $Response.Body[1].workload | Should -Be 'OneDrive'
        $Response.Body[1].users | Should -Be 'a@contoso.com, b@contoso.com'
    }

    It 'returns an empty array when there are no reports' {
        Mock Invoke-CIPPSPOAccessReportRequest { [pscustomobject]@{ value = @() } }

        $Response = Invoke-ListSharePointAccessReports -Request (New-ListRequest)

        $Response.StatusCode | Should -Be 200
        $null -eq $Response.Body | Should -BeFalse
        @($Response.Body).Count | Should -Be 0
    }

    It 'returns the rows of a CSV report with camelCase field names' {
        Mock Invoke-CIPPSPOAccessReportRequest {
            , [System.Text.Encoding]::UTF8.GetBytes("$([char]0xFEFF)Site URL,Number of users having access,EEEU permission`r`nhttps://contoso.sharepoint.com/sites/a,5,Yes`r`n")
        }

        $Response = Invoke-ListSharePointAccessReports -Request (New-ListRequest -ReportId $script:ReportId)

        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 1
        $Response.Body[0].siteUrl | Should -Be 'https://contoso.sharepoint.com/sites/a'
        $Response.Body[0].numberOfUsersHavingAccess | Should -Be '5'
        $Response.Body[0].eeeuPermission | Should -Be 'Yes'
        Should -Invoke Invoke-CIPPSPOAccessReportRequest -Times 1 -Exactly -ParameterFilter { $Path -eq "/$script:ReportId/content" -and $Content }
    }

    It 'reads every CSV in a user permissions ZIP and keeps the file name' {
        $Stream = [System.IO.MemoryStream]::new()
        $Archive = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($User in 'a@contoso.com', 'b@contoso.com') {
            $Writer = [System.IO.StreamWriter]::new($Archive.CreateEntry("$User.csv").Open())
            $Writer.Write("Site URL,Permission`nhttps://contoso.sharepoint.com/sites/$($User[0]),Edit`n")
            $Writer.Dispose()
        }
        $Archive.Dispose()
        $script:ZipBytes = $Stream.ToArray()
        Mock Invoke-CIPPSPOAccessReportRequest { , $script:ZipBytes }

        $Response = Invoke-ListSharePointAccessReports -Request (New-ListRequest -ReportId $script:ReportId)

        $Response.StatusCode | Should -Be 200
        @($Response.Body).Count | Should -Be 2
        $Response.Body[0].reportFile | Should -Be 'a@contoso.com'
        $Response.Body[1].siteUrl | Should -Be 'https://contoso.sharepoint.com/sites/b'
        $Response.Body[1].permission | Should -Be 'Edit'
    }

    It 'maps a <Type> from the helper to <Status>' -TestCases @(
        @{ Type = 'ArgumentException'; Status = 400 }
        @{ Type = 'ItemNotFoundException'; Status = 404 }
        @{ Type = 'untyped error'; Status = 500 }
    ) {
        $script:ThrowType = $Type
        Mock Invoke-CIPPSPOAccessReportRequest {
            switch ($script:ThrowType) {
                'ArgumentException' { throw [System.ArgumentException]::new('no licence') }
                'ItemNotFoundException' { throw [System.Management.Automation.ItemNotFoundException]::new('gone') }
                default { throw 'boom' }
            }
        }

        $Response = Invoke-ListSharePointAccessReports -Request (New-ListRequest)

        $Response.StatusCode | Should -Be $Status
        $Response.Body.Results | Should -BeLike 'Failed to read SharePoint access reports:*'
    }
}

Describe 'Invoke-ExecSharePointAccessReport' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[hashtable]]::new()
        Mock Invoke-CIPPSPOAccessReportRequest {
            $script:Calls.Add(@{ Path = $Path; Method = $Method; Body = $Body })
            [pscustomobject]@{ id = 'new'; status = 'InProgress' }
        }
    }

    It 'refuses <Case> with 400' -TestCases @(
        @{ Case = 'AllTenants'; Body = @{ tenantFilter = 'AllTenants'; Action = 'Create'; ReportType = 'SitePermissions'; Workload = 'sharePoint' } }
        @{ Case = 'an unknown action'; Body = @{ Action = 'Run' } }
        @{ Case = 'an unknown report type'; Body = @{ Action = 'Create'; ReportType = 'Files'; Workload = 'sharePoint' } }
        @{ Case = 'an unknown workload'; Body = @{ Action = 'Create'; ReportType = 'SitePermissions'; Workload = 'teams' } }
        @{ Case = 'a user report without users'; Body = @{ Action = 'Create'; ReportType = 'UserPermissions'; Workload = 'sharePoint'; Users = @() } }
        @{ Case = 'a delete without a GUID'; Body = @{ Action = 'Delete'; ReportId = '../x' } }
    ) {
        (Invoke-ExecSharePointAccessReport -Request (New-ExecRequest -Body $Body)).StatusCode | Should -Be 400
        $script:Calls.Count | Should -Be 0
    }

    It 'starts an org-wide site permissions report' {
        $Response = Invoke-ExecSharePointAccessReport -Request (New-ExecRequest -Body @{ Action = 'Create'; ReportType = 'SitePermissions'; Workload = 'oneDrive' })

        $Response.StatusCode | Should -Be 200
        $script:Calls[0].Path | Should -Be '/createSitePermissionsReport'
        $script:Calls[0].Method | Should -Be 'POST'
        $Sent = $script:Calls[0].Body | ConvertFrom-Json
        $Sent.workLoad | Should -Be 'oneDrive'
        $Sent.sitePermissionsParameters.reportName | Should -BeLike 'CIPP OneDrive site permissions *'
        @($Sent.sitePermissionsParameters.siteTemplates) | Should -Be @('All')
        $Response.Body.Results | Should -BeLike "Started 'CIPP OneDrive site permissions *"
    }

    It 'starts a user permissions report from autocomplete values' {
        $Body = @{
            Action     = 'Create'
            ReportType = [pscustomobject]@{ value = 'UserPermissions'; label = 'User permissions' }
            Workload   = [pscustomobject]@{ value = 'sharePoint'; label = 'SharePoint' }
            Users      = @([pscustomobject]@{ value = 'a@contoso.com'; label = 'A' })
        }

        $Response = Invoke-ExecSharePointAccessReport -Request (New-ExecRequest -Body $Body)

        $Response.StatusCode | Should -Be 200
        $script:Calls[0].Path | Should -Be '/createPermissionsReport'
        $Sent = $script:Calls[0].Body | ConvertFrom-Json
        $Sent.entity | Should -Be 'UserPermissions'
        $script:Calls[0].Body.Contains('"userEmailList":["a@contoso.com"]') | Should -BeTrue
    }

    It 'deletes a report by id' {
        $Response = Invoke-ExecSharePointAccessReport -Request (New-ExecRequest -Body @{ Action = 'Delete'; ReportId = $script:ReportId })

        $Response.StatusCode | Should -Be 200
        $script:Calls[0].Path | Should -Be "/$script:ReportId"
        $script:Calls[0].Method | Should -Be 'DELETE'
    }

    It 'returns 400 when Microsoft refuses the request' {
        Mock Invoke-CIPPSPOAccessReportRequest { throw [System.ArgumentException]::new('no licence') }

        $Response = Invoke-ExecSharePointAccessReport -Request (New-ExecRequest -Body @{ Action = 'Create'; ReportType = 'SitePermissions'; Workload = 'sharePoint' })

        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -Be 'Failed to start the access report: no licence'
    }
}
