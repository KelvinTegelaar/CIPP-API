function New-CIPPAzServiceSAS {
    [CmdletBinding()] param(
        [Parameter(Mandatory = $true)] [string] $AccountName,
        [Parameter(Mandatory = $true)] [string] $AccountKey,
        [Parameter(Mandatory = $true)] [ValidateSet('blob', 'queue', 'file', 'table')] [string] $Service,
        [Parameter(Mandatory = $true)] [string] $ResourcePath,
        [Parameter(Mandatory = $true)] [string] $Permissions,
        [Parameter(Mandatory = $false)] [DateTime] $StartTime,
        [Parameter(Mandatory = $true)] [DateTime] $ExpiryTime,
        [Parameter(Mandatory = $false)] [ValidateSet('http', 'https', 'https,http')] [string] $Protocol = 'https',
        [Parameter(Mandatory = $false)] [string] $IP,
        [Parameter(Mandatory = $false)] [string] $SignedIdentifier,
        [Parameter(Mandatory = $false)] [string] $Version = '2022-11-02',
        [Parameter(Mandatory = $false)] [ValidateSet('b', 'c', 'd', 'bv', 'bs', 'f', 's')] [string] $SignedResource,
        [Parameter(Mandatory = $false)] [int] $DirectoryDepth,
        [Parameter(Mandatory = $false)] [string] $SnapshotTime,
        # Optional response header overrides (Blob/Files)
        [Parameter(Mandatory = $false)] [string] $CacheControl,
        [Parameter(Mandatory = $false)] [string] $ContentDisposition,
        [Parameter(Mandatory = $false)] [string] $ContentEncoding,
        [Parameter(Mandatory = $false)] [string] $ContentLanguage,
        [Parameter(Mandatory = $false)] [string] $ContentType,
        # Optional encryption scope (Blob, 2020-12-06+)
        [Parameter(Mandatory = $false)] [string] $EncryptionScope,
        # Optional connection string for endpoint/emulator support
        [Parameter(Mandatory = $false)] [string] $ConnectionString = $env:AzureWebJobsStorage
    )

    # Local helpers: canonicalized resource and signature (standalone)
    function _GetCanonicalizedResource {
        param(
            [Parameter(Mandatory = $true)][string] $AccountName,
            [Parameter(Mandatory = $true)][ValidateSet('blob', 'queue', 'file', 'table')] [string] $Service,
            [Parameter(Mandatory = $true)][string] $ResourcePath
        )
        $decodedPath = [System.Web.HttpUtility]::UrlDecode(($ResourcePath.TrimStart('/')))
        switch ($Service) {
            'blob' { return "/blob/$AccountName/$decodedPath" }
            'queue' { return "/queue/$AccountName/$decodedPath" }
            'file' { return "/file/$AccountName/$decodedPath" }
            'table' { return "/table/$AccountName/$decodedPath" }
        }
    }

    function _NewSharedKeySignature {
        param(
            [Parameter(Mandatory = $true)][string] $AccountKey,
            [Parameter(Mandatory = $true)][string] $StringToSign
        )
        $keyBytes = [Convert]::FromBase64String($AccountKey)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($StringToSign)
            $sig = $hmac.ComputeHash($bytes)
            return [Convert]::ToBase64String($sig)
        } finally { $hmac.Dispose() }
    }

    # Parse connection string for emulator/provided endpoints
    $ProvidedEndpoint = $null
    $ProvidedPath = $null
    $EmulatorHost = $null
    $EndpointSuffix = 'core.windows.net'

    if ($ConnectionString) {
        $conn = @{}
        foreach ($part in ($ConnectionString -split ';')) {
            $p = $part.Trim()
            if ($p -and $p -match '^(.+?)=(.+)$') { $conn[$matches[1]] = $matches[2] }
        }
        if ($conn['EndpointSuffix']) { $EndpointSuffix = $conn['EndpointSuffix'] }

        $ServiceCapitalized = [char]::ToUpper($Service[0]) + $Service.Substring(1)
        $EndpointKey = "${ServiceCapitalized}Endpoint"
        if ($conn[$EndpointKey]) {
            $ProvidedEndpoint = $conn[$EndpointKey]
            $ep = [Uri]::new($ProvidedEndpoint)
            $Protocol = $ep.Scheme
            $EmulatorHost = $ep.Host
            if ($ep.Port -ne -1) { $EmulatorHost = "$($ep.Host):$($ep.Port)" }
            $ProvidedPath = $ep.AbsolutePath.TrimEnd('/')
        } elseif ($conn['UseDevelopmentStorage'] -eq 'true') {
            # Emulator defaults
            if (-not $AccountName) { $AccountName = 'devstoreaccount1' }
            if (-not $AccountKey) { $AccountKey = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==' }
            $Protocol = 'http'
            $ports = @{ blob = 10000; queue = 10001; table = 10002 }
            $EmulatorHost = "127.0.0.1:$($ports[$Service])"
        }
    }

    # Build the resource URI
    if ($ResourcePath.StartsWith('/')) { $ResourcePath = $ResourcePath.TrimStart('/') }
    $UriBuilder = [System.UriBuilder]::new()
    $UriBuilder.Scheme = $Protocol

    if ($ProvidedEndpoint) {
        # Use provided endpoint + its base path
        if ($EmulatorHost -match '^(.+?):(\d+)$') { $UriBuilder.Host = $matches[1]; $UriBuilder.Port = [int]$matches[2] }
        else { $UriBuilder.Host = $EmulatorHost }
        $UriBuilder.Path = ("$ProvidedPath/$ResourcePath").Replace('//', '/')
    } elseif ($EmulatorHost) {
        # Emulator: include account name in path
        if ($EmulatorHost -match '^(.+?):(\d+)$') { $UriBuilder.Host = $matches[1]; $UriBuilder.Port = [int]$matches[2] }
        else { $UriBuilder.Host = $EmulatorHost }
        $UriBuilder.Path = "$AccountName/$ResourcePath"
    } else {
        # Standard Azure endpoint
        $UriBuilder.Host = "$AccountName.$Service.$EndpointSuffix"
        $UriBuilder.Path = $ResourcePath
    }
    $uri = $UriBuilder.Uri

    # Canonicalized resource for SAS string-to-sign (service-name style, 2015-02-21+)
    $canonicalizedResource = _GetCanonicalizedResource -AccountName $AccountName -Service $Service -ResourcePath $ResourcePath

    # Time formatting per SAS spec (ISO 8601 UTC)
    function _FormatSasTime($dt) {
        if ($null -eq $dt) { return '' }
        if ($dt -is [string]) {
            if ([string]::IsNullOrWhiteSpace($dt)) { return '' }
            $parsed = [DateTime]::Parse($dt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
            $utc = $parsed.ToUniversalTime()
            return $utc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        if ($dt -is [DateTime]) {
            $utc = ([DateTime]$dt).ToUniversalTime()
            return $utc.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        return ''
    }

    $st = _FormatSasTime $StartTime
    $se = _FormatSasTime $ExpiryTime
    if ([string]::IsNullOrEmpty($se)) { throw 'ExpiryTime is required for SAS generation.' }

    # Assemble query parameters (service-specific)
    $q = @{}
    $q['sp'] = $Permissions
    if ($st) { $q['st'] = $st }
    $q['se'] = $se
    if ($IP) { $q['sip'] = $IP }
    if ($Protocol) { $q['spr'] = $Protocol }
    if ($Version) { $q['sv'] = $Version }
    if ($SignedIdentifier) { $q['si'] = $SignedIdentifier }

    # Blob/Files response headers overrides
    if ($CacheControl) { $q['rscc'] = $CacheControl }
    if ($ContentDisposition) { $q['rscd'] = $ContentDisposition }
    if ($ContentEncoding) { $q['rsce'] = $ContentEncoding }
    if ($ContentLanguage) { $q['rscl'] = $ContentLanguage }
    if ($ContentType) { $q['rsct'] = $ContentType }

    # Resource-type specifics
    $includeEncryptionScope = $false
    if ($Service -eq 'blob') {
        if (-not $SignedResource) { throw 'SignedResource (sr) is required for blob SAS: use b, c, d, bv, or bs.' }
        $q['sr'] = $SignedResource
        # Blob snapshot time uses the 'snapshot' parameter when applicable
        if ($SnapshotTime) { $q['snapshot'] = $SnapshotTime }
        if ($SignedResource -eq 'd') {
            if ($null -eq $DirectoryDepth) { throw 'DirectoryDepth (sdd) is required when sr=d (Data Lake Hierarchical Namespace).' }
            $q['sdd'] = [string]$DirectoryDepth
        }
        if ($EncryptionScope -and $Version -ge '2020-12-06') {
            $q['ses'] = $EncryptionScope
            $includeEncryptionScope = $true
        }
    } elseif ($Service -eq 'file') {
        if (-not $SignedResource) { throw 'SignedResource (sr) is required for file SAS: use f or s.' }
        $q['sr'] = $SignedResource
        if ($SnapshotTime) { $q['sst'] = $SnapshotTime }
    } elseif ($Service -eq 'table') {
        # Table SAS may include ranges (spk/srk/epk/erk), omitted here unless future parameters are added
        # Table also uses tn (table name) in query, but canonicalizedResource already includes table name
        # We rely on canonicalizedResource and omit tn unless specified by callers via ResourcePath
    } elseif ($Service -eq 'queue') {
        # No sr for queue
    }

    # Construct string-to-sign based on service and version
    $StringToSign = $null
    if ($Service -eq 'blob') {
        # Version 2018-11-09 and later (optionally 2020-12-06 with encryption scope)
        $fields = @(
            $q['sp'],
            ($st ?? ''),
            $q['se'],
            $canonicalizedResource,
            ($q.ContainsKey('si') ? $q['si'] : ''),
            ($q.ContainsKey('sip') ? $q['sip'] : ''),
            ($q.ContainsKey('spr') ? $q['spr'] : ''),
            ($q.ContainsKey('sv') ? $q['sv'] : ''),
            $q['sr'],
            ($q.ContainsKey('snapshot') ? $q['snapshot'] : ''),
            ($includeEncryptionScope ? $q['ses'] : ''),
            ($q.ContainsKey('rscc') ? $q['rscc'] : ''),
            ($q.ContainsKey('rscd') ? $q['rscd'] : ''),
            ($q.ContainsKey('rsce') ? $q['rsce'] : ''),
            ($q.ContainsKey('rscl') ? $q['rscl'] : ''),
            ($q.ContainsKey('rsct') ? $q['rsct'] : '')
        )
        $StringToSign = ($fields -join "`n")
    } elseif ($Service -eq 'file') {
        # Use 2015-04-05+ format (no signedResource in string until 2018-11-09; we include response headers)
        $fields = @(
            $q['sp'],
            ($st ?? ''),
            $q['se'],
            $canonicalizedResource,
            ($q.ContainsKey('si') ? $q['si'] : ''),
            ($q.ContainsKey('sip') ? $q['sip'] : ''),
            ($q.ContainsKey('spr') ? $q['spr'] : ''),
            ($q.ContainsKey('sv') ? $q['sv'] : ''),
            ($q.ContainsKey('rscc') ? $q['rscc'] : ''),
            ($q.ContainsKey('rscd') ? $q['rscd'] : ''),
            ($q.ContainsKey('rsce') ? $q['rsce'] : ''),
            ($q.ContainsKey('rscl') ? $q['rscl'] : ''),
            ($q.ContainsKey('rsct') ? $q['rsct'] : '')
        )
        $StringToSign = ($fields -join "`n")
    } elseif ($Service -eq 'queue') {
        # Version 2015-04-05 and later
        $fields = @(
            $q['sp'],
            ($st ?? ''),
            $q['se'],
            $canonicalizedResource,
            ($q.ContainsKey('si') ? $q['si'] : ''),
            ($q.ContainsKey('sip') ? $q['sip'] : ''),
            ($q.ContainsKey('spr') ? $q['spr'] : ''),
            ($q.ContainsKey('sv') ? $q['sv'] : '')
        )
        $StringToSign = ($fields -join "`n")
    } elseif ($Service -eq 'table') {
        # Version 2015-04-05 and later
        $fields = @(
            $q['sp'],
            ($st ?? ''),
            $q['se'],
            $canonicalizedResource,
            ($q.ContainsKey('si') ? $q['si'] : ''),
            ($q.ContainsKey('sip') ? $q['sip'] : ''),
            ($q.ContainsKey('spr') ? $q['spr'] : ''),
            ($q.ContainsKey('sv') ? $q['sv'] : ''),
            '', # startingPartitionKey
            '', # startingRowKey
            '', # endingPartitionKey
            ''  # endingRowKey
        )
        $StringToSign = ($fields -join "`n")
    }

    # Generate signature using account key (HMAC-SHA256 over UTF-8 string-to-sign)
    try {
        $SignatureBase64 = _NewSharedKeySignature -AccountKey $AccountKey -StringToSign $StringToSign
    } catch {
        throw "Failed to create SAS signature: $($_.Exception.Message)"
    }

    # Store signature; will be URL-encoded when assembling query
    $q['sig'] = $SignatureBase64

    # Compose ordered query for readability (common fields first)
    $orderedKeys = @('sp', 'st', 'se', 'sip', 'spr', 'sv', 'sr', 'si', 'snapshot', 'ses', 'sdd', 'rscc', 'rscd', 'rsce', 'rscl', 'rsct', 'sig')
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $orderedKeys) {
        if ($q.ContainsKey($k) -and -not [string]::IsNullOrEmpty($q[$k])) {
            $parts.Add("$k=" + [System.Net.WebUtility]::UrlEncode($q[$k]))
        }
    }
    # Include any remaining keys
    foreach ($k in $q.Keys) {
        if ($orderedKeys -notcontains $k) {
            $parts.Add("$k=" + [System.Net.WebUtility]::UrlEncode($q[$k]))
        }
    }

    $token = '?' + ($parts -join '&')

    # Return structured output for debugging/usage
    [PSCustomObject]@{
        Token                 = $token
        Query                 = $q
        CanonicalizedResource = $canonicalizedResource
        StringToSign          = $StringToSign
        Version               = $Version
        Service               = $Service
        ResourceUri           = $uri.AbsoluteUri
    }
}
