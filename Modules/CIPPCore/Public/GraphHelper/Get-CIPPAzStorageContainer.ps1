function Get-CIPPAzStorageContainer {
    <#
    .SYNOPSIS
        Lists Azure Storage blob containers using Shared Key auth.
    .DESCRIPTION
        Uses New-CIPPAzStorageRequest to call the Blob service list API.
        - Uses server-side 'prefix' when Name ends with a single trailing '*'.
        - Builds container URIs from the connection string (standard, provided endpoint, emulator).
        - Passes through container Properties returned by the service.
    .PARAMETER Name
        Container name filter. Supports wildcards (e.g., 'cipp*'). Defaults to '*'.
        When the pattern ends with a single trailing '*' and contains no other wildcards,
        a server-side 'prefix' is used for listing; otherwise client-side filtering is applied.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage
    .EXAMPLE
        Get-CIPPAzStorageContainer -Name 'cipp*'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Name = '*',

        [Parameter(Mandatory = $false)]
        [string]$ConnectionString = $env:AzureWebJobsStorage
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

        function Get-BlobBaseInfo {
            param([hashtable]$ConnParams)
            $service = 'blob'
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
                    Port    = 10000
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
                Host    = "$account.blob.$suffix"
                Port    = -1
                Path    = $null
                Mode    = 'Standard'
                Account = $account
            }
        }

        function Build-ContainerUri {
            param([pscustomobject]$BaseInfo, [string]$ContainerName)
            $ub = [System.UriBuilder]::new()
            $ub.Scheme = $BaseInfo.Scheme
            $ub.Host = $BaseInfo.Host
            if ($BaseInfo.Port -and $BaseInfo.Port -ne -1) { $ub.Port = [int]$BaseInfo.Port }
            switch ($BaseInfo.Mode) {
                'ProvidedEndpoint' {
                    $prefixPath = $BaseInfo.Path
                    if ([string]::IsNullOrEmpty($prefixPath)) { $ub.Path = "/$ContainerName" }
                    else { $ub.Path = ("$prefixPath/$ContainerName").Replace('//', '/') }
                }
                'Emulator' { $ub.Path = "$($BaseInfo.Account)/$ContainerName" }
                default { $ub.Path = "/$ContainerName" }
            }
            $ub.Uri.AbsoluteUri
        }
    }

    process {
        $connParams = Parse-ConnString -Conn $ConnectionString
        $baseInfo = Get-BlobBaseInfo -ConnParams $connParams

        # Determine server-side prefix optimization
        $serverPrefix = $null
        $pattern = $Name
        if ([string]::IsNullOrEmpty($pattern)) { $pattern = '*' }
        $canUsePrefix = $false
        if ($pattern.EndsWith('*') -and $pattern.IndexOfAny([char[]]@('*', '?')) -eq ($pattern.Length - 1)) {
            $serverPrefix = $pattern.Substring(0, $pattern.Length - 1)
            $canUsePrefix = $true
        }

        $listParams = @{ Service = 'blob'; Component = 'list'; ConnectionString = $ConnectionString }
        if ($canUsePrefix -and $serverPrefix) { $listParams['QueryParams'] = @{ prefix = $serverPrefix } }

        $containers = New-CIPPAzStorageRequest @listParams
        if (-not $containers) { return @() }

        # Normalize to array of {Name, Properties}
        $items = @()
        foreach ($c in $containers) {
            if ($null -ne $c -and $c.PSObject.Properties['Name']) {
                $items += [PSCustomObject]@{ Name = $c.Name; Properties = $c.Properties }
            }
        }

        # Client-side wildcard filtering when needed
        if (-not $canUsePrefix) {
            $items = $items | Where-Object { $_.Name -like $pattern }
        }

        $results = @()
        foreach ($it in $items) {
            $uri = Build-ContainerUri -BaseInfo $baseInfo -ContainerName $it.Name
            $results += [PSCustomObject]@{
                Name       = $it.Name
                Uri        = $uri
                Properties = $it.Properties
            }
        }

        # Optional banner for UX parity when displayed directly
        if ($results.Count -gt 0 -and $baseInfo.Account) {
            Write-Host "\n   Storage Account Name: $($baseInfo.Account)\n" -ForegroundColor DarkGray
        }

        $results
    }
}
