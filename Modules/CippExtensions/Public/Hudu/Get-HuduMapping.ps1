function Get-HuduMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Hudu'

    $Tenants = Get-Tenants -IncludeErrors

    $Mappings = foreach ($Mapping in $ExtensionMappings) {
        $Tenant = $Tenants | Where-Object { $_.RowKey -eq $Mapping.RowKey }
        if ($Tenant) {
            [PSCustomObject]@{
                TenantId        = $Tenant.customerId
                Tenant          = $Tenant.displayName
                TenantDomain    = $Tenant.defaultDomainName
                IntegrationId   = $Mapping.IntegrationId
                IntegrationName = $Mapping.IntegrationName
            }
        }
    }
    $Tenants = Get-Tenants -IncludeErrors
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Hudu

        Connect-HuduAPI -configuration $Configuration
        $HuduCompanies = Get-HuduCompanies

    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get Hudu Companies, error: $Message " -Level Error -tenant 'CIPP' -API 'HuduMapping'
        $HuduCompanies = @(@{name = "Could not get Hudu Companies, error: $Message"; value = '-1' })
    }
    $HuduCompanies = $HuduCompanies | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }
    $MappingObj = [PSCustomObject]@{
        Companies = @($HuduCompanies)
        Mappings  = $Mappings
    }

    return $MappingObj

}
