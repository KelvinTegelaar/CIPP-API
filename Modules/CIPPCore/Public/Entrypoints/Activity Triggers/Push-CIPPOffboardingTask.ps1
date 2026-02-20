function Push-CIPPOffboardingTask {
    <#
    .SYNOPSIS
        Generic wrapper to execute individual offboarding task cmdlets

    .DESCRIPTION
        Executes the specified cmdlet with the provided parameters as part of user offboarding

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Cmdlet = $Item.Cmdlet
    $Parameters = $Item.Parameters | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable

    try {
        Write-Information "Executing offboarding cmdlet: $Cmdlet"

        # Check if cmdlet exists
        $CmdletInfo = Get-Command -Name $Cmdlet -ErrorAction SilentlyContinue
        if (-not $CmdletInfo) {
            throw "Cmdlet $Cmdlet does not exist"
        }

        # Execute the cmdlet with splatting
        $Result = & $Cmdlet @Parameters

        Write-Information "Completed $Cmdlet successfully"
        return $Result

    } catch {
        $ErrorMsg = "Failed to execute $Cmdlet : $($_.Exception.Message)"
        Write-Information $ErrorMsg
        return $ErrorMsg
    }
}
