# Pester tests for community repository add/list hygiene.
#
# The anonymous GitHub fallback answers a missing repository with a null result rather than an
# error. Pins that Add refuses to persist in that case, and that ListCommunityRepos removes the
# nameless rows an older build already wrote (empty RowKey), which the UI cannot delete by Id.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Exec = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecCommunityRepo.ps1' -File | Select-Object -First 1 -ExpandProperty FullName
    $List = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListCommunityRepos.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Invoke-GitHubApiRequest { param($Path, $Method, $Body, $Accept) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Push-CIPPTemplateToRepo { param($GUID, $FullName, $Message, $Branch) }
    function Push-CIPPBaselineToRepo { param($GUID, $FullName, $Message, $Branch) }

    . $Exec
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippErrorStatusCode.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)
    . $List
}

Describe 'Invoke-ExecCommunityRepo Add' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity { }
    }

    It 'refuses to persist when GitHub returns nothing for the repository' {
        Mock Invoke-GitHubApiRequest { $null }
        $Response = Invoke-ExecCommunityRepo -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecCommunityRepo' }
                Headers = @{}
                Body    = [pscustomobject]@{ Action = 'Add'; FullName = 'nobody/missing'; TemplateTypes = @('ConditionalAccess') }
            })
        $Response.Body.Results.state | Should -Be 'error'
        $Response.Body.Results.resultText | Should -Match "'nobody/missing' was not found"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'persists a repository GitHub does know' {
        Mock Invoke-GitHubApiRequest { [pscustomobject]@{ id = 42; name = 'repo'; full_name = 'owner/repo'; html_url = 'https://github.com/owner/repo'; owner = @{ login = 'owner' }; visibility = 'public'; default_branch = 'main'; permissions = @{ push = $false } } }
        $Response = Invoke-ExecCommunityRepo -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecCommunityRepo' }
                Headers = @{}
                Body    = [pscustomobject]@{ Action = 'Add'; FullName = 'owner/repo' }
            })
        $Response.Body.Results.state | Should -Be 'success'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq '42' -and $Entity.FullName -eq 'owner/repo' }
    }
}

Describe 'Invoke-ExecCommunityRepo upload status codes' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ FullName = 'Org/repo'; DefaultBranch = 'main' } }
    }

    It 'returns <Code> for <Action> when <Case>' -ForEach @(
        @{ Action = 'UploadTemplate'; Helper = 'Push-CIPPTemplateToRepo'; Case = 'the template is missing'; Code = 404; Mock = { throw [System.Management.Automation.ItemNotFoundException]::new("Template 'g' not found") } }
        @{ Action = 'UploadBaseline'; Helper = 'Push-CIPPBaselineToRepo'; Case = 'the baseline is missing'; Code = 404; Mock = { throw [System.Management.Automation.ItemNotFoundException]::new("Baseline 'g' not found") } }
        @{ Action = 'UploadTemplate'; Helper = 'Push-CIPPTemplateToRepo'; Case = 'the push does not land'; Code = 500; Mock = { @{ resultText = 'not pushed'; state = 'error' } } }
        @{ Action = 'UploadBaseline'; Helper = 'Push-CIPPBaselineToRepo'; Case = 'GitHub throws'; Code = 500; Mock = { throw 'GitHub API is down' } }
        @{ Action = 'UploadTemplate'; Helper = 'Push-CIPPTemplateToRepo'; Case = 'the push succeeds'; Code = 200; Mock = { @{ resultText = 'uploaded'; state = 'success' } } }
    ) {
        Mock $Helper $Mock
        $Response = Invoke-ExecCommunityRepo -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecCommunityRepo' }
                Headers = @{}
                Body    = [pscustomobject]@{ Action = $Action; FullName = 'Org/repo'; GUID = 'g' }
            })
        $Response.StatusCode | Should -Be $Code
        $Response.Body.Results.state | Should -Be $(if ($Code -eq 200) { 'success' } else { 'error' })
    }
}

Describe 'Invoke-ListCommunityRepos ghost rows' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Remove-AzDataTableEntity { }
    }

    It 'deletes rows with an empty RowKey and leaves them out of the response' {
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ PartitionKey = 'CommunityRepos'; RowKey = ''; ETag = 'e1'; TemplateTypes = '["ConditionalAccess"]' }
                [pscustomobject]@{ PartitionKey = 'CommunityRepos'; RowKey = '42'; ETag = 'e2'; Name = 'repo'; FullName = 'owner/repo'; URL = 'https://github.com/owner/repo' }
            )
        }
        $Response = Invoke-ListCommunityRepos -Request ([pscustomobject]@{ Query = @{ WriteAccess = $true } })
        Should -Invoke Remove-AzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq '' -and $Entity.ETag -eq 'e1' }
        @($Response.Body.Results).Count | Should -Be 1
        $Response.Body.Results[0].Id | Should -Be '42'
    }
}
