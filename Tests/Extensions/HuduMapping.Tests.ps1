BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Set-HuduMapping.ps1"
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Get-HuduMapping.ps1"

    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $headers, $message, $Sev) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) }
    function Connect-HuduAPI { param($configuration) }
    function Get-HuduCompanies { }
}

Describe 'Hudu mapping SyncPasswords flag' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
    }

    It 'stores SyncPasswords false when sent and true when omitted' {
        $Request = @{ Headers = @{}; Body = @(
                [PSCustomObject]@{ TenantId = 't1'; IntegrationId = 1; IntegrationName = 'A'; SyncPasswords = $false }
                [PSCustomObject]@{ TenantId = 't2'; IntegrationId = 2; IntegrationName = 'B' }
            )
        }
        $null = Set-HuduMapping -CIPPMapping @{} -APIName 'x' -Request $Request

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 't1' -and $Entity.SyncPasswords -eq $false }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 't2' -and $Entity.SyncPasswords -eq $true }
    }

    It 'returns SyncPasswords true for a row without the property and false when stored false' {
        Mock Get-ExtensionMapping {
            @(
                [PSCustomObject]@{ RowKey = 't1'; IntegrationId = 1; IntegrationName = 'A' }
                [PSCustomObject]@{ RowKey = 't2'; IntegrationId = 2; IntegrationName = 'B'; SyncPasswords = $false }
            )
        }
        Mock Get-Tenants {
            @(
                [PSCustomObject]@{ RowKey = 't1'; customerId = 't1'; displayName = 'One'; defaultDomainName = 'one.test' }
                [PSCustomObject]@{ RowKey = 't2'; customerId = 't2'; displayName = 'Two'; defaultDomainName = 'two.test' }
            )
        }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ config = '{}' } }
        Mock Connect-HuduAPI { }
        Mock Get-HuduCompanies { @() }

        $Result = Get-HuduMapping -CIPPMapping @{}

        ($Result.Mappings | Where-Object TenantId -eq 't1').SyncPasswords | Should -BeTrue
        ($Result.Mappings | Where-Object TenantId -eq 't2').SyncPasswords | Should -BeFalse
    }
}
