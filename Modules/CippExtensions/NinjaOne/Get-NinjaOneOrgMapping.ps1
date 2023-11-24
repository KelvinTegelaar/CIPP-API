function Get-NinjaOneOrgMapping {
    [CmdletBinding()]
    param (
        $CIPPMapping
    )
    try {
        #Get available mappings
        $Mappings = [pscustomobject]@{}
        $Tenants = Get-Tenants

        $Filter = "PartitionKey eq 'NinjaOrgsMapping'"
        Get-AzDataTableEntity @CIPPMapping -Filter $Filter | ForEach-Object {
            $Mappings | Add-Member -NotePropertyName $_.RowKey -NotePropertyValue @{ label = "$($_.NinjaOneName)"; value = "$($_.NinjaOne)" }
        }
        #Get Available Tenants
        
        #Get available Ninja clients
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json -ea stop).NinjaOne
    
    
        $Token = Get-NinjaOneToken -configuration $Configuration
    
        $After = 0
        $PageSize = 1000
        $NinjaOrgs = do {
            $Result = (Invoke-WebRequest -uri "https://$($Configuration.Instance)/api/v2/organizations?pageSize=$PageSize&after=$After" -Method GET -Headers @{Authorization = "Bearer $($token.access_token)" } -ContentType 'application/json').content | ConvertFrom-Json -depth 100
            $Result | Select-Object name, @{n = 'value'; e = { $_.id } }
            $ResultCount = ($Result.id | Measure-Object -Maximum)
            $After = $ResultCount.maximum

        } while ($ResultCount.count -eq $PageSize) 
        
    } catch {
        $NinjaOrgs = @()
    }

    $MappingObj = [PSCustomObject]@{
        Tenants   = @($Tenants)
        NinjaOrgs = @($NinjaOrgs | Sort-Object name)
        Mappings  = $Mappings
    }

    return $MappingObj

}