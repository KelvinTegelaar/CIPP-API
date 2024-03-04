function Push-CIPPStandard {
    param (
        $Tenant,
        $Standard,
        $Settings
    )

    Write-Host "Received queue item for $Tenant and standard $Standard."
    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard
    Write-Host "We'll be running $FunctionName"
    try {
        & $FunctionName -Tenant $Tenant -Settings $Settings -ErrorAction Stop
    } catch {
        throw $_.Exception.Message
    }
}
