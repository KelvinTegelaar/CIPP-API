BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-GraphGetRequest { param($uri, $tenantid, $noPagination) }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CippErrorStatusCode { param($ErrorRecord) [System.Net.HttpStatusCode]::InternalServerError }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListUserGroups.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    . $FunctionPath

    function New-UserGroupsRequest {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListUserGroups' }
            Headers = @{}
            Query   = [pscustomobject]@{ tenantFilter = 'contoso.com'; userId = 'user-1' }
        }
    }
}

Describe 'Invoke-ListUserGroups' {
    It 'reads every page of the memberships' {
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'g1'; displayName = 'Group 1'; securityEnabled = $true; mailEnabled = $false; groupTypes = @() }) }
        $Response = Invoke-ListUserGroups -Request (New-UserGroupsRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        @($Response.Body)[0].DisplayName | Should -Be 'Group 1'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/users/user-1/memberOf/*' -and -not $noPagination }
    }

    It 'returns an error status when Graph fails' {
        Mock New-GraphGetRequest { throw 'Resource not found' }
        $Response = Invoke-ListUserGroups -Request (New-UserGroupsRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*Resource not found*'
    }

    It 'requires userId' {
        $Request = New-UserGroupsRequest
        $Request.Query.userId = $null
        (Invoke-ListUserGroups -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 400
    }
}
