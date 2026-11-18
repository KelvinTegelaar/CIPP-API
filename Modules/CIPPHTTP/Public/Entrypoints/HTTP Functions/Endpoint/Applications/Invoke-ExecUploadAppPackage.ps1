function Invoke-ExecUploadAppPackage {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    .SYNOPSIS
        Uploads one block of an app package's encrypted payload to CIPP storage.
    .DESCRIPTION
        The browser sends the encrypted payload in blocks of at most 8 MB. When the host passes raw request
        bodies through ($Request.RawBody), a block is an application/octet-stream body with packageId and
        index in the query string; otherwise it is JSON with the block base64-encoded in 'data'. A request with
        'capabilities' reports which of the two this host supports. Saving the application template assembles
        the blocks; blocks that are never saved expire from storage on their own.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # A Craft that passes raw bodies always sets RawBody: null for this JSON request, byte[] for a binary one.
    # Azure Functions also has RawBody, but as the body text, so it never reads as supported.
    $BinaryBlocks = $null -ne $Request.PSObject.Properties['RawBody'] -and ($null -eq $Request.RawBody -or $Request.RawBody -is [byte[]])
    if ($Request.Query.capabilities -or $Request.Body.capabilities) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = @{ binaryBlocks = $BinaryBlocks } } })
    }

    $PackageId = [guid]::Empty
    if (-not [guid]::TryParse([string]($Request.Query.packageId ?? $Request.Body.packageId), [ref]$PackageId)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'packageId must be a GUID' } })
    }
    # Zero-based block number; packages are capped below 4 GiB, 512 blocks of 8 MB
    $Index = [int]($Request.Query.index ?? $Request.Body.index)
    # Base64 of the block, when it is not sent as a raw body
    if ($Request.RawBody -is [byte[]]) { $Bytes = $Request.RawBody } else { $Bytes = [Convert]::FromBase64String([string]$Request.Body.data) }
    if ($Index -lt 0 -or $Index -ge 512 -or $Bytes.Length -eq 0 -or $Bytes.Length -gt 8MB) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Each block must be 1 byte to 8 MB with an index below 512 (packages must be smaller than 4 GB)' } })
    }

    try {
        if ($Index -eq 0 -and -not (New-CIPPAzStorageRequest -Service blob -Component list -ErrorAction Stop | Where-Object Name -EQ 'app-packages')) {
            $null = New-CIPPAzStorageRequest -Service blob -Resource 'app-packages' -Method PUT -QueryParams @{ restype = 'container' } -ErrorAction Stop
        }
        $BlockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($Index.ToString('000')))
        $null = New-CIPPAzStorageRequest -Service blob -Resource "app-packages/$PackageId/IntunePackage.intunewin" -Method PUT -QueryParams @{ comp = 'block'; blockid = $BlockId } -Body $Bytes -ContentType 'application/octet-stream' -ErrorAction Stop
        $Result = @{ index = $Index; size = $Bytes.Length }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to store the app package: $($_.Exception.Message)"
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Result -Sev Error
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}
