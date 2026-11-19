function New-CIPPAzStorageRequest {
    <#
    .SYNOPSIS
        Sends a REST request to Azure Blob or Queue storage with Shared Key authorization
    .DESCRIPTION
        Builds the request from the AzureWebJobsStorage connection string, signs it and sends it through the pooled
        CIPP REST client, which retries 429 and 5xx responses. Results by request:
        - list (comp=list): blobs or containers as { Name; Properties }, queues as { Name; Metadata }, every page
        - queue messages GET: { MessageId; InsertionTime; ExpirationTime; DequeueCount; Message }
        - queue comp=metadata: { ApproximateMessagesCount; Headers; Uri }
        - other GET: { Bytes; Length; Headers; Uri }
        - DELETE: { StatusCode; Headers; Uri }
        A failed request writes an error; use -ErrorAction Stop to throw it.
    .EXAMPLE
        New-CIPPAzStorageRequest -Service 'blob' -Component 'list'
    .EXAMPLE
        New-CIPPAzStorageRequest -Service 'queue' -Resource 'myqueue/messages' -Method DELETE
    .LINK
        https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('blob', 'queue')]
        [string]$Service,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Resource,

        # Sets comp=<Component>, e.g. list or metadata
        [Parameter(Mandatory = $false, Position = 2)]
        [string]$Component,

        [Parameter(Mandatory = $false)]
        [hashtable]$QueryParams,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string]$Method = 'GET',

        # A string, a byte[], or an object sent as JSON
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

    $Connection = @{}
    foreach ($Part in $ConnectionString -split ';') {
        if ($Part -match '^\s*(.+?)=(.+?)\s*$') { $Connection[$Matches[1]] = $Matches[2] }
    }
    $DevStorage = $Connection['UseDevelopmentStorage'] -eq 'true'
    $AccountName = $Connection['AccountName'] ?? $(if ($DevStorage) { 'devstoreaccount1' })
    # The storage emulator's published well-known key
    $AccountKey = $Connection['AccountKey'] ?? $(if ($DevStorage) { 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==' })
    if (-not $AccountName -or -not $AccountKey) {
        Write-Error 'The storage connection string needs AccountName and AccountKey'
        return
    }

    $Endpoint = $Connection["$([char]::ToUpper($Service[0]))$($Service.Substring(1))Endpoint"]
    $UriBuilder = if ($Endpoint) {
        $Builder = [System.UriBuilder]::new($Endpoint)
        $Builder.Path = "$($Builder.Path.TrimEnd('/'))/$Resource"
        $Builder
    } elseif ($DevStorage) {
        [System.UriBuilder]::new('http', '127.0.0.1', $(if ($Service -eq 'blob') { 10000 } else { 10001 }), "$AccountName/$Resource")
    } else {
        [System.UriBuilder]::new($Connection['DefaultEndpointsProtocol'] ?? 'https', "$AccountName.$Service.$($Connection['EndpointSuffix'] ?? 'core.windows.net')", -1, $Resource)
    }
    $Query = [System.Web.HttpUtility]::ParseQueryString('')
    if ($QueryParams) { foreach ($Key in $QueryParams.Keys) { $Query.Add($Key, [string]$QueryParams[$Key]) } }
    if ($Component -and -not $Query['comp']) { $Query.Add('comp', $Component) }
    $UriBuilder.Query = $Query.ToString()
    $Uri = $UriBuilder.Uri

    $IsList = $Query['comp'] -eq 'list'
    # Bodies go as bytes: the client adds no Content-Type of its own, so the request matches its signature
    $BodyBytes = [byte[]]::new(0)
    if ($Body -is [byte[]]) { $BodyBytes = $Body }
    elseif ($Body -is [string]) { $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes($Body) }
    elseif ($null -ne $Body) { $BodyBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 10 -Compress)) }
    $ContentLength = $BodyBytes.Length

    $RequestHeaders = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $RequestHeaders['x-ms-version'] = '2023-11-03'
    $RequestHeaders['x-ms-date'] = [DateTime]::UtcNow.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Service -eq 'queue' -or $IsList) { $RequestHeaders['Accept'] = 'application/xml' }
    if ($Service -eq 'blob' -and $Method -eq 'PUT' -and -not $Query['comp']) { $RequestHeaders['x-ms-blob-type'] = 'BlockBlob' }
    foreach ($Key in $Headers.Keys) { $RequestHeaders[$Key] = [string]$Headers[$Key] }

    # Shared Key string to sign: verb, standard headers, x-ms-* headers sorted, then the resource and sorted query
    $XmsNames = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $RequestHeaders.Keys) { if ($Key -like 'x-ms-*') { $XmsNames.Add($Key.ToLowerInvariant()) } }
    $XmsNames.Sort([System.StringComparer]::Ordinal)
    $QueryNames = [System.Collections.Generic.List[string]]::new()
    foreach ($Key in $Query.AllKeys) { $QueryNames.Add($Key.ToLowerInvariant()) }
    $QueryNames.Sort([System.StringComparer]::Ordinal)
    $StringToSign = @(
        $Method
        $RequestHeaders['Content-Encoding']
        $RequestHeaders['Content-Language']
        $(if ($ContentLength -gt 0) { $ContentLength } else { '' })
        $RequestHeaders['Content-MD5']
        $ContentType
        ''
        $RequestHeaders['If-Modified-Since']
        $RequestHeaders['If-Match']
        $RequestHeaders['If-None-Match']
        $RequestHeaders['If-Unmodified-Since']
        $RequestHeaders['Range']
        foreach ($Name in $XmsNames) { '{0}:{1}' -f $Name, ($RequestHeaders[$Name] -replace '\s+', ' ') }
        "/$AccountName$($Uri.AbsolutePath)"
        foreach ($Name in $QueryNames) { '{0}:{1}' -f $Name, $Query[$Name] }
    ) -join "`n"
    $Hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($AccountKey))
    $RequestHeaders['Authorization'] = 'SharedKey {0}:{1}' -f $AccountName, [Convert]::ToBase64String($Hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($StringToSign)))
    $Hmac.Dispose()

    $Request = [CIPP.CIPPConcurrentRequest]@{ Uri = $Uri.AbsoluteUri; Method = $Method; Headers = $RequestHeaders; ContentType = $ContentType; TimeoutSec = 300 }
    if ($ContentLength -gt 0) { $Request.BodyBytes = $BodyBytes }
    Write-Information "$Method [ $Uri ]"
    $Response = [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@($Request), 1, $MaxRetries, $global:CraftPipelineStopToken)[0]
    if (-not $Response.IsSuccess) {
        Write-Error ("Azure Storage API call failed: Status {0} {1}`nResponse: {2}`nURI: {3}" -f $Response.StatusCode, $Response.Error, $Response.Result.Content, $Uri)
        return
    }

    $ResponseHeaders = @{}
    foreach ($Header in $Response.Result.ResponseHeaders.GetEnumerator()) { $ResponseHeaders[$Header.Key] = $Header.Value -join ',' }
    if ($Method -eq 'DELETE') { return [PSCustomObject]@{ StatusCode = $Response.StatusCode; Headers = $ResponseHeaders; Uri = $Uri.AbsoluteUri } }
    if ($Method -ne 'GET') { return }
    if ($Query['comp'] -eq 'metadata' -and $Service -eq 'queue') {
        return [PSCustomObject]@{ ApproximateMessagesCount = $ResponseHeaders['x-ms-approximate-messages-count'] -as [int]; Headers = $ResponseHeaders; Uri = $Uri.AbsoluteUri }
    }
    $IsMessages = $Service -eq 'queue' -and $Uri.AbsolutePath.EndsWith('/messages', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $IsList -and -not $IsMessages) {
        $Bytes = $Response.Result.ContentBytes ?? [System.Text.Encoding]::UTF8.GetBytes($Response.Result.Content)
        return [PSCustomObject]@{ Bytes = $Bytes; Length = $Bytes.Length; Headers = $ResponseHeaders; Uri = $Uri.AbsoluteUri }
    }

    $Xml = [System.Xml.XmlDocument]::new()
    $Xml.LoadXml($Response.Result.Content.TrimStart([char]0xFEFF))
    if ($IsMessages) {
        foreach ($Node in $Xml.SelectNodes('//QueueMessage')) {
            $Text = $Node.SelectSingleNode('MessageText')?.InnerText
            $Message = $Text
            if ($Text -match '^\s*[\[{]') { try { $Message = ConvertFrom-Json -InputObject $Text -Depth 20 -ErrorAction Stop } catch { $Message = $Text } }
            [PSCustomObject]@{
                MessageId      = $Node.SelectSingleNode('MessageId')?.InnerText
                InsertionTime  = $Node.SelectSingleNode('InsertionTime')?.InnerText
                ExpirationTime = $Node.SelectSingleNode('ExpirationTime')?.InnerText
                DequeueCount   = $Node.SelectSingleNode('DequeueCount')?.InnerText -as [int]
                Message        = $Message
            }
        }
        return
    }
    $DetailName = if ($Service -eq 'queue') { 'Metadata' } else { 'Properties' }
    foreach ($Node in $Xml.SelectNodes('//Container|//Blob|//Queue')) {
        $Details = $null
        $DetailNode = $Node.SelectSingleNode($DetailName)
        if ($DetailNode -and $DetailNode.HasChildNodes) {
            $Details = @{}
            foreach ($Child in $DetailNode.ChildNodes) { $Details[$Child.Name] = $Child.InnerText }
        }
        [PSCustomObject]@{ Name = $Node.SelectSingleNode('Name').InnerText; $DetailName = $Details }
    }
    # A listing is returned in pages; NextMarker continues it.
    $NextMarker = $Xml.SelectSingleNode('//NextMarker')?.InnerText
    if ($NextMarker) {
        $NextPage = @{} + $PSBoundParameters
        $NextPage.QueryParams = if ($QueryParams) { $QueryParams.Clone() } else { @{} }
        $NextPage.QueryParams.marker = $NextMarker
        New-CIPPAzStorageRequest @NextPage
    }
}
