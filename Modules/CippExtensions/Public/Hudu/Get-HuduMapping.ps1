function Get-HuduMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Mappings = Get-ExtensionMapping -Extension 'Hudu'

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
        Tenants   = @($Tenants)
        Companies = @($HuduCompanies)
        Mappings  = $Mappings
    }

    return $MappingObj

}
