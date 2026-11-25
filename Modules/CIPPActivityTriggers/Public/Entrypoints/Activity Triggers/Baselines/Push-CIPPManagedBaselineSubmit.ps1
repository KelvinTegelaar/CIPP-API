function Push-CIPPManagedBaselineSubmit {
    <#
    .SYNOPSIS
        PostExecution for a custom managed baseline request: send the collected snapshot to CyberDrain.
    .DESCRIPTION
        Runs once after every standard has been compared. Sends what the partner typed and the
        redacted results, then moves the request to 'Waiting on CyberDrain'. A failure leaves
        the request 'Failed' with the reason; Retry starts the collection again.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $RequestId = "$($Item.Parameters.RequestId)"
    $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
    $SafeId = ConvertTo-CIPPODataFilterValue -Value $RequestId
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request' and RowKey eq '$SafeId'" | Select-Object -First 1
    # Cancelled while the standards were being compared: there is nothing to send.
    if (-not $Row) { return }

    $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $Changes = @{ PartitionKey = 'request'; RowKey = $RequestId; CollectedAt = $Now }
    try {
        $Row | Add-Member -NotePropertyName CollectedAt -NotePropertyValue $Now -Force
        $Body = Get-CIPPManagedBaselineRequestBody -Row $Row
        if (@($Body.standards).Count -eq 0) { throw 'no standard could be compared.' }
        $Answer = Invoke-ManagedBaselinesRequest -Path 'requests' -Method POST -Body $Body
        $Changes.Status = 'Waiting on CyberDrain'
        $Changes.RemoteStatus = "$($Answer.status)"
        $Changes.SubmittedAt = $Now
        $Changes.Error = ''
        Write-LogMessage -API 'ManagedBaselines' -tenant $Row.TenantFilter -message "Sent the custom managed baseline request for $($Row.TenantFilter) to CyberDrain: $(@($Body.standards).Count) standards compared." -Sev 'Info'
    } catch {
        $Changes.Status = 'Failed'
        $Changes.Error = "Sending the snapshot to CyberDrain failed: $($_.Exception.Message)"
        Write-LogMessage -API 'ManagedBaselines' -tenant $Row.TenantFilter -message "The custom managed baseline request for $($Row.TenantFilter) could not be sent to CyberDrain: $($_.Exception.Message)" -Sev 'Error'
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Changes -OperationType UpsertMerge
}
