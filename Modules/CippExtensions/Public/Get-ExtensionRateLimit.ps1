function Get-ExtensionRateLimit($ExtensionName, $ExtensionPartitionKey, $RateLimit, $WaitTime) {
    
    $MappingTable = Get-CIPPTable -TableName CIPPMapping
    $CurrentMap = (Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq '$ExtensionPartitionKey'")

    # Check Global Rate Limiting
    $ActiveJobs = $CurrentMap | Where-Object { $_.lastStartTime -gt (Get-Date).AddMinutes(-10) -and ($_.lastStartTime -gt $_.lastEndTime -or $Null -eq $_.lastEndTime) }
    if (($ActiveJobs | Measure-Object).count -ge $RateLimit) {
        Write-LogMessage -API 'ExtensionRateLimiting' -user 'CIPP' -message "$ExtensionName Rate Limited" -Sev 'Info'
        Start-Sleep -Seconds $WaitTime
        $CurrentMap = Get-ExtensionRateLimit -ExtensionName $ExtensionName -ExtensionPartitionKey $ExtensionPartitionKey -RateLimit $RateLimit -WaitTime $WaitTime
    }

    Return $CurrentMap

}