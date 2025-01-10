function Get-HIBPRequest {
    [CmdletBinding()]
    param(
        [Parameter()]
        $endpoint
    )
    $uri = "https://haveibeenpwned.com/api/v3/$endpoint"
    try {
        return Invoke-RestMethod -Uri $uri -Headers (Get-HIBPAuth)
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 404) {
            return @()
        } elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 429) {
            Write-Host 'Rate limited hit for hibp.'
            return @{
                Wait         = ($_.Exception.Response.headers | Where-Object -Property key -EQ 'Retry-After').value
                'rate-limit' = $true
            }
        } else {
            throw "Failed to connect to HIBP: $($_.Exception.Message)"
        }
    }
    throw "Failed to connect to HIBP after $maxRetries retries."
}
