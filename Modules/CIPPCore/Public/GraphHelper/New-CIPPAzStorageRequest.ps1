function New-CIPPAzStorageRequest {
    <#
    .SYNOPSIS
        Create and send a REST request to Azure Storage APIs using Shared Key authorization
    .DESCRIPTION
        Wraps Invoke-RestMethod with automatic Azure Storage Shared Key authentication.
        Parses AzureWebJobsStorage connection string and generates authorization headers.
        Supports Blob, Queue, and Table storage services.
    .PARAMETER Service
        The Azure Storage service (blob, queue, table, file)
    .PARAMETER Resource
        The resource path (e.g., 'tables', 'myqueue/messages')
    .PARAMETER QueryParams
        Optional hashtable of query string parameters
    .PARAMETER Method
        The HTTP method (GET, POST, PUT, PATCH, DELETE, HEAD, etc.). Defaults to GET.
    .PARAMETER Body
        The request body (can be string, hashtable, or PSCustomObject)
    .PARAMETER Headers
        Additional headers to include in the request. Authorization header is automatically added.
    .PARAMETER ContentType
        The content type of the request body
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage
    .PARAMETER MaxRetries
        Maximum number of retry attempts for transient failures. Defaults to 3.
    .EXAMPLE
        New-CIPPStorageRequest -Service 'table' -Resource 'tables'
        Lists all tables in storage account (returns PSObjects)
    .EXAMPLE
        New-CIPPStorageRequest -Service 'queue' -Resource 'myqueue/messages' -Method DELETE
        Clears messages from a queue
    .EXAMPLE
        New-CIPPStorageRequest -Service 'queue' -Component 'list'
        Lists queues (returns PSObjects with Name and optional Metadata)
    .EXAMPLE
        New-CIPPStorageRequest -Service 'blob' -Component 'list'
        Lists blob containers (returns PSObjects with Name and Properties)
    .LINK
        https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('blob', 'queue', 'table', 'file')]
        [string]$Service,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Resource,

        [Parameter(Mandatory = $false, Position = 2)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [hashtable]$QueryParams,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [hashtable]$Headers = @{},

        [Parameter(Mandatory = $false)]
        [string]$ContentType,

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    # Helper: robustly convert XML string to XmlDocument (handles BOM/whitespace)
    function Convert-XmlStringToDocument {
        param(
            [Parameter(Mandatory = $true)][string]$XmlText
        )
        # Normalize: trim leading BOM and whitespace
        $normalized = $XmlText
        # Remove UTF-8 BOM if present
        if ($normalized.Length -gt 0 -and [int][char]$normalized[0] -eq 65279) {
            $normalized = $normalized.Substring(1)
        }
        $normalized = $normalized.Trim()

        $settings = [System.Xml.XmlReaderSettings]::new()
        $settings.IgnoreWhitespace = $true
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $sr = [System.IO.StringReader]::new($normalized)
        try {
            $xr = [System.Xml.XmlReader]::Create($sr, $settings)
            $doc = [System.Xml.XmlDocument]::new()
            $doc.Load($xr)
            $xr.Dispose()
            $sr.Dispose()
            return $doc
        } catch {
            try { if ($xr) { $xr.Dispose() } } catch {}
            try { if ($sr) { $sr.Dispose() } } catch {}
            throw $_
        }
    }

    # Helper: compute Shared Key HMAC-SHA256 signature (Base64 over UTF-8 string)
    function New-SharedKeySignature {
        param(
            [Parameter(Mandatory = $true)][string]$AccountKey,
            [Parameter(Mandatory = $true)][string]$StringToSign
        )
        try {
            $KeyBytes = [Convert]::FromBase64String($AccountKey)
            $Hmac = [System.Security.Cryptography.HMACSHA256]::new($KeyBytes)
            $StringBytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
            $SignatureBytes = $Hmac.ComputeHash($StringBytes)
            $Hmac.Dispose()
            return [Convert]::ToBase64String($SignatureBytes)
        } catch {
            throw $_
        }
    }

    # Helper: canonicalize x-ms-* headers (lowercase names, sort ascending, collapse whitespace)
    function Get-CanonicalizedXmsHeaders {
        param(
            [Parameter(Mandatory = $true)][hashtable]$Headers
        )
        $CanonicalizedHeadersList = [System.Collections.Generic.List[string]]::new()
        $XmsHeaders = $Headers.Keys | Where-Object { $_ -like 'x-ms-*' } | Sort-Object
        foreach ($Header in $XmsHeaders) {
            $HeaderName = $Header.ToLowerInvariant()
            $HeaderValue = $Headers[$Header] -replace '\s+', ' '
            $CanonicalizedHeadersList.Add("${HeaderName}:${HeaderValue}")
        }
        return ($CanonicalizedHeadersList -join "`n")
    }

    # Helper: canonicalize resource for Shared Key
    function Get-CanonicalizedResourceSharedKey {
        param(
            [Parameter(Mandatory = $true)][string]$AccountName,
            [Parameter(Mandatory = $true)][uri]$Uri,
            [switch]$TableFormat
        )
        $CanonicalizedResource = "/$AccountName" + $Uri.AbsolutePath
        if ($TableFormat) {
            if ($Uri.Query) {
                try {
                    $parsed = [System.Web.HttpUtility]::ParseQueryString($Uri.Query)
                    $compVal = $parsed['comp']
                    if ($compVal) { $CanonicalizedResource += "?comp=$compVal" }
                } catch { }
            }
            return $CanonicalizedResource
        }
        if ($Uri.Query) {
            $ParsedQueryParams = [System.Web.HttpUtility]::ParseQueryString($Uri.Query)
            $CanonicalizedParams = [System.Collections.Generic.List[string]]::new()
            foreach ($Key in ($ParsedQueryParams.AllKeys | Sort-Object)) {
                $Value = $ParsedQueryParams[$Key]
                $CanonicalizedParams.Add("$($Key.ToLowerInvariant()):$Value")
            }
            if ($CanonicalizedParams.Count -gt 0) {
                $CanonicalizedResource += "`n" + ($CanonicalizedParams -join "`n")
            }
        }
        return $CanonicalizedResource
    }

    # Helper: build StringToSign for Blob/Queue/File
    function Get-StringToSignBlobQueueFile {
        param(
            [Parameter(Mandatory = $true)][string]$Method,
            [Parameter()][string]$ContentType,
            [Parameter(Mandatory = $true)][hashtable]$Headers,
            [Parameter()][string]$CanonicalizedHeaders,
            [Parameter(Mandatory = $true)][string]$CanonicalizedResource
        )
        $ContentLengthString = ''
        if ($Headers.ContainsKey('Content-Length')) {
            $cl = [string]$Headers['Content-Length']
            if ($cl -ne '0') { $ContentLengthString = $cl }
        }
        $parts = @(
            $Method.ToUpperInvariant()
            if ($Headers['Content-Encoding']) { $Headers['Content-Encoding'] } else { '' }
            if ($Headers['Content-Language']) { $Headers['Content-Language'] } else { '' }
            $ContentLengthString
            ''
            if ($ContentType) { $ContentType } else { '' }
            ''
            if ($Headers['If-Modified-Since']) { $Headers['If-Modified-Since'] } else { '' }
            if ($Headers['If-Match']) { $Headers['If-Match'] } else { '' }
            if ($Headers['If-None-Match']) { $Headers['If-None-Match'] } else { '' }
            if ($Headers['If-Unmodified-Since']) { $Headers['If-Unmodified-Since'] } else { '' }
            if ($Headers['Range']) { $Headers['Range'] } else { '' }
        )
        $str = ($parts -join "`n")
        if ($CanonicalizedHeaders) { $str += "`n" + $CanonicalizedHeaders }
        $str += "`n" + $CanonicalizedResource
        return $str
    }

    # Helper: build StringToSign for Table
    function Get-StringToSignTable {
        param(
            [Parameter(Mandatory = $true)][string]$Method,
            [Parameter()][string]$ContentType,
            [Parameter(Mandatory = $true)][string]$Date,
            [Parameter(Mandatory = $true)][string]$CanonicalizedResource
        )
        $contentTypeForSign = if ($ContentType) { $ContentType } else { '' }
        return ($Method.ToUpperInvariant() + "`n" + '' + "`n" + $contentTypeForSign + "`n" + $Date + "`n" + $CanonicalizedResource)
    }

    # Parse connection string
    try {
        # Initialize variables
        $ProvidedEndpoint = $null
        $ProvidedPath = $null
        $EmulatorHost = $null
        $EndpointSuffix = $null
        $Protocol = $null

        Write-Verbose 'Parsing connection string'
        $ConnectionParams = @{}
        $ConnectionString -split ';' | ForEach-Object {
            $Part = $_.Trim()
            if ($Part -and $Part -match '^(.+?)=(.+)$') {
                $ConnectionParams[$matches[1]] = $matches[2]
            }
        }

        Write-Verbose "Connection string parsed. Keys: $($ConnectionParams.Keys -join ', ')"

        # For development storage, use default account name if not provided
        if ($ConnectionParams['UseDevelopmentStorage'] -eq 'true') {
            $AccountName = $ConnectionParams['AccountName'] ?? 'devstoreaccount1'
            $AccountKey = $ConnectionParams['AccountKey'] ?? 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
            Write-Verbose 'Using development storage defaults'
        } else {
            $AccountName = $ConnectionParams['AccountName']
            $AccountKey = $ConnectionParams['AccountKey']
        }

        $AccountKeyMasked = if ($AccountKey) { '***' } else { 'NOT FOUND' }

        Write-Verbose "AccountName: $AccountName, AccountKey: $AccountKeyMasked"

        if (-not $AccountName) {
            throw 'Connection string must contain AccountName'
        }

        # For localhost (emulator), use default key if not provided
        if (-not $AccountKey) {
            if ($ConnectionParams[$EndpointKey] -and $ConnectionParams[$EndpointKey] -match '127\.0\.0\.1') {
                $AccountKey = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
                Write-Verbose 'Using default emulator key for 127.0.0.1'
            } else {
                throw 'Connection string must contain AccountKey for non-emulator storage'
            }
        }

        # Check for service-specific endpoint (e.g., BlobEndpoint, QueueEndpoint, TableEndpoint)
        $ServiceCapitalized = [char]::ToUpper($Service[0]) + $Service.Substring(1)
        $EndpointKey = "${ServiceCapitalized}Endpoint"
        $ProvidedEndpoint = $ConnectionParams[$EndpointKey]

        Write-Verbose "Looking for endpoint key: $EndpointKey"

        if ($ProvidedEndpoint) {
            Write-Verbose "Found provided endpoint: $ProvidedEndpoint"
            # Parse provided endpoint
            $EndpointUri = [System.Uri]::new($ProvidedEndpoint)
            $Protocol = $EndpointUri.Scheme
            $EmulatorHost = "$($EndpointUri.Host)"
            if ($EndpointUri.Port -ne -1) {
                $EmulatorHost += ":$($EndpointUri.Port)"
            }
            # Path will be used for canonicalized resource
            $ProvidedPath = $EndpointUri.AbsolutePath.TrimEnd('/')
            Write-Verbose "Parsed endpoint - Protocol: $Protocol, Host: $EmulatorHost, Path: $ProvidedPath"
        }
        # Check for development storage emulator
        elseif ($ConnectionParams['UseDevelopmentStorage'] -eq 'true') {
            Write-Verbose 'Using development storage emulator'
            $Protocol = 'http'
            # Map service to emulator port
            $ServicePorts = @{
                'blob'  = 10000
                'queue' = 10001
                'table' = 10002
            }
            $EmulatorHost = "127.0.0.1:$($ServicePorts[$Service])"
            Write-Verbose "Emulator host: $EmulatorHost"
        } else {
            Write-Verbose 'Using standard Azure Storage'
            # Extract endpoint suffix and protocol
            $EndpointSuffix = $ConnectionParams['EndpointSuffix']
            if (-not $EndpointSuffix) {
                $EndpointSuffix = 'core.windows.net'
            }

            $Protocol = $ConnectionParams['DefaultEndpointsProtocol']
            if (-not $Protocol) {
                $Protocol = 'https'
            }
            Write-Verbose "Protocol: $Protocol, EndpointSuffix: $EndpointSuffix"
        }
    } catch {
        Write-Error "Failed to parse connection string: $($_.Exception.Message)"
        return
    }

    # Build URI using UriBuilder
    Write-Verbose "Building URI - Service: $Service, Resource: $Resource"

    # Treat Resource strictly as a path; only Component/QueryParams build queries
    $ResourcePath = $Resource
    $InlineQueryString = $null
    if ($Component) {
        $InlineQueryString = "comp=$Component"
        Write-Verbose "Using component -> comp=$Component"
    }

    $UriBuilder = [System.UriBuilder]::new()
    $UriBuilder.Scheme = $Protocol

    if ($ProvidedEndpoint) {
        # Use provided endpoint host - split host and port if present
        if ($EmulatorHost -match '^(.+?):(\d+)$') {
            $UriBuilder.Host = $matches[1]
            $UriBuilder.Port = [int]$matches[2]
            Write-Verbose "Set host with port - Host: $($matches[1]), Port: $($matches[2])"
        } else {
            $UriBuilder.Host = $EmulatorHost
        }
        # Build path from provided endpoint base + resource
        $FullResourcePath = "$ProvidedPath/$ResourcePath".Replace('//', '/')
        $UriBuilder.Path = $FullResourcePath
        Write-Verbose "Using provided endpoint - Host: $EmulatorHost, Path: $FullResourcePath"
    } elseif ($EmulatorHost) {
        # Emulator without provided endpoint - split host and port if present
        if ($EmulatorHost -match '^(.+?):(\d+)$') {
            $UriBuilder.Host = $matches[1]
            $UriBuilder.Port = [int]$matches[2]
            Write-Verbose "Set host with port - Host: $($matches[1]), Port: $($matches[2])"
        } else {
            $UriBuilder.Host = $EmulatorHost
        }
        $UriBuilder.Path = "$AccountName/$ResourcePath"
        Write-Verbose "Using emulator - Host: $EmulatorHost, Path: $AccountName/$ResourcePath"
    } else {
        # Standard Azure Storage
        $UriBuilder.Host = "$AccountName.$Service.$EndpointSuffix"
        $UriBuilder.Path = $ResourcePath
        Write-Verbose "Using standard Azure Storage - Host: $AccountName.$Service.$EndpointSuffix, Path: $ResourcePath"
    }

    # Build query string from both explicit QueryParams and inline query string
    $QueryString = [System.Web.HttpUtility]::ParseQueryString('')

    # Add inline query string if present (from Component only)
    if ($InlineQueryString) {
        Write-Verbose "Adding inline query string: $InlineQueryString"
        foreach ($Param in $InlineQueryString -split '&') {
            $Key, $Value = $Param -split '=', 2
            $QueryString.Add([System.Web.HttpUtility]::UrlDecode($Key), [System.Web.HttpUtility]::UrlDecode($Value))
        }
    }

    # Add explicit QueryParams
    if ($QueryParams) {
        Write-Verbose "Adding query parameters: $($QueryParams.Keys -join ', ')"
        foreach ($Key in $QueryParams.Keys) {
            $QueryString.Add($Key, $QueryParams[$Key])
        }
    }

    # Ensure comp from Component is set even if QueryParams provided (QueryParams can override)
    if ($Component -and -not $QueryString['comp']) {
        $QueryString.Add('comp', $Component)
    }

    if ($QueryString.Count -gt 0) {
        $UriBuilder.Query = $QueryString.ToString()
        Write-Verbose "Final query string: $($UriBuilder.Query)"
    }

    $Uri = $UriBuilder.Uri
    Write-Verbose "Final URI: $Uri"

    # Initialize request headers
    $RequestHeaders = @{}
    $currentDateRfc = [DateTime]::UtcNow.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
    # Default a recent stable service version if none supplied by caller (Blob/Queue/File)
    $RequestHeaders['x-ms-version'] = '2023-11-03'

    # Add Table service specific headers
    if ($Service -eq 'table') {
        # Table service: align with Az (SharedKey). Table uses Date (never empty) and may also set x-ms-date to same value
        $RequestHeaders['x-ms-date'] = $currentDateRfc
        $RequestHeaders['Date'] = $currentDateRfc
        $RequestHeaders['x-ms-version'] = '2017-07-29'
        $RequestHeaders['Accept'] = 'application/json; odata=minimalmetadata'
        $RequestHeaders['DataServiceVersion'] = '3.0;'
        $RequestHeaders['MaxDataServiceVersion'] = '3.0;NetFx'
        $RequestHeaders['Accept-Charset'] = 'utf-8'
    } else {
        # Blob/Queue/File use x-ms-date
        $RequestHeaders['x-ms-date'] = $currentDateRfc
    }

    # Build canonical headers and resource
    $UtcNow = $currentDateRfc

    # Determine storage service headers already set; no unused version variable

    # Build canonicalized resource - format differs by service
    if ($Service -eq 'table') {
        # Table Service canonicalized resource
        $CanonicalizedResource = Get-CanonicalizedResourceSharedKey -AccountName $AccountName -Uri $Uri -TableFormat
        Write-Verbose "Table Service canonicalized resource: $CanonicalizedResource"
        # Build string to sign for Table Service (SharedKey)
        # Per docs, Table SharedKey DOES NOT include CanonicalizedHeaders. Date is never empty.
        $StringToSign = Get-StringToSignTable -Method $Method -ContentType $ContentType -Date $RequestHeaders['Date'] -CanonicalizedResource $CanonicalizedResource
        Write-Verbose 'Using SharedKey format (Table Service)'

        Write-Verbose "String to sign (escaped): $($StringToSign -replace "`n", '\n')"
        Write-Verbose "String to sign length: $($StringToSign.Length)"

        # Generate signature
        try { $Signature = New-SharedKeySignature -AccountKey $AccountKey -StringToSign $StringToSign; Write-Verbose "Generated signature: $Signature" }
        catch { Write-Error "Failed to generate signature: $($_.Exception.Message)"; return }

        # Add authorization header
        $RequestHeaders['Authorization'] = "SharedKey ${AccountName}:${Signature}"
        Write-Verbose "Authorization header: SharedKey ${AccountName}:$($Signature.Substring(0, [Math]::Min(10, $Signature.Length)))..."

        # Headers for Table response already set (Accept minimalmetadata etc.)

        # Merge user-provided headers
        foreach ($Key in $Headers.Keys) {
            $RequestHeaders[$Key] = $Headers[$Key]
        }

        # Build Invoke-RestMethod parameters for Table Service
        $RestMethodParams = @{
            Uri         = $Uri
            Method      = $Method
            Headers     = $RequestHeaders
            ErrorAction = 'Stop'
        }

        if ($Body) {
            if ($Body -is [string]) {
                $RestMethodParams['Body'] = $Body
            } elseif ($Body -is [byte[]]) {
                $RestMethodParams['Body'] = $Body
            } else {
                $RestMethodParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
            }
        }

        if ($ContentType) {
            $RestMethodParams['ContentType'] = $ContentType
        }
    } else {
        # Blob/Queue/File canonicalized resource
        $CanonicalizedResource = Get-CanonicalizedResourceSharedKey -AccountName $AccountName -Uri $Uri
        Write-Verbose "Blob/Queue/File canonicalized resource: $($CanonicalizedResource -replace "`n", ' | ')"

        # Do not force JSON Accept on blob/queue; service returns XML for list ops
        if (-not $RequestHeaders.ContainsKey('Accept')) {
            if ($Service -eq 'blob') {
                $isList = (($Component -eq 'list') -or ($Uri.Query -match 'comp=list'))
                if ($isList) { $RequestHeaders['Accept'] = 'application/xml' }
            } elseif ($Service -eq 'queue') {
                $RequestHeaders['Accept'] = 'application/xml'
            }
            # For Azure Files, avoid forcing Accept; binary downloads should be raw bytes
        }

        # Merge user-provided headers (these override defaults)
        foreach ($Key in $Headers.Keys) {
            $RequestHeaders[$Key] = $Headers[$Key]
        }

        # Add Content-Length for PUT/POST/PATCH
        $ContentLength = 0
        if ($Body) {
            if ($Body -is [string]) {
                $ContentLength = [System.Text.Encoding]::UTF8.GetByteCount($Body)
            } elseif ($Body -is [byte[]]) {
                $ContentLength = $Body.Length
            } else {
                $BodyJson = $Body | ConvertTo-Json -Depth 10 -Compress
                $ContentLength = [System.Text.Encoding]::UTF8.GetByteCount($BodyJson)
            }
        }

        if ($Method -in @('PUT', 'POST', 'PATCH')) {
            $RequestHeaders['Content-Length'] = $ContentLength.ToString()
        }

        # Blob upload: default to BlockBlob when performing a simple Put Blob (no comp parameter)
        if ($Service -eq 'blob') {
            $isCompSpecified = ($Component) -or ($Uri.Query -match 'comp=')
            if ($Method -eq 'PUT' -and -not $isCompSpecified) {
                if (-not $RequestHeaders.ContainsKey('x-ms-blob-type')) { $RequestHeaders['x-ms-blob-type'] = 'BlockBlob' }
            }
        }

        # Azure Files specific conveniences and validations
        if ($Service -eq 'file') {
            # Create file: PUT to file path without comp=range should specify x-ms-type and x-ms-content-length; body typically empty
            $isRangeOp = ($Component -eq 'range') -or ($Uri.Query -match 'comp=range')
            if ($Method -eq 'PUT' -and -not $isRangeOp) {
                if (-not $RequestHeaders.ContainsKey('x-ms-type')) { $RequestHeaders['x-ms-type'] = 'file' }
                # x-ms-content-length is required for create; if not provided by caller, try to infer from header Content-Length when body is empty
                if (-not $RequestHeaders.ContainsKey('x-ms-content-length')) {
                    if ($ContentLength -eq 0) {
                        # Caller must supply x-ms-content-length for file size; fail fast for correctness
                        Write-Error 'Azure Files create operation requires header x-ms-content-length specifying file size in bytes.'
                        return
                    } else {
                        # If body present, assume immediate range upload is intended; advise using comp=range
                        Write-Verbose 'Body detected on Azure Files PUT without comp=range; consider using comp=range for content upload.'
                    }
                }
            } elseif ($Method -eq 'PUT' -and $isRangeOp) {
                # Range upload must include x-ms-write and x-ms-range
                if (-not $RequestHeaders.ContainsKey('x-ms-write')) { $RequestHeaders['x-ms-write'] = 'update' }
                if (-not $RequestHeaders.ContainsKey('x-ms-range')) {
                    Write-Error 'Azure Files range upload requires header x-ms-range (e.g., bytes=0-<end>).'
                    return
                }
            }
        }

        # Build canonicalized headers (x-ms-*)
        $CanonicalizedHeaders = Get-CanonicalizedXmsHeaders -Headers $RequestHeaders

        Write-Verbose "CanonicalizedHeaders: $($CanonicalizedHeaders -replace "`n", '\n')"

        # Build string to sign for Blob/Queue/File
        $StringToSign = Get-StringToSignBlobQueueFile -Method $Method -ContentType $ContentType -Headers $RequestHeaders -CanonicalizedHeaders $CanonicalizedHeaders -CanonicalizedResource $CanonicalizedResource
        Write-Verbose 'Using SharedKey format (Blob/Queue/File)'

        Write-Verbose "String to sign (escaped): $($StringToSign -replace "`n", '\n')"
        Write-Verbose "String to sign length: $($StringToSign.Length)"

        # Generate signature
        try { $Signature = New-SharedKeySignature -AccountKey $AccountKey -StringToSign $StringToSign; Write-Verbose "Generated signature: $Signature" }
        catch { Write-Error "Failed to generate signature: $($_.Exception.Message)"; return }

        # Add authorization header
        $RequestHeaders['Authorization'] = "SharedKey ${AccountName}:${Signature}"
        Write-Verbose "Authorization header: SharedKey ${AccountName}:$($Signature.Substring(0, [Math]::Min(10, $Signature.Length)))..."

        # Build Invoke-RestMethod parameters
        $RestMethodParams = @{
            Uri         = $Uri
            Method      = $Method
            Headers     = $RequestHeaders
            ErrorAction = 'Stop'
        }

        if ($Body) {
            if ($Body -is [string]) {
                $RestMethodParams['Body'] = $Body
            } elseif ($Body -is [byte[]]) {
                $RestMethodParams['Body'] = $Body
            } else {
                $RestMethodParams['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
            }
        }

        if ($ContentType) {
            $RestMethodParams['ContentType'] = $ContentType
        }
    }

    # Invoke with retry logic
    $RetryCount = 0
    $RequestSuccessful = $false

    Write-Information "$($Method.ToUpper()) [ $Uri ] | attempt: $($RetryCount + 1) of $MaxRetries"

    $TriedAltTableAuth = $false
    $UseInvokeWebRequest = $false
    if ($Service -eq 'queue' -and (($Component -eq 'metadata') -or ($Uri.Query -match 'comp=metadata'))) {
        # Use Invoke-WebRequest to access response headers for queue metadata
        $UseInvokeWebRequest = $true
    } elseif ($Method -eq 'DELETE') {
        # For other DELETE operations across services, prefer capturing headers/status
        $UseInvokeWebRequest = $true
    } elseif ($Service -eq 'file' -and $Method -eq 'GET' -and -not (($Component -eq 'list') -or ($Uri.Query -match 'comp=list') -or ($Uri.Query -match 'comp=properties') -or ($Uri.Query -match 'comp=metadata'))) {
        # For Azure Files binary downloads, use Invoke-WebRequest and return bytes
        $UseInvokeWebRequest = $true
    } elseif ($Service -eq 'blob' -and $Method -eq 'GET' -and -not (($Component -eq 'list') -or ($Uri.Query -match 'comp=list') -or ($Uri.Query -match 'comp=metadata') -or ($Uri.Query -match 'comp=properties'))) {
        # For Blob binary downloads, use Invoke-WebRequest and return bytes (memory stream, no filesystem)
        $UseInvokeWebRequest = $true
    }
    do {
        try {
            # Blob: binary GET returns bytes from RawContentStream
            if ($UseInvokeWebRequest -and $Service -eq 'blob' -and $Method -eq 'GET' -and -not (($Component -eq 'list') -or ($Uri.Query -match 'comp=list') -or ($Uri.Query -match 'comp=metadata') -or ($Uri.Query -match 'comp=properties'))) {
                Write-Verbose 'Processing Blob binary download'
                $resp = Invoke-WebRequest @RestMethodParams
                $RequestSuccessful = $true
                $ms = [System.IO.MemoryStream]::new()
                try { $resp.RawContentStream.CopyTo($ms) } catch { }
                $bytes = $ms.ToArray()
                $hdrHash = @{}
                if ($resp -and $resp.Headers) { foreach ($key in $resp.Headers.Keys) { $hdrHash[$key] = $resp.Headers[$key] } }
                $reqUri = $null
                try { if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) { $reqUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } } catch { $reqUri = $Uri.AbsoluteUri }
                return [PSCustomObject]@{ Bytes = $bytes; Length = $bytes.Length; Headers = $hdrHash; Uri = $reqUri }
            }
            # Azure Files: binary GET returns bytes
            if ($UseInvokeWebRequest -and $Service -eq 'file' -and $Method -eq 'GET' -and -not (($Component -eq 'list') -or ($Uri.Query -match 'comp=list') -or ($Uri.Query -match 'comp=properties') -or ($Uri.Query -match 'comp=metadata'))) {
                Write-Verbose 'Processing Azure Files binary download'
                $tmp = [System.IO.Path]::GetTempFileName()
                try {
                    $resp = Invoke-WebRequest @RestMethodParams -OutFile $tmp
                    $RequestSuccessful = $true
                    $bytes = [System.IO.File]::ReadAllBytes($tmp)
                    $hdrHash = @{}
                    if ($resp -and $resp.Headers) { foreach ($key in $resp.Headers.Keys) { $hdrHash[$key] = $resp.Headers[$key] } }
                    $reqUri = $null
                    try { if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) { $reqUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } } catch { $reqUri = $Uri.AbsoluteUri }
                    return [PSCustomObject]@{ Bytes = $bytes; Length = $bytes.Length; Headers = $hdrHash; Uri = $reqUri }
                } finally {
                    try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch {}
                }
            }
            # For queue comp=metadata, capture headers-only and return a compact object
            if ($UseInvokeWebRequest -and $Service -eq 'queue' -and (($Component -eq 'metadata') -or ($Uri.Query -match 'comp=metadata'))) {
                Write-Verbose 'Processing queue metadata response headers'
                $resp = Invoke-WebRequest @RestMethodParams
                $RequestSuccessful = $true
                $respHeaders = $null
                if ($resp -and $resp.Headers) { $respHeaders = $resp.Headers }
                $approx = $null
                $reqUri = $null
                try { if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) { $reqUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } } catch { $reqUri = $null }
                if ($respHeaders) {
                    $val = $null
                    if ($respHeaders.ContainsKey('x-ms-approximate-messages-count')) {
                        $val = $respHeaders['x-ms-approximate-messages-count']
                    } else {
                        foreach ($key in $respHeaders.Keys) { if ($key -ieq 'x-ms-approximate-messages-count') { $val = $respHeaders[$key]; break } }
                    }
                    if ($null -ne $val) {
                        $approxStr = if ($val -is [array]) { if ($val.Length -gt 0) { $val[0] } else { $null } } else { $val }
                        if ($approxStr) { try { $approx = [int]$approxStr } catch { $approx = $null } }
                    }
                }
                $hdrHash = @{}
                if ($respHeaders) { foreach ($key in $respHeaders.Keys) { $hdrHash[$key] = $respHeaders[$key] } }
                return [PSCustomObject]@{ ApproximateMessagesCount = $approx; Headers = $hdrHash; Uri = $reqUri }
            }

            # Queue clear messages: DELETE on /<queue>/messages — return compact response
            if ($UseInvokeWebRequest -and $Service -eq 'queue' -and $Method -eq 'DELETE' -and ($Uri.AbsolutePath.ToLower().EndsWith('/messages'))) {
                Write-Verbose 'Processing queue clear messages response headers'
                $resp = Invoke-WebRequest @RestMethodParams
                $RequestSuccessful = $true
                $status = $null
                $reqUri = $null
                $respHeaders = $null
                try { if ($resp -and $resp.StatusCode) { $status = [int]$resp.StatusCode } } catch { }
                try { if (-not $status -and $resp -and $resp.BaseResponse) { $status = [int]$resp.BaseResponse.StatusCode } } catch { }
                try { if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) { $reqUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } } catch { }
                if ($resp -and $resp.Headers) { $respHeaders = $resp.Headers }
                $hdrHash = @{}
                if ($respHeaders) { foreach ($key in $respHeaders.Keys) { $hdrHash[$key] = $respHeaders[$key] } }
                return [PSCustomObject]@{ StatusCode = $status; Headers = $hdrHash; Uri = $reqUri }
            }

            # Generic DELETE compact response across services
            if ($UseInvokeWebRequest -and $Method -eq 'DELETE') {
                Write-Verbose 'Processing generic DELETE response headers'
                $resp = Invoke-WebRequest @RestMethodParams
                $RequestSuccessful = $true
                $status = $null
                $reqUri = $null
                $respHeaders = $null
                try { if ($resp -and $resp.StatusCode) { $status = [int]$resp.StatusCode } } catch { }
                try { if (-not $status -and $resp -and $resp.BaseResponse) { $status = [int]$resp.BaseResponse.StatusCode } } catch { }
                try { if ($resp -and $resp.BaseResponse -and $resp.BaseResponse.ResponseUri) { $reqUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } } catch { }
                if ($resp -and $resp.Headers) { $respHeaders = $resp.Headers }
                $hdrHash = @{}
                if ($respHeaders) { foreach ($key in $respHeaders.Keys) { $hdrHash[$key] = $respHeaders[$key] } }
                return [PSCustomObject]@{ StatusCode = $status; Headers = $hdrHash; Uri = $reqUri }
            }

            if ($UseInvokeWebRequest) { $Response = Invoke-WebRequest @RestMethodParams }
            else { $Response = Invoke-RestMethod @RestMethodParams }
            $RequestSuccessful = $true

            # Generic XML list parser: if response is XML string, parse into PSObjects
            if ($Response -is [string]) {
                $respText = $Response.Trim()
                if ($respText.StartsWith('<?xml') -and $respText.IndexOf('<EnumerationResults') -ge 0) {
                    try {
                        $xml = Convert-XmlStringToDocument -XmlText $respText
                        if ($Service -eq 'blob') {
                            $containers = @()
                            foreach ($node in $xml.SelectNodes('//Container')) {
                                $nameNode = $node.SelectSingleNode('Name')
                                $propsNode = $node.SelectSingleNode('Properties')
                                $props = $null
                                if ($propsNode -and $propsNode.HasChildNodes) {
                                    $props = @{}
                                    foreach ($p in $propsNode.ChildNodes) { $props[$p.Name] = $p.InnerText }
                                }
                                $containers += ([PSCustomObject]@{ Name = $nameNode.InnerText; Properties = $props })
                            }
                            if ($containers.Count -gt 0) { return $containers }
                        } elseif ($Service -eq 'queue') {
                            $queues = @()
                            foreach ($node in $xml.SelectNodes('//Queue')) {
                                $nameNode = $node.SelectSingleNode('Name')
                                $metaNode = $node.SelectSingleNode('Metadata')
                                $meta = $null
                                if ($metaNode -and $metaNode.HasChildNodes) {
                                    $meta = @{}
                                    foreach ($m in $metaNode.ChildNodes) { $meta[$m.Name] = $m.InnerText }
                                }
                                $queues += ([PSCustomObject]@{ Name = $nameNode.InnerText; Metadata = $meta })
                            }
                            if ($queues.Count -gt 0) { return $queues }
                        }
                    } catch {
                        # fall through to specific handlers below
                    }
                }
            }

            # Queue list: convert XML to PSObjects { Name, Metadata? }
            if (($Service -eq 'queue' -and $Component -eq 'list') -or ($Service -eq 'queue' -and $Uri.Query -match 'comp=list')) {
                try {
                    # Normalize to XmlDocument robustly
                    $xml = $null
                    if ($Response -is [System.Xml.XmlDocument]) { $xml = $Response }
                    elseif ($Response -is [string]) {
                        $xml = Convert-XmlStringToDocument -XmlText $Response
                    } else {
                        $xml = New-Object System.Xml.XmlDocument
                        $xml.LoadXml(($Response | Out-String))
                    }

                    $queueNodes = $xml.SelectNodes('//Queue')
                    $queues = foreach ($node in $queueNodes) {
                        $nameNode = $node.SelectSingleNode('Name')
                        $metaNode = $node.SelectSingleNode('Metadata')
                        $meta = $null
                        if ($metaNode -and $metaNode.HasChildNodes) {
                            $meta = @{}
                            foreach ($m in $metaNode.ChildNodes) { $meta[$m.Name] = $m.InnerText }
                        }
                        $q = [PSCustomObject]@{ Name = $nameNode.InnerText; Metadata = $meta }
                        $q
                    }
                    return $queues
                } catch {
                    # Fallback: return original response if parsing fails
                    return $Response
                }
            }

            # Blob containers list: convert XML to PSObjects { Name, Properties? }
            if (($Service -eq 'blob' -and $Component -eq 'list') -or ($Service -eq 'blob' -and $Uri.Query -match 'comp=list')) {
                try {
                    # Normalize to XmlDocument robustly
                    $xml = $null
                    if ($Response -is [System.Xml.XmlDocument]) { $xml = $Response }
                    elseif ($Response -is [string]) {
                        $xml = Convert-XmlStringToDocument -XmlText $Response
                    } else {
                        $xml = New-Object System.Xml.XmlDocument
                        $xml.LoadXml(($Response | Out-String))
                    }

                    $containerNodes = $xml.SelectNodes('//Container')
                    $containers = foreach ($node in $containerNodes) {
                        $nameNode = $node.SelectSingleNode('Name')
                        $propsNode = $node.SelectSingleNode('Properties')
                        $props = $null
                        if ($propsNode -and $propsNode.HasChildNodes) {
                            $props = @{}
                            foreach ($p in $propsNode.ChildNodes) { $props[$p.Name] = $p.InnerText }
                        }
                        [PSCustomObject]@{ Name = $nameNode.InnerText; Properties = $props }
                    }
                    return $containers
                } catch { return $Response }
            }

            # Fallback: generic XML-to-PSObject conversion for known list shapes
            try {
                $isXml = $false
                $xmlDoc = $null
                if ($Response -is [System.Xml.XmlDocument]) { $xmlDoc = $Response; $isXml = $true }
                elseif ($Response -is [string] -and $Response.TrimStart().StartsWith('<?xml')) {
                    $xmlDoc = Convert-XmlStringToDocument -XmlText $Response
                    $isXml = $true
                }
                if ($isXml -and $null -ne $xmlDoc) {
                    if ($Service -eq 'blob') {
                        $containers = foreach ($node in $xmlDoc.SelectNodes('//Container')) {
                            $nameNode = $node.SelectSingleNode('Name')
                            $propsNode = $node.SelectSingleNode('Properties')
                            $props = $null
                            if ($propsNode -and $propsNode.HasChildNodes) {
                                $props = @{}
                                foreach ($p in $propsNode.ChildNodes) { $props[$p.Name] = $p.InnerText }
                            }
                            [PSCustomObject]@{ Name = $nameNode.InnerText; Properties = $props }
                        }
                        if ($containers.Count -gt 0) { return $containers }
                    } elseif ($Service -eq 'queue') {

                        $queues = foreach ($node in $xmlDoc.SelectNodes('//Queue')) {
                            $nameNode = $node.SelectSingleNode('Name')
                            $metaNode = $node.SelectSingleNode('Metadata')
                            $meta = $null
                            if ($metaNode -and $metaNode.HasChildNodes) {
                                $meta = @{}
                                foreach ($m in $metaNode.ChildNodes) { $meta[$m.Name] = $m.InnerText }
                            }
                            [PSCustomObject]@{ Name = $nameNode.InnerText; Metadata = $meta }
                        }
                        if ($queues.Count -gt 0) { return $queues }
                    }
                }
            } catch { }

            # Table service: if response is JSON string, convert to PSObject
            if ($Service -eq 'table') {
                try {
                    if ($Response -is [string]) {
                        $obj = $Response | ConvertFrom-Json -Depth 10
                        return $obj
                    }
                } catch { return $Response }
            }

            # Default: return the raw response (Invoke-RestMethod returns PSObjects for JSON)
            return $Response
        } catch {
            $ShouldRetry = $false
            $WaitTime = 0
            $Message = $_.Exception.Message

            # Check for 429 Too Many Requests
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 429) {
                $RetryAfterHeader = $_.Exception.Response.Headers['Retry-After']
                if ($RetryAfterHeader) {
                    $WaitTime = [int]$RetryAfterHeader
                    $ShouldRetry = $true
                } elseif ($RetryCount -lt $MaxRetries) {
                    $WaitTime = [Math]::Min([Math]::Pow(2, $RetryCount), 60)
                    $ShouldRetry = $true
                }
                Write-Warning "Rate limited (429). Waiting $WaitTime seconds. Attempt $($RetryCount + 1) of $MaxRetries"
            }
            # Check for 503 Service Unavailable
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -eq 503) {
                if ($RetryCount -lt $MaxRetries) {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1
                    $ShouldRetry = $true
                    Write-Warning "Service unavailable (503). Waiting $WaitTime seconds. Attempt $($RetryCount + 1) of $MaxRetries"
                }
            }
            # Check for 500/502/504 server errors
            elseif ($_.Exception.Response -and $_.Exception.Response.StatusCode -in @(500, 502, 504)) {
                if ($RetryCount -lt $MaxRetries) {
                    $WaitTime = Get-Random -Minimum 1.1 -Maximum 3.1
                    $ShouldRetry = $true
                    Write-Warning "Server error ($($_.Exception.Response.StatusCode)). Waiting $WaitTime seconds. Attempt $($RetryCount + 1) of $MaxRetries"
                }
            }

            if ($ShouldRetry -and $RetryCount -lt $MaxRetries) {
                $RetryCount++
                if ($WaitTime -gt 0) {
                    Start-Sleep -Seconds $WaitTime
                }
                Write-Information "$($Method.ToUpper()) [ $Uri ] | attempt: $($RetryCount + 1) of $MaxRetries"

                # Regenerate time-based headers for retry and rebuild signature using helpers
                $UtcNow = [DateTime]::UtcNow.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
                if ($Service -eq 'table') {
                    # Table: Date must be non-empty and match x-ms-date
                    $RequestHeaders['x-ms-date'] = $UtcNow
                    $RequestHeaders['Date'] = $UtcNow
                    $CanonicalizedResource = Get-CanonicalizedResourceSharedKey -AccountName $AccountName -Uri $Uri -TableFormat
                    $StringToSign = Get-StringToSignTable -Method $Method -ContentType $ContentType -Date $RequestHeaders['Date'] -CanonicalizedResource $CanonicalizedResource
                } else {
                    $RequestHeaders['x-ms-date'] = $UtcNow
                    $CanonicalizedHeaders = Get-CanonicalizedXmsHeaders -Headers $RequestHeaders
                    $CanonicalizedResource = Get-CanonicalizedResourceSharedKey -AccountName $AccountName -Uri $Uri
                    $StringToSign = Get-StringToSignBlobQueueFile -Method $Method -ContentType $ContentType -Headers $RequestHeaders -CanonicalizedHeaders $CanonicalizedHeaders -CanonicalizedResource $CanonicalizedResource
                }

                # Regenerate signature
                $Signature = New-SharedKeySignature -AccountKey $AccountKey -StringToSign $StringToSign
                $RequestHeaders['Authorization'] = "SharedKey ${AccountName}:${Signature}"

                $RestMethodParams['Headers'] = $RequestHeaders
            } else {
                $ErrorMessage = "Azure Storage API call failed: $Message"
                if ($_.Exception.Response) {
                    $ErrorMessage += " (Status: $($_.Exception.Response.StatusCode))"

                    try {
                        $ResponseBody = $_.ErrorDetails.Message
                        if (-not $ResponseBody -and $_.Exception.Response.Content) {
                            $ResponseBody = [System.IO.StreamReader]::new($_.Exception.Response.Content).ReadToEnd()
                        }
                        if ($ResponseBody) {
                            $ErrorMessage += "`nResponse: $ResponseBody"
                        }
                    } catch {
                        # Ignore errors reading response body
                    }
                }

                $ErrorMessage += "`nURI: $Uri"
                Write-Error -Message $ErrorMessage
                return
            }
        }
    } while (-not $RequestSuccessful -and $RetryCount -le $MaxRetries)

    if (-not $RequestSuccessful) {
        Write-Error "Azure Storage API call failed after $MaxRetries attempts`nURI: $Uri"
        return
    }
}
