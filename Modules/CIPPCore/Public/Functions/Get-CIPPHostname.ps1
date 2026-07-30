function Get-CIPPHostname {
    <#
    .SYNOPSIS
        Resolves the hostname the CIPP instance is currently being served from
    .DESCRIPTION
        Works out the host of the running instance, preferring the inbound request so the value always
        reflects the URL the user is on at the time of the call. Falls back to the stored instance
        property and then the platform hostname for contexts where no request is available.
        Returns the host only (no scheme, no port), matching the format stored in Config/InstanceProperties/CIPPURL.
    .PARAMETER Headers
        The request headers, usually $Request.Headers. Optional - omit for non-HTTP contexts.
    .PARAMETER Save
        Persist the resolved hostname to Config/InstanceProperties/CIPPURL so background jobs pick up the current URL.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPHostname -Headers $Request.Headers -Save
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [switch]$Save
    )

    $Hostname = $null

    if ($Headers) {
        # x-ms-original-url carries the full URL the client requested, including any custom domain
        $Candidates = @(
            $Headers.'x-ms-original-url'
            $Headers.origin
            $Headers.referer
        )
        foreach ($Candidate in $Candidates) {
            if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
            try {
                $Parsed = [System.Uri]$Candidate
                if ($Parsed.Host) {
                    $Hostname = $Parsed.Host
                    break
                }
            } catch {
                continue
            }
        }

        # Proxied deployments may only expose the host, not a full URL
        if (!$Hostname) {
            $HostHeader = $Headers.'x-forwarded-host' ?? $Headers.host
            if (![string]::IsNullOrWhiteSpace($HostHeader)) {
                $Hostname = (($HostHeader -split ',')[0]).Trim().Split(':')[0]
            }
        }
    }

    # Only touch storage when we actually need it: as a fallback, or to persist the resolved value
    $StoredConfig = $null
    if (!$Hostname -or $Save.IsPresent) {
        $ConfigTable = Get-CIPPTable -TableName 'Config'
        $StoredConfig = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
    }

    if (!$Hostname -and ![string]::IsNullOrWhiteSpace($StoredConfig.Value)) {
        $Hostname = $StoredConfig.Value
    }

    if (!$Hostname -and ![string]::IsNullOrWhiteSpace($env:WEBSITE_HOSTNAME)) {
        $Hostname = $env:WEBSITE_HOSTNAME
    }

    if ($Save.IsPresent -and ![string]::IsNullOrWhiteSpace($Hostname) -and $StoredConfig.Value -ne $Hostname) {
        try {
            $AddObject = @{
                PartitionKey = 'InstanceProperties'
                RowKey       = 'CIPPURL'
                Value        = [string]$Hostname
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity $AddObject -Force
            Write-Information "Get-CIPPHostname: updated stored CIPPURL from '$($StoredConfig.Value)' to '$Hostname'"
        } catch {
            Write-Information "Get-CIPPHostname: failed to store CIPPURL: $($_.Exception.Message)"
        }
    }

    return $Hostname
}
