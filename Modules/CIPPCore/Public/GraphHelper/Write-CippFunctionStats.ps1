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
        
        # Flatten data to json string
        $Entity.PartitionKey = $FunctionType
        $Entity.RowKey = $RowKey
        $Entity.Start = $Start
        $Entity.End = $End
        $Entity.Duration = $Duration
        $Entity.ErrorMsg = $ErrorMsg
        $Entity = [PSCustomObject]$Entity
        foreach ($Property in $Entity.PSObject.Properties.Name) {
            if ($Entity.$Property.GetType().Name -in ('Hashtable', 'PSCustomObject')) {
                $Entity.$Property = [string]($Entity.$Property | ConvertTo-Json -Compress)
            }
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    } catch {
        Write-Host "Exception logging stats $($_.Exception.Message)"
    }
}
