function Invoke-ListBrandingPresets {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists named report branding presets — colours, logo, cover image, footer and watermark —
        that a report template can be pointed at instead of the default branding.

        Read-only and separate from ExecBrandingSettings on purpose: building a report should not
        require the app-settings permission that editing branding does.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        # Image payloads are large and a picker only needs names and colours, so callers ask for
        # the artwork explicitly.
        $IncludeImages = [bool]$Request.Query.includeImages

        $Presets = Get-CIPPBrandingPreset -SkipImageData:(-not $IncludeImages)

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Presets)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list branding presets: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Error: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
        })
}
