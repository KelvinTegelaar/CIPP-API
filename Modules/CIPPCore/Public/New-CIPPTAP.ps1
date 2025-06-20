function New-CIPPTAP {
    [CmdletBinding()]
    param (
        $UserID,
        $TenantFilter,
        $APIName = 'Create TAP',
        $Headers,
        $LifetimeInMinutes,
        [bool]$IsUsableOnce,
        $StartDateTime
    )

    try {
        # Build the request body based on provided parameters
        $RequestBody = @{}

        if ($LifetimeInMinutes) {
            $RequestBody.lifetimeInMinutes = [int]$LifetimeInMinutes
        }

        if ($null -ne $IsUsableOnce) {
            $RequestBody.isUsableOnce = $IsUsableOnce
        }

        if ($StartDateTime) {
            # Convert Unix timestamp to DateTime if it's a number
            if ($StartDateTime -match '^\d+$') {
                $dateTime = [DateTimeOffset]::FromUnixTimeSeconds([int]$StartDateTime).DateTime
                $RequestBody.startDateTime = Get-Date $dateTime -Format 'o'
            } else {
                # If it's already a date string, format it properly
                $dateTime = Get-Date $StartDateTime
                $RequestBody.startDateTime = Get-Date $dateTime -Format 'o'
            }
        }

        # Convert request body to JSON
        $BodyJson = if ($RequestBody) { $RequestBody | ConvertTo-Json } else { '{}' }
        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserID)/authentication/temporaryAccessPassMethods" -tenantid $TenantFilter -type POST -body $BodyJson -verbose

        # Build log message parts based on actual response values
        $logParts = [System.Collections.Generic.List[string]]::new()
        $logParts.Add("Lifetime: $($GraphRequest.lifetimeInMinutes) minutes")

        $logParts.Add($GraphRequest.isUsableOnce ? 'one-time use' : 'multi-use')

        $logParts.Add($StartDateTime ? "starts at $(Get-Date $GraphRequest.startDateTime -Format 'yyyy-MM-dd HH:mm:ss') UTC" : 'starts immediately')

        # Create parameter string for logging
        $paramString = ' with ' + ($logParts -join ', ')

        Write-LogMessage -headers $Headers -API $APIName -message "Created Temporary Access Password (TAP) for $UserID$paramString" -Sev 'Info' -tenant $TenantFilter

        # Build result text with parameters
        $resultText = "The TAP for $UserID is $($GraphRequest.temporaryAccessPass) - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes"
        $resultText += $GraphRequest.isUsableOnce ? ' (one-time use only)' : ''
        $resultText += $StartDateTime ? " starting at $(Get-Date $GraphRequest.startDateTime -Format 'yyyy-MM-dd HH:mm:ss') UTC" : ''

        return @{
            resultText          = $resultText
            userId              = $UserID
            copyField           = $GraphRequest.temporaryAccessPass
            temporaryAccessPass = $GraphRequest.temporaryAccessPass
            lifetimeInMinutes   = $GraphRequest.LifetimeInMinutes
            startDateTime       = $GraphRequest.startDateTime
            isUsableOnce        = $GraphRequest.isUsableOnce
            state               = 'success'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Temporary Access Password (TAP) for $($UserID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

