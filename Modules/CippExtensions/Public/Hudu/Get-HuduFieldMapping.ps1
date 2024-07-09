function Get-HuduFieldMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )

    $Mappings = Get-ExtensionMapping -Extension 'HuduField'

    $CIPPFieldHeaders = @(
        [PSCustomObject]@{
            Title       = 'Hudu Asset Layouts'
            FieldType   = 'Layouts'
            Description = 'Use the table below to map your Hudu Asset Layouts to the correct CIPP Data Type. A new Rich Text asset layout field will be created if it does not exist.'
        }
    )
    $CIPPFields = @(
        [PSCustomObject]@{
            FieldName  = 'Users'
            FieldLabel = 'Asset Layout for M365 Users'
            FieldType  = 'Layouts'
        }
        [PSCustomObject]@{
            FieldName  = 'Devices'
            FieldLabel = 'Asset Layout for M365 Devices'
            FieldType  = 'Layouts'
        }
    )

    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).Hudu
        Connect-HuduAPI -configuration $Configuration

        $AssetLayouts = Get-HuduAssetLayouts | Select-Object @{Name = 'FieldType' ; Expression = { 'Layouts' } }, @{Name = 'value'; Expression = { $_.id } }, name, fields
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get Hudu Asset Layouts, error: $Message " -Level Error -tenant 'CIPP' -API 'HuduMapping'
        $AssetLayouts = @(@{name = "Could not get Hudu Asset Layouts, error: $Message"; value = '-1' })
    }

    $Unset = [PSCustomObject]@{
        name  = '--- Do not synchronize ---'
        value = $null
        type  = 'unset'
    }

    $MappingObj = [PSCustomObject]@{
        CIPPFields        = $CIPPFields
        CIPPFieldHeaders  = $CIPPFieldHeaders
        IntegrationFields = @($Unset) + @($AssetLayouts)
        Mappings          = $Mappings
    }

    return $MappingObj

}
