function Remove-CIPPUser {
    [CmdletBinding()]
    param (
        $Headers,
        [parameter(Mandatory = $true)]
        [string]$UserID,
        [string]$Username,
        $APIName = 'Remove User',
        $TenantFilter
    )



    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserID)" -type DELETE -tenant $TenantFilter
        $Result = "Successfully deleted user with ID: '$UserID'"
        if (-not [string]::IsNullOrEmpty($Username)) { $Result += " and Username: '$Username'" }
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to delete user with ID: '$UserID'. Error: $($ErrorMessage.NormalizedError)"
        if (-not [string]::IsNullOrEmpty($Username)) { $Result += " and Username: '$Username'" }
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

