function Get-ExtensionRateLimit($ExtensionName, $ExtensionPartitionKey, $RateLimit, $WaitTime) {
    
    $MappingTable = Get-CIPPTable -TableName CippMapping
    $CurrentMap = (Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq '$ExtensionPartitionKey'")

    # Check Global Rate Limiting
    try {
    $ActiveJobs = $CurrentMap | Where-Object { ($Null -ne $_.lastStartTime -or $_.lastStartTime -gt (Get-Date).AddMinutes(-10)) -and ($Null -eq $_.lastEndTime -or $_.lastStartTime -gt $_.lastEndTime) }
    } catch {
        $ActiveJobs = 'FirstRun'
    }
    if (($ActiveJobs | Measure-Object).count -ge $RateLimit) {
        Write-LogMessage -API 'ExtensionRateLimiting' -user 'CIPP' -message "$ExtensionName Rate Limited" -Sev 'Info'
        Write-Host "Rate Limiting"
        Start-Sleep -Seconds $WaitTime
        $CurrentMap = Get-ExtensionRateLimit -ExtensionName $ExtensionName -ExtensionPartitionKey $ExtensionPartitionKey -RateLimit $RateLimit -WaitTime $WaitTime
    }

    Return $CurrentMap

}