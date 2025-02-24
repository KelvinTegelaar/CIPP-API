function New-CIPPTAP {
    [CmdletBinding()]
    param (
        $userid,
        $TenantFilter,
        $APIName = 'Create TAP',
        $Headers
    )

    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/authentication/temporaryAccessPassMethods" -tenantid $TenantFilter -type POST -body '{}' -verbose
        Write-LogMessage -headers $Headers -API $APIName -message "Created Temporary Access Password (TAP) for $userid" -Sev 'Info' -tenant $TenantFilter
        $Results = [System.Collections.Generic.List[string]]::new()
        $Results.Add("The TAP for this user is $($GraphRequest.temporaryAccessPass) - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes")
        $Results.Add("$($GraphRequest.temporaryAccessPass)")
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Temporary Access Password (TAP) for $($userid): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw @{ Results = $Result }


    }

}

