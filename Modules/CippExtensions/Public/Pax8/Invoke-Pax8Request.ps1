function Invoke-Pax8Request {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        $Body,
        [hashtable]$Query,
        [switch]$NoContent
    )

    $BaseUri = 'https://api.pax8.com/v1'
    $UriBuilder = [System.UriBuilder]::new("$BaseUri/$($Path.TrimStart('/'))")
    if ($Query) {
        $QueryParts = foreach ($Item in $Query.GetEnumerator()) {
            if ($null -ne $Item.Value -and $Item.Value -ne '') {
                '{0}={1}' -f [System.Uri]::EscapeDataString([string]$Item.Key), [System.Uri]::EscapeDataString([string]$Item.Value)
            }
        }
        $UriBuilder.Query = $QueryParts -join '&'
    }

    $Params = @{
        Uri         = $UriBuilder.Uri.AbsoluteUri
        Method      = $Method
        Headers     = Get-Pax8Authentication
        ContentType = 'application/json'
    }

    if ($null -ne $Body) {
        $Params.Body = $Body | ConvertTo-Json -Depth 20
    }

    try {
        if ($NoContent) {
            Invoke-RestMethod @Params | Out-Null
            return $true
        }
        return Invoke-RestMethod @Params
    } catch {
        $Message = if ($_.ErrorDetails.Message) {
            Get-NormalizedError -Message $_.ErrorDetails.Message
        } else {
            $_.Exception.Message
        }
        throw "Pax8 API request failed for $Method $Path. $Message"
    }
}
