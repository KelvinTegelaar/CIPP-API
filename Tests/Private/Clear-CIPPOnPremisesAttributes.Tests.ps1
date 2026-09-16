# Pester tests for Clear-CIPPOnPremisesAttributes.
#
# The shared helper behind the Clear On-Premises Attributes action and the immutable-ID wrapper.
# Pins the PATCH body per attribute selection, the whitelist, the previous-values log entry and
# the soft-deleted-user restore path.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Clear-CIPPOnPremisesAttributes.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Clear-CIPPOnPremisesAttributes.ps1 at $FunctionPath" }

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath

    $script:AllAttributes = @(
        'onPremisesDistinguishedName', 'onPremisesDomainName', 'onPremisesImmutableId', 'onPremisesObjectIdentifier',
        'onPremisesSamAccountName', 'onPremisesSecurityIdentifier', 'onPremisesUserPrincipalName'
    )
}

Describe 'Clear-CIPPOnPremisesAttributes' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = "$($Exception.Exception.Message)" } }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                id                          = 'user-guid'
                userPrincipalName           = 'ada@contoso.com'
                onPremisesImmutableId       = 'AbCd=='
                onPremisesSamAccountName    = 'ada'
                onPremisesDistinguishedName = 'CN=ada,DC=contoso,DC=local'
            }
        }
        $script:CapturedBody = $null
        Mock -CommandName New-GraphPostRequest -MockWith { $script:CapturedBody = $body }
    }

    It 'clears every documented attribute when none are specified' {
        Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com'

        $Body = $script:CapturedBody | ConvertFrom-Json
        foreach ($Name in $script:AllAttributes) {
            $Body.PSObject.Properties.Name | Should -Contain $Name
            $Body.$Name | Should -BeNullOrEmpty
        }
        @($Body.PSObject.Properties).Count | Should -Be 7
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter {
            $type -eq 'PATCH' -and $uri -eq 'https://graph.microsoft.com/beta/users/user-guid' -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true
        }
    }

    It 'clears only the selected attribute' {
        $Result = Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com' -Attributes 'onPremisesImmutableId'

        $script:CapturedBody | Should -BeExactly '{"onPremisesImmutableId":null}'
        $Result | Should -Match 'onPremisesImmutableId'
    }

    It 'normalises the casing of a selected attribute' {
        Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com' -Attributes 'onpremisessamaccountname'

        $script:CapturedBody | Should -BeExactly '{"onPremisesSamAccountName":null}'
    }

    It 'rejects an attribute outside the documented list without PATCHing' {
        { Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com' -Attributes 'userPrincipalName' } |
            Should -Throw -ExpectedMessage '*not a clearable on-premises attribute*'

        Should -Invoke New-GraphPostRequest -Times 0
    }

    It 'records the previous values on the success log entry' {
        Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com' -Attributes 'onPremisesImmutableId', 'onPremisesSamAccountName'

        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $Sev -eq 'Info' -and $LogData.onPremisesImmutableId -eq 'AbCd==' -and $LogData.onPremisesSamAccountName -eq 'ada'
        }
    }

    It 'restores a soft-deleted user before clearing' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Request_ResourceNotFound' }
        Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*directory/deletedItems/user-guid' } -MockWith {
            [pscustomobject]@{ id = 'user-guid' }
        }

        Clear-CIPPOnPremisesAttributes -UserID 'user-guid' -TenantFilter 'contoso.com' -Attributes 'onPremisesImmutableId'

        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $type -eq 'POST' -and $uri -like '*deletedItems/user-guid/restore' }
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter { $type -eq 'PATCH' }
    }
}
