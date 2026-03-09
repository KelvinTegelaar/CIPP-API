function Set-CIPPVacationOOO {
    param(
        [Parameter(Mandatory)] [string]$TenantFilter,
        [Parameter(Mandatory)] [ValidateSet('Add', 'Remove')] [string]$Action,
        [object[]]$Users,
        [string]$InternalMessage,
        [string]$ExternalMessage,
        [string]$APIName = 'OOO Vacation Mode',
        $Headers
    )

    $Results = [System.Collections.Generic.List[string]]::new()

    foreach ($upn in $Users) {
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }
        try {
            $SplatParams = @{
                UserID       = $upn
                TenantFilter = $TenantFilter
                State        = if ($Action -eq 'Add') { 'Enabled' } else { 'Disabled' }
                APIName      = $APIName
                Headers      = $Headers
            }
            # Only pass messages on Add — Remove only disables, preserving any messages
            # the user may have updated themselves during vacation
            if ($Action -eq 'Add') {
                if (-not [string]::IsNullOrWhiteSpace($InternalMessage)) {
                    $SplatParams.InternalMessage = $InternalMessage
                }
                if (-not [string]::IsNullOrWhiteSpace($ExternalMessage)) {
                    $SplatParams.ExternalMessage = $ExternalMessage
                }
            }
            $result = Set-CIPPOutOfOffice @SplatParams
            $Results.Add($result)
        } catch {
            $err = (Get-CippException -Exception $_).NormalizedError
            $Results.Add("Failed to set OOO for ${upn}: $err")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed OOO for ${upn}: $err" -Sev Error
        }
    }
    return $Results
}
