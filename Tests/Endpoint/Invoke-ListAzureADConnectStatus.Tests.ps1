BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAzureADConnectStatus.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    . $FunctionPath

    function New-AdcRequest {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListAzureADConnectStatus' }
            Headers = @{}
            Query   = [pscustomobject]@{ TenantFilter = 'contoso.com'; DataToReturn = 'AzureADObjectsInError' }
        }
    }
    function New-Item200 {
        param($Id, $Value)
        [pscustomobject]@{ id = $Id; status = 200; body = [pscustomobject]@{ value = @($Value) } }
    }
}

Describe 'Invoke-ListAzureADConnectStatus objects in error' {
    It 'returns only objects with provisioning errors' {
        Mock New-GraphBulkRequest {
            @(
                New-Item200 'users' @(
                    [pscustomobject]@{ id = 'u1'; displayName = 'Clean'; onPremisesProvisioningErrors = @() }
                    [pscustomobject]@{ id = 'u2'; displayName = 'Broken'; onPremisesProvisioningErrors = @([pscustomobject]@{ category = 'PropertyConflict'; propertyCausingError = 'UserPrincipalName' }) }
                )
                New-Item200 'contacts' @([pscustomobject]@{ id = 'c1'; displayName = 'Contact'; onPremisesProvisioningErrors = $null })
                New-Item200 'groups' @([pscustomobject]@{ id = 'g1'; displayName = 'Group'; onPremisesProvisioningErrors = @([pscustomobject]@{ category = 'PropertyConflict' }) })
            )
        }
        $Response = Invoke-ListAzureADConnectStatus -Request (New-AdcRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        @($Response.Body).id | Should -Be @('u2', 'g1')
        @($Response.Body).ObjectType | Should -Be @('user', 'group')
    }

    It 'returns an error when a sub-request fails instead of dropping that type' {
        Mock New-GraphBulkRequest {
            @(
                New-Item200 'users' @()
                [pscustomobject]@{ id = 'contacts'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
                New-Item200 'groups' @()
            )
        }
        $Response = Invoke-ListAzureADConnectStatus -Request (New-AdcRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -BeLike '*contacts: Insufficient privileges*'
    }

    It 'returns an error when a later page fails instead of a partial list' {
        Mock New-GraphBulkRequest {
            @(
                New-Item200 'users' @()
                New-Item200 'contacts' @()
                New-Item200 'groups' @() | Add-Member -NotePropertyMembers @{ PagingIncomplete = $true; PagingError = 'continuation page returned 429' } -PassThru
            )
        }
        $Response = Invoke-ListAzureADConnectStatus -Request (New-AdcRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body | Should -BeLike '*groups: continuation page returned 429*'
    }
}
