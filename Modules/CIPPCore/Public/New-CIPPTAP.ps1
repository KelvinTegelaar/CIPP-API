function New-CIPPTAP {
    [CmdletBinding()]
    param (
        $userid,
        $TenantFilter,
        $APIName = 'Create TAP',
        $ExecutingUser
    )


    try {
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/authentication/temporaryAccessPassMethods" -tenantid $TenantFilter -type POST -body '{}' -verbose
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Created Temporary Access Password (TAP) for $userid" -Sev 'Info' -tenant $TenantFilter
        return [pscustomobject]@{ resultText = "The TAP for this user is $($GraphRequest.temporaryAccessPass) - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes"
            copyField                        = $($GraphRequest.temporaryAccessPass)
            state                            = 'success'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Failed to created TAP for $($userid): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        Return [pscustomobject]@{ resultText = "Failed to create TAP: $($ErrorMessage.NormalizedError)"
            state                            = 'error'
        }


    }

}

