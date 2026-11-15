# Pester tests for Set-CIPPDBCacheAutopilotDeviceModels
# Unique manufacturer/model pairs go into one global table; only pairs not seen before are written.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Tools/Get-StringHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheAutopilotDeviceModels.ps1')
}

Describe 'Set-CIPPDBCacheAutopilotDeviceModels' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Test-CIPPStandardLicense { $true }
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Get-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ manufacturer = 'LENOVO'; model = '21HD0012MH'; serialNumber = 'PF1' }
            [pscustomobject]@{ manufacturer = 'LENOVO'; model = '21HD0012MH'; serialNumber = 'PF2' }
            [pscustomobject]@{ manufacturer = 'Dell Inc.'; model = 'Latitude 5440'; serialNumber = 'D1' }
            [pscustomobject]@{ manufacturer = 'Dell Inc.'; model = 'LATITUDE 5440'; serialNumber = 'D2' }
            [pscustomobject]@{ manufacturer = ''; model = 'Unknown'; serialNumber = 'X1' }
        }
    }

    It 'writes each unique pair once, keeps exact strings and stores no serials' {
        Set-CIPPDBCacheAutopilotDeviceModels -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Force -and @($Entity).Count -eq 3 -and
            @($Entity).Model -ccontains '21HD0012MH' -and @($Entity).Model -ccontains 'Latitude 5440' -and @($Entity).Model -ccontains 'LATITUDE 5440' -and
            -not (@($Entity) | Where-Object { $_.ContainsKey('serialNumber') })
        }
    }

    It 'skips pairs already in the table' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ RowKey = (Get-StringHash -String 'LENOVO|21HD0012MH') }
            [pscustomobject]@{ RowKey = (Get-StringHash -String 'Dell Inc.|Latitude 5440') }
        }

        Set-CIPPDBCacheAutopilotDeviceModels -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { @($Entity).Count -eq 1 -and $Entity[0].Model -ceq 'LATITUDE 5440' }
    }

    It 'writes nothing when every pair is already known' {
        Mock New-GraphGetRequest { [pscustomobject]@{ manufacturer = 'LENOVO'; model = '21HD0012MH' } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = (Get-StringHash -String 'LENOVO|21HD0012MH') } }

        Set-CIPPDBCacheAutopilotDeviceModels -TenantFilter 'contoso.com'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'does not read Graph or the table for unlicensed tenants' {
        Mock Test-CIPPStandardLicense { $false }

        Set-CIPPDBCacheAutopilotDeviceModels -TenantFilter 'contoso.com'

        Should -Invoke New-GraphGetRequest -Times 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'is collected with the Intune group' {
        (Get-CIPPDBCacheSchedule).Intune.Types | Should -Contain 'AutopilotDeviceModels'
    }
}
