function Add-CIPPSSOAppSecret {
    <#
    .SYNOPSIS
        Creates a client secret on the CIPP-SSO app registration with retry.
    .DESCRIPTION
        Adds a new password credential to the given app object via Graph. Retries up to
        MaxRetries times with backoff because Entra propagation can take a few seconds
        after the app is freshly created or its app-management-policy exemption is set.
        Throws on final failure so callers can persist Status=error + LastError.
    .PARAMETER ObjectId
        Graph object ID of the application (NOT the appId/clientId).
    .PARAMETER DisplayName
        Display name to set on the password credential. Defaults to 'CIPP-SSO-Secret'.
    .PARAMETER MaxRetries
        Number of secret-creation attempts before giving up. Defaults to 5.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName = 'CIPP-SSO-Secret',

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 5
    )

    $SecretText = $null
    $SecretAttempt = 0
    $BackoffSchedule = @(2, 5, 10, 15, 30)
    $LastException = $null

    while ($SecretAttempt -lt $MaxRetries -and -not $SecretText) {
        try {
            $PasswordBody = @{ passwordCredential = @{ displayName = $DisplayName } } | ConvertTo-Json -Compress
            $PasswordResult = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$ObjectId/addPassword" -body $PasswordBody -type POST -NoAuthCheck $true -AsApp $true
            $SecretText = $PasswordResult.secretText
            Write-Information "[SSO-Secret] Client secret created on objectId $ObjectId"
        } catch {
            $SecretAttempt++
            $LastException = $_
            Write-Warning "[SSO-Secret] Secret creation attempt $SecretAttempt/$MaxRetries failed: $($_.Exception.Message)"
            if ($SecretAttempt -lt $MaxRetries) {
                $Delay = $BackoffSchedule[[Math]::Min($SecretAttempt - 1, $BackoffSchedule.Count - 1)]
                Start-Sleep -Seconds $Delay
            }
        }
    }

    if (-not $SecretText) {
        $InnerMessage = if ($LastException) { $LastException.Exception.Message } else { 'unknown error' }
        throw "Failed to create client secret for CIPP-SSO after $MaxRetries attempts: $InnerMessage"
    }

    return $SecretText
}
