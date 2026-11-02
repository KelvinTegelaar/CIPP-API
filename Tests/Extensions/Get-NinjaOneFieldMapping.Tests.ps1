BeforeAll {
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/NinjaOne/Get-NinjaOneFieldMapping.ps1"

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-AzDataTableEntity { @{ config = '{"NinjaOne":{"Instance":"eu.ninjarmm.com"}}' } }
    function Get-ExtensionMapping { param($Extension) }
    function Get-NinjaOneToken { param($configuration) @{ access_token = 'x' } }
}

Describe 'Get-NinjaOneFieldMapping' {
    It 'offers mapped write-only fields as options typed like the CIPP field they belong to' {
        Mock Get-CIPPAzDataTableEntity { }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*scopes=node*' } { [pscustomobject]@{ content = '[{"label":"Microsoft 365 Device Links","name":"microsoft365DeviceLinks","type":"WYSIWYG","apiPermission":"READ_WRITE"}]' } }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -like '*scopes=organization*' } { [pscustomobject]@{ content = '[]' } }
        Mock Get-ExtensionMapping {
            @([pscustomobject]@{ RowKey = 'LAPSPassword'; IntegrationId = 'cippLapsPassword'; IntegrationName = 'Windows LAPS Password' },
              [pscustomobject]@{ RowKey = 'BitLockerKeyIds'; IntegrationId = 'cippBitLockerKeyIds'; IntegrationName = 'BitLocker Key IDs' },
              [pscustomobject]@{ RowKey = 'DeviceLinks'; IntegrationId = 'microsoft365DeviceLinks'; IntegrationName = 'Microsoft 365 Device Links' })
        }

        $Result = Get-NinjaOneFieldMapping -CIPPMapping @{}

        ($Result.IntegrationFields | Where-Object value -EQ 'cippLapsPassword').type | Should -Be 'TEXT_ENCRYPTED'
        ($Result.IntegrationFields | Where-Object value -EQ 'cippBitLockerKeyIds').type | Should -Be 'TEXT_MULTILINE'
        @($Result.IntegrationFields | Where-Object value -EQ 'microsoft365DeviceLinks').Count | Should -Be 1
    }
}
