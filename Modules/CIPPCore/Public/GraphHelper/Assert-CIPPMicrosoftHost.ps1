function Assert-CIPPMicrosoftHost {
    <#
    .SYNOPSIS
    Refuse to send a CIPP token to a host that is not a Microsoft service
    .DESCRIPTION
    Throws unless -Uri is an https URL on a Microsoft service domain. Broad parents that also host
    customer content (azure.com, windows.net, azurewebsites.net) are only trusted for named hosts.
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Uri
    )

    $Parsed = $null
    if (-not [uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$Parsed) -or
        $Parsed.Scheme -ne 'https' -or $Parsed.UserInfo) {
        throw "URL '$Uri' is not an https Microsoft service URL; the request was not sent."
    }

    $HostName = $Parsed.IdnHost.ToLowerInvariant()
    # The Autopatch host is the Intune portal's own backend, used by the AutopatchGroup standard.
    if ($HostName -in @('management.azure.com', 'intuneautopatchbeta-bwhtaqgefgcyaaa8.westeurope-01.azurewebsites.net')) { return }
    # securitycenter.windows.com covers the regional MDE provisioning hosts.
    foreach ($Domain in @('microsoft.com', 'microsoftonline.com', 'office.com', 'office365.com', 'outlook.com', 'sharepoint.com', 'cloud.microsoft', 'securitycenter.windows.com')) {
        if ($HostName -eq $Domain -or $HostName.EndsWith(".$Domain")) { return }
    }
    throw "URL host '$HostName' is not a Microsoft service host; the request was not sent."
}
