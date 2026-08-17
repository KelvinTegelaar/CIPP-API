function Invoke-GetVersion {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Compares the caller's reported CIPP version against the latest published release and reports whether the frontend or the API is out of date, alongside the hosting shape (hosting type, App Service SKU, runtime stack) and the recorded version-update history.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $CIPPVersion = $request.query.LocalVersion

    try {
        $Version = Assert-CippVersion -CIPPVersion $CIPPVersion
    } catch {
        # GitHub unreachable or rate-limited - the release comparison is unavailable, but the
        # hosting shape and update history below do not depend on it. Degrade instead of
        # failing the request, so a support-ticket paste still carries what we could read.
        $Version = [PSCustomObject]@{
            LocalCIPPVersion     = $CIPPVersion
            RemoteCIPPVersion    = 'Unknown'
            LocalCIPPAPIVersion  = $env:APP_VERSION ?? 'Unknown'
            RemoteCIPPAPIVersion = 'Unknown'
            OutOfDateCIPP        = $false
            OutOfDateCIPPAPI     = $false
        }
    }

    # Hosting shape for support tickets. Environment only - no ARM call - so this stays fast
    # and works without a managed identity; anything unset degrades to 'Unknown'.
    $SKU = [string]::IsNullOrWhiteSpace($env:WEBSITE_SKU) ? 'Unknown' : $env:WEBSITE_SKU
    $RuntimeStack = if ($env:WEBSITE_SKU -eq 'FlexConsumption') { 'Flex Consumption' } elseif ($IsLinux) { 'Linux' } else { 'Windows' }
    $Hosting = [PSCustomObject]@{
        HostingType  = $env:CIPP_HOSTED -eq 'true' ? 'CyberDrain-hosted' : 'Self-hosted'
        SKU          = $SKU
        RuntimeStack = $RuntimeStack
    }

    # Update history recorded at warmup by Update-CIPPVersionHistory; empty until the
    # instance has moved between builds at least once.
    $History = @(Get-CIPPVersionHistory)

    $Version | Add-Member -NotePropertyName 'Hosting' -NotePropertyValue $Hosting
    $Version | Add-Member -NotePropertyName 'VersionHistory' -NotePropertyValue $History
    $Version | Add-Member -NotePropertyName 'LastUpdate' -NotePropertyValue ($History.Count -gt 0 ? $History[0] : $null)

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Version
        })
}
