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
        return @{
            resultText          = "The TAP for $userid is $($GraphRequest.temporaryAccessPass) - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes"
            userid              = $userid
            copyField           = $GraphRequest.temporaryAccessPass
            temporaryAccessPass = $GraphRequest.temporaryAccessPass
            lifetimeInMinutes   = $GraphRequest.LifetimeInMinutes
            startDateTime       = $GraphRequest.startDateTime
            state               = 'success'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Temporary Access Password (TAP) for $($userid): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

