function Invoke-ExecUploadAppPackage {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    .SYNOPSIS
        Uploads one block of an app package or installer to CIPP storage, and packages uploaded installers.
    .DESCRIPTION
        The browser sends the encrypted payload in blocks of at most 8 MB. When the host passes raw request
        bodies through ($Request.RawBody), a block is an application/octet-stream body with packageId and
        index in the query string; otherwise it is JSON with the block base64-encoded in 'data'. A request with
        'capabilities' reports which of the two this host supports. Saving the application template assembles
        the blocks; blocks that are never saved expire from storage on their own.
        An .exe or .msi is uploaded the same way with 'installer' set, then 'package' (the setup file name and
        block count) queues a background job that builds the encrypted payload, and 'status' returns its result:
        the block count and metadata to save the template with, or the error.
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

    try {
        $Storage = Get-CIPPAppPackageStorage -PackageId "$PackageId"
    } catch {
        return ([HttpResponseContext]@{ StatusCode = Get-CippErrorStatusCode -ErrorRecord $_; Body = @{ Results = "Failed to open app package storage: $($_.Exception.Message)" } })
    }

    if ($Request.Body.status) {
        $Packaged = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource "app-packages/$PackageId/packaged.json" -ErrorAction SilentlyContinue
        $Result = if ($Packaged.Bytes) { [Text.Encoding]::UTF8.GetString($Packaged.Bytes) | ConvertFrom-Json } else { @{ packaging = $true } }
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = $Result } })
    }

    # The uploaded installer's file name, which becomes the package's setup file
    $SetupFile = [string]$Request.Body.package.setupFile
    if ($SetupFile) {
        $BlockCount = [int]$Request.Body.package.blockCount
        if ($SetupFile -notmatch '^[^\\/:*?"<>|]+\.(exe|msi)$' -or $BlockCount -lt 1 -or $BlockCount -gt 512) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Upload an .exe or .msi installer smaller than 4 GB' } })
        }
        try {
            $BlockIds = foreach ($i in 0..($BlockCount - 1)) { '<Latest>{0}</Latest>' -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($i.ToString('000'))) }
            $null = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource "app-packages/$PackageId/installer" -Method PUT -QueryParams @{ comp = 'blocklist' } -ContentType 'application/xml' -Body ('<?xml version="1.0" encoding="utf-8"?><BlockList>' + ($BlockIds -join '') + '</BlockList>') -ErrorAction Stop
            if (-not (Add-CippQueueMessage -Cmdlet 'New-CIPPIntuneWinPackage' -Parameters @{ PackageId = "$PackageId"; SetupFile = $SetupFile })) { throw 'Could not queue the packaging job' }
            $Result = "Packaging $SetupFile"
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $Result = "Failed to package the installer: $($_.Exception.Message)"
            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Result -Sev Error
            $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        }
        return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
    }
    # Zero-based block number; packages are capped below 4 GiB, 512 blocks of 8 MB
    $Index = [int]($Request.Query.index ?? $Request.Body.index)
    # Base64 of the block, when it is not sent as a raw body
    if ($Request.RawBody -is [byte[]]) { $Bytes = $Request.RawBody } else { $Bytes = [Convert]::FromBase64String([string]$Request.Body.data) }
    if ($Index -lt 0 -or $Index -ge 512 -or $Bytes.Length -eq 0 -or $Bytes.Length -gt 8MB) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Each block must be 1 byte to 8 MB with an index below 512 (packages must be smaller than 4 GB)' } })
    }

    try {
        # The first block decides where a new package is stored; later requests find it by package id
        if ($Index -eq 0) {
            $Storage = Get-CIPPAppPackageStorage
            # ponytail: checked when an upload starts, so the upload that fills storage can go over the limit by one package
            if ($Storage.LimitBytes) {
                $Used = (@(Get-CIPPAppPackageFile -ErrorAction SilentlyContinue).Size | Measure-Object -Sum).Sum
                if ($Used -ge $Storage.LimitBytes) {
                    throw [System.ArgumentException]::new(('App package storage is full: {0:N1} GB of the {1:N0} GB included with this instance is in use. Delete application templates you no longer need, or connect your own storage account under Settings > App Package Storage.' -f ($Used / 1GB), ($Storage.LimitBytes / 1GB)))
                }
            }
            if ($Storage.Custom) {
                $PackagesTable = Get-CIPPTable -TableName 'AppPackages'
                Add-CIPPAzDataTableEntity @PackagesTable -Entity @{ PartitionKey = 'AppPackage'; RowKey = "$PackageId"; AccountName = $Storage.AccountName } -Force
            }
        }
        if ($Index -eq 0 -and -not (New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Component list -ErrorAction Stop | Where-Object Name -EQ 'app-packages')) {
            $null = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource 'app-packages' -Method PUT -QueryParams @{ restype = 'container' } -ErrorAction Stop
        }
        $BlockId = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($Index.ToString('000')))
        # True when the block belongs to an .exe or .msi installer that CIPP packages
        $Blob = if ([bool]($Request.Query.installer ?? $Request.Body.installer)) { 'installer' } else { 'IntunePackage.intunewin' }
        $null = New-CIPPAzStorageRequest -Service blob -ConnectionString $Storage.ConnectionString -Resource "app-packages/$PackageId/$Blob" -Method PUT -QueryParams @{ comp = 'block'; blockid = $BlockId } -Body $Bytes -ContentType 'application/octet-stream' -ErrorAction Stop
        $Result = @{ index = $Index; size = $Bytes.Length }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to store the app package: $($_.Exception.Message)"
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Result -Sev Error
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}
