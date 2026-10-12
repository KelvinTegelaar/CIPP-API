BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity {
        [pscustomobject]@{ config = (@{ NinjaOne = @{ Instance = 'ninja.example.com' } } | ConvertTo-Json -Compress) }
    }
    function Get-NinjaOneToken { param($configuration) @{ access_token = 'token' } }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-ExtensionMapping { param($Extension) @([pscustomobject]@{ RowKey = 't1'; IntegrationId = '1' }) }
    function Get-Tenants {
        param([switch]$IncludeErrors)
        foreach ($Name in 'Already', 'Contoso', 'Fabrikam', 'Tied', 'Taken', 'DupSerial', 'Broken', 'NameOnly') {
            [pscustomobject]@{ customerId = "t$($script:TenantIds[$Name])"; displayName = $Name; defaultDomainName = "$Name.test".ToLower() }
        }
    }
    function Get-CIPPDbItem {
        param($TenantFilter, $Type)
        if ($TenantFilter -eq 'broken.test') { throw "Tenant '$TenantFilter' not found" }
        [pscustomobject]@{ RowKey = 'ManagedDevices-Count'; Data = '{}' }
        foreach ($Device in $script:IntuneDevices[$TenantFilter]) {
            [pscustomobject]@{ RowKey = [guid]::NewGuid().ToString(); Data = ($Device | ConvertTo-Json -Compress) }
        }
    }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:Added.Add($Entity) }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/NinjaOne/Invoke-NinjaOneOrgMapping.ps1')

    $script:TenantIds = @{ Already = 1; Contoso = 2; Fabrikam = 3; Tied = 4; Taken = 5; DupSerial = 6; NameOnly = 7; Broken = 8 }
    $script:Orgs = @(1..7 | ForEach-Object { @{ id = $_; name = @{ 1 = 'Already'; 2 = 'Contoso'; 3 = 'Fabrikam Pty Ltd'; 4 = 'Other'; 5 = 'Tied A'; 6 = 'Tied B'; 7 = 'Name Only Org' }[$_] } })
    $script:NinjaDevices = @(
        @{ id = 1; organizationId = 3; systemName = 'FAB-1'; system = @{ serialNumber = 'S1' } }
        @{ id = 2; organizationId = 3; systemName = 'FAB-2'; system = @{ serialNumber = 'S2' } }
        @{ id = 3; organizationId = 4; systemName = 'PC-X'; system = @{ serialNumber = 'SX' } }
        @{ id = 4; organizationId = 5; systemName = 'TIE-A'; system = @{ serialNumber = 'S3' } }
        @{ id = 5; organizationId = 6; systemName = 'TIE-B'; system = @{ serialNumber = 'S4' } }
        @{ id = 6; organizationId = 1; systemName = 'TAKEN'; system = @{ serialNumber = 'S5' } }
        @{ id = 7; organizationId = 5; systemName = 'DUP-A'; system = @{ serialNumber = 'DUP' } }
        @{ id = 8; organizationId = 6; systemName = 'DUP-B'; system = @{ serialNumber = 'DUP' } }
        @{ id = 9; organizationId = 7; systemName = 'NAMEPC'; system = @{ serialNumber = 'To Be Filled By O.E.M.' } }
    )
    $script:IntuneDevices = @{
        'fabrikam.test'  = @(@{ deviceName = 'a'; serialNumber = 'S1' }, @{ deviceName = 'b'; serialNumber = 'S2' }, @{ deviceName = 'PC-X'; serialNumber = 'nope' })
        'tied.test'      = @(@{ deviceName = 'a'; serialNumber = 'S3' }, @{ deviceName = 'b'; serialNumber = 'S4' })
        'taken.test'     = @(@{ deviceName = 'a'; serialNumber = 'S5' })
        'dupserial.test' = @(@{ deviceName = 'a'; serialNumber = 'DUP' })
        'nameonly.test'  = @(@{ deviceName = 'NAMEPC'; serialNumber = 'To Be Filled By O.E.M.' })
    }
}

Describe 'Invoke-NinjaOneOrgMapping' {
    BeforeAll {
        $script:Added = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-WebRequest {
            $Data = if ($Uri -like '*/organizations?*') { $script:Orgs } else { $script:NinjaDevices }
            [pscustomobject]@{ content = (ConvertTo-Json -InputObject @($Data) -Depth 5 -Compress) }
        }
        $script:Result = Invoke-NinjaOneOrgMapping
        $script:ByTenant = @{}
        foreach ($Row in $script:Added) { $script:ByTenant[$Row.RowKey] = $Row.IntegrationId }
    }

    It 'maps an exact organization name match' {
        $script:ByTenant['t2'] | Should -Be '2'
    }

    It 'maps by the organization owning most of the tenant devices' {
        $script:ByTenant['t3'] | Should -Be '3'
    }

    It 'falls back to device name when the serial is excluded' {
        $script:ByTenant['t7'] | Should -Be '7'
    }

    It 'skips ties, serials shared across organizations, organizations already mapped and unreadable caches' {
        $script:ByTenant.Keys | Should -Not -Contain 't4'
        $script:ByTenant.Keys | Should -Not -Contain 't5'
        $script:ByTenant.Keys | Should -Not -Contain 't6'
        $script:ByTenant.Keys | Should -Not -Contain 't8'
    }

    It 'never rewrites an existing mapping' {
        $script:ByTenant.Keys | Should -Not -Contain 't1'
        $script:Added.Count | Should -Be 3
        $script:Result | Should -BeLike '*3 new tenant mapping*'
    }
}

Describe 'Invoke-NinjaOneOrgMapping -NameOnly' {
    BeforeAll {
        $script:Added = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-WebRequest {
            [pscustomobject]@{ content = (ConvertTo-Json -InputObject @($script:Orgs) -Depth 5 -Compress) }
        }
        Invoke-NinjaOneOrgMapping -NameOnly
    }

    It 'maps by organization name without downloading devices' {
        @($script:Added.RowKey) | Should -Be @('t2')
        Should -Invoke Invoke-WebRequest -Times 0 -ParameterFilter { $Uri -like '*/devices-detailed?*' }
    }
}
