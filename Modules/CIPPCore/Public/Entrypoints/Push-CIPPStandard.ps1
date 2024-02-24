function Push-CIPPStandard {
    param (
        $QueueItem, $TriggerMetadata
    )

    Write-Host "Received queue item for $($QueueItem.Tenant) and standard $($QueueItem.Standard)."
    $Tenant = $QueueItem.Tenant
    $Standard = $QueueItem.Standard
    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard
    Write-Host "We'll be running $FunctionName"
    try {
        & $FunctionName -Tenant $Tenant -Settings $QueueItem.Settings -ErrorAction Stop
    } catch {
        throw $_.Exception.Message
    }
}
