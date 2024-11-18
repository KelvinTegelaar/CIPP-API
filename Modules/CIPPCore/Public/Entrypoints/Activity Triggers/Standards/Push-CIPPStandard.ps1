function Push-CIPPStandard {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param (
        $Item
    )

    Write-Information "Received queue item for $($Item.Tenant) and standard $($Item.Standard)."
    $Tenant = $Item.Tenant
    $Standard = $Item.Standard
    $FunctionName = 'Invoke-CIPPStandard{0}' -f $Standard
    Write-Information "We'll be running $FunctionName"
    $Rerun = Test-CIPPRerun -Type Standard -Tenant $Tenant -API $Standard
    if ($Rerun) {
        Write-Information 'Detected rerun. Exiting cleanly'
        exit 0
    } else {
        Write-Information "Rerun is set to false. We'll be running $FunctionName"
    }
    try {
        & $FunctionName -Tenant $Item.Tenant -Settings $Item.Settings -ErrorAction Stop
    } catch {
        throw $_.Exception.Message
    }
}
