function Set-CIPPSponsor {
    [CmdletBinding()]
    param (
        $User,
        $Sponsor,
        $TenantFilter,
        $APIName = 'Set Sponsor',
        $Headers
    )

    try {
        $SponsorBody = [PSCustomObject]@{'@odata.id' = "https://graph.microsoft.com/beta/users/$($Sponsor)" }
        $SponsorBodyJSON = ConvertTo-Json -Compress -Depth 10 -InputObject $SponsorBody
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($User)/sponsors/`$ref" -tenantid $TenantFilter -type PUT -body $SponsorBodyJSON
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set $User's sponsor to $Sponsor" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to Set Sponsor. Error:$($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $_
        throw "Failed to set sponsor: $($_.Exception.Message)"
    }
    return "Set $user's sponsor to $Sponsor"
}
