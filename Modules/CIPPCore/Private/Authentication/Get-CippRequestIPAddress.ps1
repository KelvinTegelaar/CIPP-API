function Get-CippRequestIPAddress {
    <#
    .SYNOPSIS
        First x-forwarded-for hop with any port suffix and IPv6 brackets stripped.
    .FUNCTIONALITY
        Internal
    #>
    param($Request)
    $ForwardedFor = $Request.Headers.'x-forwarded-for' -split ',' | Select-Object -First 1
    $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
    return $ForwardedFor -replace $IPRegex, '$1' -replace '[\[\]]', ''
}
