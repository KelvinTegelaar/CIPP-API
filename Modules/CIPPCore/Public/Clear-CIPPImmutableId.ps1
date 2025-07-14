function Clear-CIPPImmutableId {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $UserID,
        $Headers,
        $APIName = 'Clear Immutable ID'
    )

    try {
        $Body = [pscustomobject]@{ onPremisesImmutableId = $null }
        $Body = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$UserID" -tenantid $TenantFilter -type PATCH -body $Body
        $Result = "Successfully cleared immutable ID for user $UserID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Info -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to clear immutable ID for $($UserID). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}
