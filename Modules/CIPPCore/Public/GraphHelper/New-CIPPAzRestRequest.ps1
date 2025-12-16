function New-CIPPAzRestRequest {
    <#
    .SYNOPSIS
        Create and send a REST request to Azure APIs using Managed Identity authentication
    .DESCRIPTION
        Wraps Invoke-RestMethod with automatic Azure Managed Identity token authentication.
        Automatically adds the Authorization header using Get-CIPPAzIdentityToken.
        Supports all Invoke-RestMethod parameters.
    .PARAMETER Uri
        The URI of the Azure REST API endpoint
    .PARAMETER Method
        The HTTP method (GET, POST, PUT, PATCH, DELETE, etc.). Defaults to GET.
    .PARAMETER ResourceUrl
        The Azure resource URL to get a token for. Defaults to 'https://management.azure.com/' for Azure Resource Manager.
        Use 'https://vault.azure.net' for Key Vault, 'https://api.loganalytics.io' for Log Analytics, etc.
    .PARAMETER AccessToken
        Optional: A pre-acquired OAuth2 bearer token to use for Authorization. When provided, Managed Identity acquisition is skipped and this token is used as-is.
    .PARAMETER Body
        The request body (can be string, hashtable, or PSCustomObject)
    .PARAMETER Headers
        Additional headers to include in the request. Authorization header is automatically added.
    .PARAMETER ContentType
        The content type of the request body. Defaults to 'application/json' if Body is provided and ContentType is not specified.
    .PARAMETER SkipHttpErrorCheck
        Skip checking HTTP error status codes
    .PARAMETER ResponseHeadersVariable
        Variable name to store response headers
    .PARAMETER StatusCodeVariable
        Variable name to store HTTP status code
    .PARAMETER MaximumRetryCount
        Maximum number of retry attempts
    .PARAMETER RetryIntervalSec
        Interval between retries in seconds
    .PARAMETER TimeoutSec
        Request timeout in seconds
    .PARAMETER UseBasicParsing
        Use basic parsing (for older PowerShell versions)
    .PARAMETER WebSession
        Web session object for maintaining cookies/state
    .PARAMETER MaxRetries
        Maximum number of retry attempts for transient failures. Defaults to 3.
    .EXAMPLE
        New-CIPPAzRestRequest -Uri 'https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{name}?api-version=2020-06-01'
        Gets Azure Resource Manager resource using managed identity
    .EXAMPLE
        New-CIPPAzRestRequest -Uri 'https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Web/sites/{name}/config/authsettingsV2/list?api-version=2020-06-01' -Method POST
        POST request to Azure Resource Manager API
    .EXAMPLE
        New-CIPPAzRestRequest -Uri 'https://{vault}.vault.azure.net/secrets/{secret}?api-version=7.4' -ResourceUrl 'https://vault.azure.net'
        Gets a Key Vault secret using managed identity
    .EXAMPLE
        New-CIPPAzRestRequest -Uri 'https://management.azure.com/...' -Method PUT -Body @{ property = 'value' } -ContentType 'application/json'
        PUT request with JSON body
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [Alias('Url')]
        [uri]$Uri,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'TRACE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [string]$ResourceUrl = 'https://management.azure.com/',

        [Parameter(Mandatory = $false)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},

        [Parameter(Mandatory = $false)]
        [string]$ContentType = 'application/json',

        [Parameter(Mandatory = $false)]
        [switch]$SkipHttpErrorCheck,

        [Parameter(Mandatory = $false)]
        [string]$ResponseHeadersVariable,

        [Parameter(Mandatory = $false)]
        [string]$StatusCodeVariable,

        [Parameter(Mandatory = $false)]
        [int]$MaximumRetryCount,

        [Parameter(Mandatory = $false)]
        [int]$RetryIntervalSec,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSec,

        [Parameter(Mandatory = $false)]
        [switch]$UseBasicParsing,

        [Parameter(Mandatory = $false)]
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    # Resolve bearer token: prefer manually-supplied AccessToken, otherwise fetch via Managed Identity
    $Token = $null
    if ($AccessToken) {
        $Token = $AccessToken
    } else {
        try {
            $Token = Get-CIPPAzIdentityToken -ResourceUrl $ResourceUrl
        } catch {
            $errorMessage = "Failed to get Azure Managed Identity token: $($_.Exception.Message)"
            Write-Error -Message $errorMessage -ErrorAction $ErrorActionPreference
            return
        }
    }

    # Build headers - add Authorization, merge with user-provided headers
    $RequestHeaders = @{
        'Authorization' = "Bearer $Token"
    }

    # Merge user-provided headers (user headers take precedence)
    foreach ($key in $Headers.Keys) {
        $RequestHeaders[$key] = $Headers[$key]
    }

    # Handle Content-Type
    if ($Body -and -not $ContentType) {
        $ContentType = 'application/json'
    }

    # Convert Body to JSON if it's an object and ContentType is JSON
    $RequestBody = $Body
    if ($Body -and $ContentType -eq 'application/json' -and $Body -isnot [string]) {
        try {
            $RequestBody = $Body | ConvertTo-Json -Depth 10 -Compress
        } catch {
            Write-Warning "Failed to convert Body to JSON: $($_.Exception.Message). Sending as-is."
            $RequestBody = $Body
        }
    }

    # Build Invoke-RestMethod parameters
    $RestMethodParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $RequestHeaders
        ErrorAction = $ErrorActionPreference
    }

    if ($Body) {
        $RestMethodParams['Body'] = $RequestBody
    }

    if ($ContentType) {
        $RestMethodParams['ContentType'] = $ContentType
    }

    if ($SkipHttpErrorCheck) {
        $RestMethodParams['SkipHttpErrorCheck'] = $true
    }

    if ($ResponseHeadersVariable) {
        $RestMethodParams['ResponseHeadersVariable'] = $ResponseHeadersVariable
    }

    if ($StatusCodeVariable) {
        $RestMethodParams['StatusCodeVariable'] = $StatusCodeVariable
    }

    if ($MaximumRetryCount) {
        $RestMethodParams['MaximumRetryCount'] = $MaximumRetryCount
    }

    if ($RetryIntervalSec) {
        $RestMethodParams['RetryIntervalSec'] = $RetryIntervalSec
    }

    if ($TimeoutSec) {
        $RestMethodParams['TimeoutSec'] = $TimeoutSec
    }

    if ($UseBasicParsing) {
        $RestMethodParams['UseBasicParsing'] = $true
    }

    if ($WebSession) {
        $RestMethodParams['WebSession'] = $WebSession
    }

    # Invoke the REST method with retry logic
    $RetryCount = 0
    $RequestSuccessful = $false
    $Message = $null
    $MessageObj = $null

    Write-Information "$($Method.ToUpper()) [ $Uri ] | attempt: $($RetryCount + 1) of $MaxRetries"

    do {
        try {
            $Response = Invoke-RestMethod @RestMethodParams
            $RequestSuccessful = $true

            # For compatibility with Invoke-AzRestMethod behavior, return object with Content property if response is a string
            # Otherwise return the parsed object directly
            if ($Response -is [string]) {
                return [PSCustomObject]@{
                    Content = $Response
                }
            }

            return $Response
        } catch {
            $ShouldRetry = $false
            $WaitTime = 0

            # Extract error message from JSON response if available
            try {
                if ($_.ErrorDetails.Message) {
                    $MessageObj = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($MessageObj.error) {
                        $MessageObj | Add-Member -NotePropertyName 'url' -NotePropertyValue $Uri -Force
                        $Message = if ($MessageObj.error.message) {
                            Get-NormalizedError -message $MessageObj.error.message
                        } elseif ($MessageObj.error.code) {
                            $MessageObj.error.code
                        } else {
                            $_.Exception.Message
                        }
                    } else {
                        $Message = Get-NormalizedError -message $_.ErrorDetails.Message
                    }
                } else {
                    $Message = $_.Exception.Message
                }
            } catch {
                $Message = $_.Exception.Message
            }

            # If we couldn't extract a message, use the exception message
            if ([string]::IsNullOrEmpty($Message)) {
                $Message = $_.Exception.Message
                $MessageObj = @{
                    error = @{
                        code    = $_.Exception.GetType().FullName
                        message = $Message
                        url     = $Uri
                    }
                }
            }

            # Check for 429 Too Many Requests (rate limiting)
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 429) {
                $RetryAfterHeader = $_.Exception.Response.Headers['Retry-After']
                if ($RetryAfterHeader) {
                    $WaitTime = [int]$RetryAfterHeader
                    Write-Warning "Rate limited (429). Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                    $ShouldRetry = $true
                } elseif ($RetryCount -lt $MaxRetries) {
                    # Exponential backoff if no Retry-After header
                    $WaitTime = [Math]::Min([Math]::Pow(2, $RetryCount), 60)  # Cap at 60 seconds
                    Write-Warning "Rate limited (429) without Retry-After header. Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                    $ShouldRetry = $true
                }
            }
            # Check for 503 Service Unavailable or temporary errors
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 503) {
                if ($RetryCount -lt $MaxRetries) {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1  # Random sleep between 1-3 seconds
                    Write-Warning "Service unavailable (503). Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                    $ShouldRetry = $true
                }
            }
            # Check for "Resource temporarily unavailable" or other transient errors
            elseif ($Message -like '*Resource temporarily unavailable*' -or $Message -like '*temporarily*' -or $Message -like '*timeout*') {
                if ($RetryCount -lt $MaxRetries) {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1  # Random sleep between 1-3 seconds
                    Write-Warning "Transient error detected. Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                    $ShouldRetry = $true
                }
            }
            # Check for 500/502/504 server errors (retryable)
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -in @(500, 502, 504)) {
                if ($RetryCount -lt $MaxRetries) {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1  # Random sleep between 1-3 seconds
                    Write-Warning "Server error ($($_.Exception.Response.StatusCode)). Waiting $WaitTime seconds before retry. Attempt $($RetryCount + 1) of $MaxRetries"
                    $ShouldRetry = $true
                }
            }

            # Retry if conditions are met
            if ($ShouldRetry -and $RetryCount -lt $MaxRetries) {
                $RetryCount++
                if ($WaitTime -gt 0) {
                    Start-Sleep -Seconds $WaitTime
                }
                Write-Information "$($Method.ToUpper()) [ $Uri ] | attempt: $($RetryCount + 1) of $MaxRetries"
            } else {
                # Final failure - build detailed error message
                $errorMessage = "Azure REST API call failed: $Message"
                if ($_.Exception.Response) {
                    $errorMessage += " (Status: $($_.Exception.Response.StatusCode))"
                    try {
                        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                        $responseBody = $reader.ReadToEnd()
                        $reader.Close()
                        if ($responseBody) {
                            $errorMessage += "`nResponse: $responseBody"
                        }
                    } catch {
                        # Ignore errors reading response stream
                    }
                }
                $errorMessage += "`nURI: $Uri"

                Write-Error -Message $errorMessage -ErrorAction $ErrorActionPreference
                return
            }
        }
    } while (-not $RequestSuccessful -and $RetryCount -le $MaxRetries)

    # Should never reach here, but just in case
    if (-not $RequestSuccessful) {
        $errorMessage = "Azure REST API call failed after $MaxRetries attempts: $Message`nURI: $Uri"
        Write-Error -Message $errorMessage -ErrorAction $ErrorActionPreference
        return
    }
}
