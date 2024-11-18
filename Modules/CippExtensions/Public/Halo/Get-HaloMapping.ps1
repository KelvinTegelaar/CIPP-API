function Get-HaloMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}

    # Migrate legacy mappings
    $Filter = "PartitionKey eq 'Mapping'"
    $MigrateRows = Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        [PSCustomObject]@{
            PartitionKey    = 'HaloMapping'
            RowKey          = $_.RowKey
            IntegrationId   = $_.HaloPSA
            IntegrationName = $_.HaloPSAName
        }
        Remove-AzDataTableEntity -Force @CIPPMapping -Entity $_ | Out-Null
    }
    if (($MigrateRows | Measure-Object).Count -gt 0) {
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $MigrateRows -Force
    }

    $Mappings = Get-ExtensionMapping -Extension 'Halo'

    $Tenants = Get-Tenants -IncludeErrors
    $Table = Get-CIPPTable -TableName Extensionsconfig
    try {
        $Configuration = ((Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).HaloPSA

        $Token = Get-HaloToken -configuration $Configuration
        $i = 1
        $RawHaloClients = do {
            $Result = Invoke-RestMethod -Uri "$($Configuration.ResourceURL)/Client?page_no=$i&page_size=999&pageinate=true" -ContentType 'application/json' -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" }
            $Result.clients | Select-Object * -ExcludeProperty logo
            $i++
            $pagecount = [Math]::Ceiling($Result.record_count / 999)
        } while ($i -le $pagecount)
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.message
        }

        Write-LogMessage -Message "Could not get HaloPSA Clients, error: $Message " -Level Error -tenant 'CIPP' -API 'HaloMapping'
        $RawHaloClients = @(@{name = "Could not get HaloPSA Clients, error: $Message"; id = '-1' })
    }
    $HaloClients = $RawHaloClients | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }
    $MappingObj = [PSCustomObject]@{
        Tenants   = @($Tenants)
        Companies = @($HaloClients)
        Mappings  = $Mappings
    }

    return $MappingObj

}