function Push-NinjaOneUserDocChunk {
    <#
    .SYNOPSIS
        Writes one staged chunk of a tenant's changed NinjaOne user documents

    .DESCRIPTION
        A tenant sync with more changed users than fit one wave of document batches stages their document inputs
        in NinjaOneUserDocStage, 2000 users to a chunk, and starts a run of these tasks two at a time. Each task
        builds and writes its chunk's documents, records them in NinjaOneUserMap and removes its staged rows.
        Users it could not write keep their old fingerprint and are picked up by the next sync.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Prefix = '{0:D4}' -f [int]$Item.Chunk
    $Result = [ordered]@{ Chunk = [int]$Item.Chunk; Users = 0; Written = 0; SkipContent = 0; Failed = 0; Unsent = 0; Error = $null }
    try {
        $StageTable = Get-CippTable -tablename 'NinjaOneUserDocStage'
        $Rows = @(Get-CIPPAzDataTableEntity @StageTable -Filter "PartitionKey eq '$($Item.RunPartition)' and RowKey ge '$Prefix-' and RowKey lt '$Prefix.'")
        $Result.Users = $Rows.Count
        if ($Rows.Count -eq 0) { return $Result }

        $ExtensionTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @ExtensionTable).config | ConvertFrom-Json).NinjaOne
        $Token = Get-NinjaOneToken -configuration $Configuration
        $Customer = [PSCustomObject]@{ customerId = $Item.CustomerId; defaultDomainName = $Item.TenantFilter; displayName = $Item.DisplayName }
        $Stats = Invoke-NinjaOneUserDocWrite -Items $Rows -Configuration $Configuration -Token $Token -Customer $Customer -TemplateId $Item.TemplateId -OrganizationId $Item.OrganizationId -CIPPUrl $Item.CIPPUrl
        foreach ($Key in 'Written', 'SkipContent', 'Failed', 'Unsent') { $Result[$Key] = $Stats[$Key] }
        Remove-CIPPAzDataTableEntity -Force @StageTable -Entity @(foreach ($Row in $Rows) { [PSCustomObject]@{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey } })
    } catch {
        $Result.Error = $_.Exception.Message
        Write-LogMessage -tenant $Item.TenantFilter -API 'NinjaOneSync' -message "Failed to write NinjaOne user documents chunk $($Item.Chunk) for $($Item.DisplayName): $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }
    $Result
}
