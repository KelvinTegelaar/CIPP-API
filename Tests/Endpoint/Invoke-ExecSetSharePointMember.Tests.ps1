# Pester tests for Invoke-ExecSetSharePointMember
# Covers adding several users at once on each path, partial failures and the single-entry removal picker.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecSetSharePointMember.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecSetSharePointMember.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Add-CIPPGroupMember { param($GroupType, $GroupID, $Member, $TenantFilter, $Headers) }
    function Get-CippException { param($Exception) }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$ComplexFilter) }
    function New-GraphPostRequest { param($uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders, [switch]$UseCertificate, $AsApp) }
    function Remove-CIPPGroupMember { param($GroupType, $GroupID, $Member, $TenantFilter, $Headers) }
    function Resolve-CIPPSharePointRestContext { param($TenantFilter, $SiteUrl) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }

    . $FunctionPath

    function New-TestRequest {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSetSharePointMember' }
            Headers = @{ Authorization = 'token' }
            Body    = ($Body | ConvertTo-Json -Depth 5 | ConvertFrom-Json)
        }
    }
    function New-UserOption {
        param($Upn, $AddedFields = @{ id = 'id' })
        @{ label = $Upn; value = $Upn; addedFields = $AddedFields }
    }
}

Describe 'Invoke-ExecSetSharePointMember' {
    BeforeEach {
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Resolve-CIPPSharePointRestContext -MockWith {
            [pscustomobject]@{ Scope = 'https://contoso.sharepoint.com/.default'; Headers = @{}; BaseUri = "$SiteUrl/_api" }
        }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = "id-of-$(($uri -split '/users/')[1] -replace '\?.*')" } }
        Mock -CommandName New-GraphPostRequest -MockWith {
            if ($uri -like '*/ensureuser') {
                $Logon = ($body | ConvertFrom-Json).logonName
                return [pscustomobject]@{ Id = 7; LoginName = $Logon }
            }
        }
        Mock -CommandName Add-CIPPGroupMember -MockWith { "Successfully added $($Member -join ', ') to group Site." }
        Mock -CommandName Remove-CIPPGroupMember -MockWith { "Successfully removed $($Member -join ', ') from group Site." }
    }

    It 'adds several users to a classic site role group in one call' {
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Members'; SharePointType = 'Sts'
            URL = 'https://contoso.sharepoint.com/sites/hr'; GroupID = 'owner@contoso.com'
            user = @((New-UserOption 'a@contoso.com'), (New-UserOption 'b@contoso.com'))
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results).Count | Should -Be 2
        $Response.Body.Results | Should -Contain 'Successfully added a@contoso.com as a member of https://contoso.sharepoint.com/sites/hr.'
        Should -Invoke New-GraphPostRequest -Times 2 -Exactly -ParameterFilter { $uri -like '*/web/associatedmembergroup/users' }
        Should -Invoke Resolve-CIPPSharePointRestContext -Times 1 -Exactly
    }

    It 'keeps going when one user fails and reports each outcome' {
        Mock -CommandName New-GraphPostRequest -MockWith { throw 'User not found' } -ParameterFilter { $uri -like '*/ensureuser' -and $body -like '*bad@contoso.com*' }
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Visitors'; SharePointType = 'Sts'
            URL = 'https://contoso.sharepoint.com/sites/hr'
            user = @((New-UserOption 'bad@contoso.com'), (New-UserOption 'good@contoso.com'))
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.Results[0] | Should -BeLike 'Failed to add bad@contoso.com*'
        $Response.Body.Results[1] | Should -Be 'Successfully added good@contoso.com as a visitor of https://contoso.sharepoint.com/sites/hr.'
    }

    It 'returns BadRequest when every user fails' {
        Mock -CommandName New-GraphPostRequest -MockWith { throw 'User not found' } -ParameterFilter { $uri -like '*/ensureuser' }
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Members'; SharePointType = 'Sts'
            URL = 'https://contoso.sharepoint.com/sites/hr'
            user = @((New-UserOption 'x@contoso.com'), (New-UserOption 'y@contoso.com'))
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        @($Response.Body.Results).Count | Should -Be 2
    }

    It 'passes all users to Add-CIPPGroupMember for members of a group-connected site' {
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Members'; SharePointType = 'Group'
            GroupID = '11111111-2222-3333-4444-555555555555'
            user = @((New-UserOption 'a@contoso.com'), (New-UserOption 'b@contoso.com'))
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly -ParameterFilter {
            ($Member -join ',') -eq 'a@contoso.com,b@contoso.com' -and $GroupID -eq '11111111-2222-3333-4444-555555555555'
        }
    }

    It 'adds each user as an owner of the M365 group on a group-connected site' {
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Owners'; SharePointType = 'Group'
            GroupID = '11111111-2222-3333-4444-555555555555'
            user = @((New-UserOption 'a@contoso.com'), (New-UserOption 'b@contoso.com'))
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results).Count | Should -Be 2
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/owners/$ref' -and $body -like '*id-of-a@contoso.com*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/owners/$ref' -and $body -like '*id-of-b@contoso.com*' }
    }

    It 'still removes a single directly-added user from the role group picked in the removal dialog' {
        $Request = New-TestRequest @{
            tenantFilter = 'contoso.onmicrosoft.com'; Add = $false; SharePointType = 'Group'
            URL = 'https://contoso.sharepoint.com/sites/team'; GroupID = '11111111-2222-3333-4444-555555555555'
            user = (New-UserOption 'c@contoso.com' @{ Group = 'Owners'; Type = 'User' })
        }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be 'Successfully removed c@contoso.com as an owner of https://contoso.sharepoint.com/sites/team.'
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/web/associatedownergroup/users/removebyid(7)' }
        Should -Invoke Remove-CIPPGroupMember -Times 0 -Exactly
    }

    It 'returns BadRequest when no user is selected' {
        $Request = New-TestRequest @{ tenantFilter = 'contoso.onmicrosoft.com'; Add = $true; Role = 'Members'; SharePointType = 'Sts'; URL = 'https://contoso.sharepoint.com/sites/hr' }

        $Response = Invoke-ExecSetSharePointMember -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*No user was selected*'
    }
}
