# Get-CIPPSPOTenant is the only caller of the SharePoint admin SOAP endpoint, so it is where a 401
# gets a name. SharePoint issues the token happily and then refuses it when the CIPP service
# principal has no app-only consent in the tenant, which no amount of retrying changes - the whole
# point of the SPOAccessDenied flag is that callers can skip that case instead of failing on it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-SharePointAdminLink { param($Public, $tenantFilter) }
    function New-GraphPostRequest { param($scope, $tenantid, $Uri, $Type, $Body, $ContentType, $AddedHeaders) }
    function Get-CippTable { param($tablename) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSPOTenant.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Get-CIPPSPOTenant' {
    BeforeEach {
        Mock Get-SharePointAdminLink {
            @{
                TenantName      = 'contoso'
                AdminUrl        = 'https://contoso-admin.sharepoint.com'
                SharePointDomain = 'sharepoint.com'
            }
        }
        Mock Get-CippTable { @{} }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'flags a 401 as missing consent and says what fixes it' {
        Mock New-GraphPostRequest { throw '401 UNAUTHORIZED' }

        $Thrown = $null
        try {
            Get-CIPPSPOTenant -TenantFilter $script:Tenant -SkipCache
        } catch {
            $Thrown = $_.Exception
        }

        $Thrown | Should -Not -BeNullOrEmpty
        $Thrown.Data['SPOAccessDenied'] | Should -BeTrue
        $Thrown.Message | Should -BeLike '*SharePoint admin access denied for contoso.onmicrosoft.com*'
        $Thrown.Message | Should -BeLike '*CPV permissions*'
        # The original failure is kept for anyone reading the exception chain.
        $Thrown.InnerException.Message | Should -BeLike '*401*'
    }

    It 'leaves any other failure exactly as it was raised' {
        Mock New-GraphPostRequest { throw 'The remote server returned an error: (500) Internal Server Error' }

        $Thrown = $null
        try {
            Get-CIPPSPOTenant -TenantFilter $script:Tenant -SkipCache
        } catch {
            $Thrown = $_.Exception
        }

        $Thrown.Message | Should -BeLike '*500*'
        $Thrown.Data['SPOAccessDenied'] | Should -BeNullOrEmpty
    }

    It 'returns and caches the configuration on success' {
        Mock New-GraphPostRequest { [PSCustomObject]@{ TenantRestrictionEnabled = $true } }

        $Result = Get-CIPPSPOTenant -TenantFilter $script:Tenant -SkipCache

        $Result.TenantRestrictionEnabled | Should -BeTrue
        $Result.SharepointPrefix | Should -Be 'contoso'
        $Result.TenantFilter | Should -Be $script:Tenant
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }
}
