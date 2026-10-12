# Pester tests for Set-CIPPSPOTenant: CSOM rejects a write with HTTP 200 and ErrorInfo in the body.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Set-CIPPSPOTenant.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Set-CIPPSPOTenant.ps1 under Modules/' }

    function Get-SharePointAdminLink { param($Public, $tenantFilter) }
    function New-GraphPostRequest { param($scope, $tenantid, $Uri, $Type, $Body, $ContentType, $AddedHeaders, $AsApp, $UseCertificate) }
    function Get-CIPPTable { param($tablename) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity) }

    . $FunctionPath

    $script:State = [pscustomobject]@{ _ObjectIdentity_ = 'id'; TenantFilter = 'contoso.onmicrosoft.com'; SharepointPrefix = 'contoso'; SharepointDomain = 'sharepoint.com' }
    $script:Params = @(@{ Type = 'Boolean'; Value = $false }, @{ Type = 'Int32'; Value = 100 }, @{ Type = 'Int32'; Value = 5 })
}

Describe 'Set-CIPPSPOTenant' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { [pscustomobject]@{ RowKey = 'contoso.onmicrosoft.com' } }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
    }

    It 'throws the CSOM error when SharePoint rejects the write' {
        Mock -CommandName New-GraphPostRequest -MockWith {
            @([pscustomobject]@{ SchemaVersion = '15.0.0.0'; ErrorInfo = [pscustomobject]@{ ErrorMessage = 'The value of ExpireVersionsAfterDays must be set to 0' } })
        }
        { $script:State | Set-CIPPSPOTenant -MethodName 'SetFileVersionPolicy' -MethodParameters $script:Params } | Should -Throw '*ExpireVersionsAfterDays must be set to 0*'
        Should -Invoke -CommandName Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns the response and clears the cache on success' {
        Mock -CommandName New-GraphPostRequest -MockWith { @([pscustomobject]@{ SchemaVersion = '15.0.0.0'; ErrorInfo = $null }) }
        $R = $script:State | Set-CIPPSPOTenant -Properties @{ EmailAttestationRequired = $true }
        $R.SchemaVersion | Should -Be '15.0.0.0'
        Should -Invoke -CommandName Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
