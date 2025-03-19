function Clear-CIPPImmutableId {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $userid,
        $Headers,
        $APIName
    )

    try {
        $Body = [pscustomobject]@{ onPremisesImmutableId = $null }
        $Body = ConvertTo-Json -InputObject $Body -Depth 5 -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$userid" -tenantid $TenantFilter -type PATCH -body $Body
        Write-LogMessage -headers $Headers -API $APIName -message "Successfully cleared immutable ID for $userid" -sev Info
        return 'Successfully cleared immutable ID for user.'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Could not clear immutable ID for $($userid): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -sev Error -LogData $ErrorMessage
        return $Message
    }
}
