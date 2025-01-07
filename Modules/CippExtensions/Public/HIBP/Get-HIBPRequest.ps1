function Get-HIBPRequest {
    [CmdletBinding()]
    param (
        [Parameter()]$endpoint

    )
    $uri = "https://haveibeenpwned.com/api/v3/$endpoint"
    try {
        Invoke-RestMethod -Uri $uri -Headers (Get-HIBPAuth)
    } catch {
        #If the error is a 404, it means no breach has been found. Return an empty object.
        if ($_.Exception.Response.StatusCode -eq 404) {
            return @()
        }
        throw "Failed to connect to HIBP: $($_.Exception.Message)"
    }
}
