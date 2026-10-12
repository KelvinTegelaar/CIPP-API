# Pester tests for Invoke-ExecSetSiteProperties: classic-site detection from the CSOM GroupId
# and the lock-state ordering a locked site needs.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetSiteProperties.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecSetSiteProperties.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPSPOSite { param($TenantFilter, $SiteUrl) }
    function Set-CIPPSPOSite { param($TenantFilter, $SiteUrl, $Properties) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function Invoke-SetSite {
        param($Body)
        $Body['tenantFilter'] = 'contoso.onmicrosoft.com'
        $Body['SiteUrl'] = 'https://contoso.sharepoint.com/sites/Team'
        Invoke-ExecSetSiteProperties -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecSetSiteProperties' }
                Headers = @{}
                Body    = [pscustomobject]$Body
            })
    }
}

Describe 'Invoke-ExecSetSiteProperties' {
    BeforeEach {
        $script:Sent = [System.Collections.Generic.List[string]]::new()
        $script:Site = [pscustomobject]@{ GroupId = '/Guid(00000000-0000-0000-0000-000000000000)/'; LockState = 'Unlock' }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
        Mock -CommandName Get-CIPPSPOSite -MockWith { $script:Site }
        Mock -CommandName Set-CIPPSPOSite -MockWith {
            $script:Sent.Add((@($Properties.Keys) | Sort-Object) -join ',')
            if ($script:Site.LockState -ne 'Unlock' -and $Properties.Keys -contains 'Title') {
                return [pscustomobject]@{ ErrorInfo = [pscustomobject]@{ ErrorMessage = 'Access is denied.' } }
            }
            if ($Properties.Keys -contains 'LockState') { $script:Site.LockState = $Properties['LockState'] }
        }
    }

    It 'treats an all-zero /Guid()/ GroupId as a classic site' {
        $R = Invoke-SetSite @{ Title = 'Team' }
        $R.StatusCode | Should -Be 200
        $script:Sent | Should -Be @('Title')
    }

    It 'still filters classic-only properties on a group-connected site' {
        $script:Site.GroupId = '/Guid(338e9db4-1ee3-45e6-be66-4a71ca70b247)/'
        $R = Invoke-SetSite @{ Title = 'Team'; SharingCapability = 'Disabled' }
        $script:Sent | Should -Be @('SharingCapability')
        $R.Body.Results | Should -Match 'Skipped \(not supported on group-connected sites\): Title'
    }

    It 'unlocks a locked site before applying the other properties' {
        $script:Site.LockState = 'ReadOnly'
        $R = Invoke-SetSite @{ Title = 'Team'; SharingCapability = 'Disabled'; LockState = 'Unlock' }
        $R.StatusCode | Should -Be 200
        $script:Sent | Should -Be @('LockState', 'SharingCapability,Title')
    }

    It 'applies the other properties before locking' {
        $R = Invoke-SetSite @{ Title = 'Team'; LockState = 'NoAccess' }
        $R.StatusCode | Should -Be 200
        $script:Sent | Should -Be @('Title', 'LockState')
    }

    It 'changes only the lock while the site stays locked and reports what it skipped' {
        $script:Site.LockState = 'ReadOnly'
        $R = Invoke-SetSite @{ Title = 'Team'; LockState = 'NoAccess' }
        $R.StatusCode | Should -Be 200
        $script:Sent | Should -Be @('LockState')
        $R.Body.Results | Should -Match 'Skipped while the site is locked \(ReadOnly\), unlock it to change: Title'
    }

    It 'rejects a change to a locked site that does not touch the lock' {
        $script:Site.LockState = 'NoAccess'
        $R = Invoke-SetSite @{ Title = 'Team' }
        $R.StatusCode | Should -Be 400
        $script:Sent.Count | Should -Be 0
        $R.Body.Results | Should -Match 'Unlock it before changing: Title'
    }

    It 'sends a single request when the lock does not change' {
        $R = Invoke-SetSite @{ Title = 'Team'; LockState = 'Unlock' }
        $script:Sent | Should -Be @('LockState,Title')
        $R.Body.Results | Should -Match 'Title=Team'
    }
}
