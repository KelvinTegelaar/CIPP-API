function Write-CippFunctionStats {
    <#
    .FUNCTIONALITY
    Internal
    #>
    Param(
        [string]$FunctionType,
        $Entity,
        [DateTime]$Start,
        [DateTime]$End,
        [string]$ErrorMsg = ''
    )
    try {
        $Table = Get-CIPPTable -tablename CippFunctionStats
        $RowKey = [string](New-Guid).Guid
        $TimeSpan = New-TimeSpan -Start $Start -End $End
        $Duration = [int]$TimeSpan.TotalSeconds

        $StatEntity = @{}
        # Flatten data to json string
        $StatEntity.PartitionKey = $FunctionType
        $StatEntity.RowKey = $RowKey
        $StatEntity.Start = $Start
        $StatEntity.End = $End
        $StatEntity.Duration = $Duration
        $StatEntity.ErrorMsg = $ErrorMsg
        $Entity = [PSCustomObject]$Entity
        foreach ($Property in $Entity.PSObject.Properties.Name) {
            if ($Entity.$Property.GetType().Name -in ('Hashtable', 'PSCustomObject')) {
                $StatEntity.$Property = [string]($Entity.$Property | ConvertTo-Json -Compress)
            }
        }
        $StatsEntity = [PSCustomObject]$StatsEntity
        Write-Host ($StatEntity | ConvertTo-Json)
        Add-CIPPAzDataTableEntity @Table -Entity $StatsEntity -Force
    } catch {
        Write-Host "Exception logging stats $($_.Exception.Message)"
    }
}
