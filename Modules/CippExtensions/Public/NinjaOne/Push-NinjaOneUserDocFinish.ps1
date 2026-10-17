function Push-NinjaOneUserDocFinish {
    <#
    .SYNOPSIS
        Post-execution for a tenant's NinjaOne user document chunks: records the end of the tenant's sync

    .DESCRIPTION
        Totals the chunk results, removes staged rows a chunk left behind and sets the NinjaOne mapping's end
        time and status, which the tenant sync leaves open when it fans its user documents out.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Parameters = $Item.Parameters
    $Totals = [ordered]@{ Users = 0; Written = 0; SkipContent = 0; Failed = 0; Unsent = 0; Errors = 0 }
    foreach ($Result in @($Item.Results)) {
        foreach ($Chunk in @($Result)) {
            if ($null -eq $Chunk -or $null -eq $Chunk.Chunk) { continue }
            foreach ($Key in 'Users', 'Written', 'SkipContent', 'Failed', 'Unsent') { $Totals[$Key] = $Totals[$Key] + [int]$Chunk.$Key }
            if ($Chunk.Error) { $Totals.Errors++ }
        }
    }
    try {
        $StageTable = Get-CippTable -tablename 'NinjaOneUserDocStage'
        $Leftover = @(Get-CIPPAzDataTableEntity @StageTable -Filter "PartitionKey eq '$($Parameters.RunPartition)'" -Property PartitionKey, RowKey)
        if ($Leftover) { Remove-CIPPAzDataTableEntity -Force @StageTable -Entity $Leftover }

        # A tenant sync that failed after fanning out has already recorded its end; the chunks do not overwrite that
        $MappingTable = Get-CIPPTable -TableName CippMapping
        $Mapping = Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq 'NinjaOneMapping' and RowKey eq '$($Parameters.CustomerId)'"
        if ($Mapping -and $Mapping.lastStatus -ne 'Failed') {
            Add-CIPPAzDataTableEntity @MappingTable -OperationType UpsertMerge -Entity @{
                PartitionKey = 'NinjaOneMapping'
                RowKey       = [string]$Parameters.CustomerId
                lastEndTime  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                lastStatus   = if ($Totals.Errors) { 'Failed' } else { 'Completed' }
            }
        }
        $Message = "NinjaOne user documents for $($Parameters.DisplayName): $($Totals.Users) of $($Parameters.Users) staged users in $($Parameters.Chunks) chunks processed, $($Totals.Written) written, $($Totals.SkipContent) unchanged, $($Totals.Failed) failed, $($Totals.Unsent) left for the next sync"
        Write-LogMessage -tenant $Parameters.TenantFilter -API 'NinjaOneSync' -message $Message -Sev $(if ($Totals.Errors -or $Totals.Failed) { 'Warning' } else { 'Info' })
    } catch {
        Write-LogMessage -tenant $Parameters.TenantFilter -API 'NinjaOneSync' -message "Failed to finish the NinjaOne user document run for $($Parameters.DisplayName): $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }
    $Totals
}
