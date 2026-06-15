function Set-CippMaxEmailSize {
    [CmdletBinding()]
    param (
        $Headers,
        $TenantFilter,
        $APIName = 'Mailbox Max Send/Receive Size',
        $UserPrincipalName,
        $UserID,
        [ValidateRange(1, 150)]
        [Int32]$MaxSendSize,
        [ValidateRange(1, 150)]
        [Int32]$MaxReceiveSize
    )

    try {
        # Id the ID is provided, use it. Otherwise, use the UPN
        $Identity = $UserID ?? $UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($Identity)) {
            $Result = 'No identity provided. Cannot set mailbox email max size.'
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter
            throw $Result
        }

        if ($MaxSendSize -eq 0 -and $MaxReceiveSize -eq 0) {
            $Result = 'No max send or receive size provided. Cannot set mailbox email max size.'
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter
            throw $Result
        }

        $cmdletParams = @{
            Identity = $Identity
        }
        # Set the max send and receive size if they are provided. Convert to bytes
        if ($MaxSendSize -gt 0) { $cmdletParams['MaxSendSize'] = $MaxSendSize * 1MB }
        if ($MaxReceiveSize -gt 0) { $cmdletParams['MaxReceiveSize'] = $MaxReceiveSize * 1MB }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams $cmdletParams

        # Use UPN for logging if provided
        $Identity = $UserPrincipalName ?? $UserID
        $Result = "Set mailbox email max size for $($Identity) to "
        if ($MaxSendSize -gt 0) { $Result += "Send: $($MaxSendSize)MB " }
        if ($MaxReceiveSize -gt 0) { $Result += "Receive: $($MaxReceiveSize)MB" }

        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_

        # Use UPN for logging if provided
        $Identity = $UserPrincipalName ?? $UserID
        $Result = "Failed to set mailbox email max size for $($Identity). Error: $($ErrorMessage)"

        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
