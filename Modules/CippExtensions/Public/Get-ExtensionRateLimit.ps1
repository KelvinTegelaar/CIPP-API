function Get-ExtensionRateLimit($ExtensionName, $ExtensionPartitionKey, $RateLimit, $WaitTime) {
    
    $MappingTable = Get-CIPPTable -TableName CippMapping
    $CurrentMap = (Get-CIPPAzDataTableEntity @MappingTable -Filter "PartitionKey eq '$ExtensionPartitionKey'")
    $CurrentMap | ForEach-Object {
        if ($Null -ne $_.lastEndTime -and $_.lastEndTime -ne ''){
        $_.lastEndTime = (Get-Date($_.lastEndTime))
        } else {
            $_ | Add-Member -NotePropertyName lastEndTime -NotePropertyValue $Null -Force
        }

        if ($Null -ne $_.lastStartTime -and $_.lastStartTime -ne '') {
        $_.lastStartTime = (Get-Date($_.lastStartTime))
        } else {
            $_ | Add-Member -NotePropertyName lastStartTime -NotePropertyValue $Null -Force
        }
    }

    # Check Global Rate Limiting
    try {
    $ActiveJobs = $CurrentMap | Where-Object { ($Null -ne $_.lastStartTime) -and ($_.lastStartTime -gt (Get-Date).AddMinutes(-10)) -and ($Null -eq $_.lastEndTime -or $_.lastStartTime -gt $_.lastEndTime) }
    } catch {
        $ActiveJobs = 'FirstRun'
    }
    if (($ActiveJobs | Measure-Object).count -ge $RateLimit) {
        Write-Host "Rate Limiting. Currently $($ActiveJobs.count) Active Jobs"
        Start-Sleep -Seconds $WaitTime
        $CurrentMap = Get-ExtensionRateLimit -ExtensionName $ExtensionName -ExtensionPartitionKey $ExtensionPartitionKey -RateLimit $RateLimit -WaitTime $WaitTime
    }

    Return $CurrentMap

}