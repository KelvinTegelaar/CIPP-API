function Get-CIPPAzStorageQueue {
    <#
    .SYNOPSIS
        Lists Azure Storage queues and approximate message counts using Shared Key auth.
    .DESCRIPTION
        Uses New-CIPPAzStorageRequest to call the Queue service REST API.
        - Lists queues (optionally with server-side prefix when Name ends with '*').
        - Enriches each queue with ApproximateMessageCount via comp=metadata.
        - Constructs queue URIs consistent with the resolved endpoint.
    .PARAMETER Name
        Queue name filter. Supports wildcards (e.g., 'cipp*'). Defaults to '*'.
        When the pattern ends with a single trailing '*' and contains no other wildcards,
        a server-side 'prefix' is used for listing; otherwise client-side filtering is applied.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage
    .PARAMETER NoCount
        If set, skips the metadata call and returns ApproximateMessageCount as $null.
    .EXAMPLE
        Get-CIPPAzStorageQueue -Name 'cippjta*'
        Returns objects similar to Get-AzStorageQueue with Name, Uri, and ApproximateMessageCount.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Name = '*',

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage,

        [Parameter(Mandatory = $false)]
        [switch]$NoCount
    )

    begin {
        function Parse-ConnString {
            param([string]$Conn)
            $map = @{}
            if (-not $Conn) { return $map }
            foreach ($part in ($Conn -split ';')) {
                $p = $part.Trim()
                if ($p -and $p -match '^(.+?)=(.+)$') { $map[$matches[1]] = $matches[2] }
            }
            $map
        }

        function Get-QueueBaseInfo {
            param([hashtable]$ConnParams)
            $service = 'queue'
            $svcCap = [char]::ToUpper($service[0]) + $service.Substring(1)
            $endpointKey = "${svcCap}Endpoint"
            $provided = $ConnParams[$endpointKey]
            $useDev = ($ConnParams['UseDevelopmentStorage'] -eq 'true')
            $account = $ConnParams['AccountName']

            if ($provided) {
                $u = [System.Uri]::new($provided)
                return [PSCustomObject]@{
                    Scheme  = $u.Scheme
                    Host    = $u.Host
                    Port    = $u.Port
                    Path    = $u.AbsolutePath.TrimEnd('/')
                    Mode    = 'ProvidedEndpoint'
                    Account = $account
                }
            }

            if ($useDev) {
                return [PSCustomObject]@{
                    Scheme  = 'http'
                    Host    = '127.0.0.1'
                    Port    = 10001
                    Path    = $null
                    Mode    = 'Emulator'
                    Account = ($account ?? 'devstoreaccount1')
                }
            }

            $suffix = $ConnParams['EndpointSuffix']
            if (-not $suffix) { $suffix = 'core.windows.net' }
            $scheme = $ConnParams['DefaultEndpointsProtocol']
            if (-not $scheme) { $scheme = 'https' }
            return [PSCustomObject]@{
                Scheme  = $scheme
                Host    = "$account.queue.$suffix"
                Port    = -1
                Path    = $null
                Mode    = 'Standard'
                Account = $account
            }
        }

        function Build-QueueUri {
            param([pscustomobject]$BaseInfo, [string]$QueueName)
            $ub = [System.UriBuilder]::new()
            $ub.Scheme = $BaseInfo.Scheme
            $ub.Host = $BaseInfo.Host
            if ($BaseInfo.Port -and $BaseInfo.Port -ne -1) { $ub.Port = [int]$BaseInfo.Port }
            switch ($BaseInfo.Mode) {
                'ProvidedEndpoint' {
                    $prefixPath = $BaseInfo.Path
                    if ([string]::IsNullOrEmpty($prefixPath)) { $ub.Path = "/$QueueName" }
                    else { $ub.Path = ("$prefixPath/$QueueName").Replace('//', '/') }
                }
                'Emulator' { $ub.Path = "$($BaseInfo.Account)/$QueueName" }
                default { $ub.Path = "/$QueueName" }
            }
            $ub.Uri.AbsoluteUri
        }
    }

    process {
        $connParams = Parse-ConnString -Conn $ConnectionString
        $baseInfo = Get-QueueBaseInfo -ConnParams $connParams

        # Determine server-side prefix optimization
        $serverPrefix = $null
        $pattern = $Name
        if ([string]::IsNullOrEmpty($pattern)) { $pattern = '*' }
        $canUsePrefix = $false
        if ($pattern.EndsWith('*') -and $pattern.IndexOfAny([char[]]@('*', '?')) -eq ($pattern.Length - 1)) {
            $serverPrefix = $pattern.Substring(0, $pattern.Length - 1)
            $canUsePrefix = $true
        }

        $listParams = @{ Service = 'queue'; Component = 'list'; ConnectionString = $ConnectionString }
        if ($canUsePrefix -and $serverPrefix) { $listParams['QueryParams'] = @{ prefix = $serverPrefix } }

        $queues = New-CIPPAzStorageRequest @listParams
        if (-not $queues) { return @() }

        # Normalize to array of names
        $queueItems = @()
        foreach ($q in $queues) {
            if ($null -ne $q -and $q.PSObject.Properties['Name']) { $queueItems += $q.Name }
        }

        # Client-side wildcard filtering when needed
        if (-not $canUsePrefix) {
            $queueItems = $queueItems | Where-Object { $_ -like $pattern }
        }

        $results = @()
        foreach ($qn in $queueItems) {
            $uri = Build-QueueUri -BaseInfo $baseInfo -QueueName $qn
            $count = $null
            if (-not $NoCount) {
                try {
                    $meta = New-CIPPAzStorageRequest -Service 'queue' -Component 'metadata' -Resource $qn -ConnectionString $ConnectionString -Method 'GET'
                    if ($meta -and $meta.PSObject.Properties['ApproximateMessagesCount']) { $count = $meta.ApproximateMessagesCount }
                } catch { $count = $null }
            }
            $results += [PSCustomObject]@{
                Name                    = $qn
                Uri                     = $uri
                ApproximateMessageCount = $count
            }
        }

        # Optional banner for UX parity when displayed directly
        if ($results.Count -gt 0 -and $baseInfo.Account) {
            Write-Host "\n   Storage Account Name: $($baseInfo.Account)\n" -ForegroundColor DarkGray
        }

        $results
    }
}
