function New-CIPPTAP {
    [CmdletBinding()]
    param (
        $UserID,
        $TenantFilter,
        $APIName = 'Create TAP',
        $Headers,
        $LifetimeInMinutes,
        [bool]$IsUsableOnce,
        $StartDateTime,
        [bool]$GeneratePwPushLink
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

        Write-LogMessage -headers $Headers -API $APIName -message "Created Temporary Access Pass (TAP) for $UserID$paramString" -Sev 'Info' -tenant $TenantFilter

        # Opt-in PwPush link so the TAP can be handed to the end user securely. Mirrors the
        # password reset flow: if the integration is disabled or the push fails, fall back
        # to the plain TAP rather than failing a pass that Graph has already created.
        $TapValue = $GraphRequest.temporaryAccessPass
        $UsedPwPush = $false
        if ($GeneratePwPushLink) {
            try {
                $PwPushLink = New-PwPushLink -Payload $TapValue
                if ($PwPushLink -and $PwPushLink -ne $false) {
                    $TapValue = $PwPushLink
                    $UsedPwPush = $true
                } else {
                    Write-LogMessage -headers $Headers -API $APIName -message "PwPush link was requested for the TAP of $UserID but the PwPush integration is not enabled or returned no link. Returning the plain TAP." -Sev 'Warning' -tenant $TenantFilter
                }
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to create PwPush link for the TAP of $UserID, returning the plain TAP. Error: $($_.Exception.Message)" -Sev 'Warning' -tenant $TenantFilter
            }
        }

        # Build result text with parameters
        $resultText = $UsedPwPush ? "The PwPush link for the TAP of $UserID is $TapValue - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes" : "The TAP for $UserID is $TapValue - This TAP is usable for the next $($GraphRequest.LifetimeInMinutes) minutes"
        $resultText += $GraphRequest.isUsableOnce ? ' (one-time use only)' : ''
        $resultText += $StartDateTime ? " starting at $(Get-Date $GraphRequest.startDateTime -Format 'yyyy-MM-dd HH:mm:ss') UTC" : ''

        return @{
            resultText          = $resultText
            userId              = $UserID
            copyField           = $TapValue
            temporaryAccessPass = $TapValue
            lifetimeInMinutes   = $GraphRequest.LifetimeInMinutes
            startDateTime       = $GraphRequest.startDateTime
            isUsableOnce        = $GraphRequest.isUsableOnce
            state               = 'success'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Temporary Access Pass (TAP) for $($UserID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

