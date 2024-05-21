function Get-HaloMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    #Get available mappings
    $Mappings = [pscustomobject]@{}

    $Filter = "PartitionKey eq 'Mapping'"
    Get-CIPPAzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
        $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.HaloPSAName)"; value = "$($_.HaloPSA)" }
    }
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
        $RawHaloClients = @(@{name = "Could not get HaloPSA Clients, error: $Message"; value = '-1' })
    }
    $HaloClients = $RawHaloClients | ForEach-Object {
        [PSCustomObject]@{
            name  = $_.name
            value = "$($_.id)"
        }
    }
    $MappingObj = [PSCustomObject]@{
        Tenants     = @($Tenants)
        HaloClients = @($HaloClients)
        Mappings    = $Mappings
    }

    return $MappingObj

}