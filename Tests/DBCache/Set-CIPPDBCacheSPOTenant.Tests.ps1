# The two SPO collectors split their failures in two, and these tests hold that split in place.
#
# Both read the SharePoint admin SOAP endpoint, which answers 401 when the service principal has no
# SharePoint consent in the tenant. That is a standing state - it answers 401 every night until the
# CPV permissions are reset - so it is recorded and skipped rather than failing the activity.
# Everything else rethrows: swallowing it left Invoke-CIPPDBCacheCollection counting the type as a
# success and the queue reporting Completed / 0 failed while the '<Type>-Count' row kept its old
# timestamp, so a genuinely broken collector looked identical to a working one.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPSPOTenant { param($TenantFilter, [switch]$SkipCache) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSPOTenant.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSPOTenantSyncClientRestriction.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    # The shape Get-CIPPSPOTenant raises for a tenant with no SharePoint consent.
    function New-SPOAccessDeniedException {
        $Exception = [System.Exception]::new('SharePoint admin access denied for contoso.onmicrosoft.com')
        $Exception.Data['SPOAccessDenied'] = $true
        return $Exception
    }
}

Describe 'Set-CIPPDBCacheSPOTenant' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'records missing SharePoint consent as a warning without failing the activity' {
        Mock Get-CIPPSPOTenant { throw (New-SPOAccessDeniedException) }

        { Set-CIPPDBCacheSPOTenant -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Warning' -and $message -like '*SharePoint admin access denied*'
        }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }

    It 'rethrows any other failure from the admin endpoint' {
        Mock Get-CIPPSPOTenant { throw 'The remote server returned an error: (500) Internal Server Error' }

        { Set-CIPPDBCacheSPOTenant -TenantFilter $script:Tenant } | Should -Throw '*500*'
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Error' -and $message -like '*Failed to cache SPO tenant configuration*'
        }
    }

    It 'rethrows when the endpoint answers with nothing' {
        Mock Get-CIPPSPOTenant { $null }

        { Set-CIPPDBCacheSPOTenant -TenantFilter $script:Tenant } | Should -Throw '*no tenant configuration*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }

    It 'writes the configuration and stays quiet on success' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ TenantRestrictionEnabled = $true } }

        { Set-CIPPDBCacheSPOTenant -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter { $Type -eq 'SPOTenant' }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }
}

Describe 'Set-CIPPDBCacheSPOTenantSyncClientRestriction' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
    }

    It 'records missing SharePoint consent as a warning without failing the activity' {
        Mock Get-CIPPSPOTenant { throw (New-SPOAccessDeniedException) }

        { Set-CIPPDBCacheSPOTenantSyncClientRestriction -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Warning' -and $message -like '*SharePoint admin access denied*'
        }
    }

    It 'rethrows any other failure from the admin endpoint' {
        Mock Get-CIPPSPOTenant { throw 'The remote server returned an error: (500) Internal Server Error' }

        { Set-CIPPDBCacheSPOTenantSyncClientRestriction -TenantFilter $script:Tenant } |
            Should -Throw '*500*'
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
            $sev -eq 'Error' -and $message -like '*Failed to cache SPO sync client restriction*'
        }
    }

    It 'rethrows when the endpoint answers with nothing' {
        Mock Get-CIPPSPOTenant { $null }

        { Set-CIPPDBCacheSPOTenantSyncClientRestriction -TenantFilter $script:Tenant } |
            Should -Throw '*no tenant configuration*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }

    It 'projects the restriction fields and stays quiet on success' {
        Mock Get-CIPPSPOTenant {
            [PSCustomObject]@{
                TenantRestrictionEnabled = $true
                AllowedDomainList        = @('contoso.com')
                BlockMacSync             = $false
                ConditionalAccessPolicy  = 'AllowLimitedAccess'
            }
        }

        { Set-CIPPDBCacheSPOTenantSyncClientRestriction -TenantFilter $script:Tenant } | Should -Not -Throw
        Should -Invoke Add-CIPPDbItem -Times 1 -ParameterFilter {
            $Type -eq 'SPOTenantSyncClientRestriction' -and
            $Data[0].TenantRestrictionEnabled -eq $true -and
            $Data[0].ConditionalAccessPolicy -eq 'AllowLimitedAccess' -and
            $Data[0].TenantFilter -eq 'contoso.onmicrosoft.com'
        }
    }
}
