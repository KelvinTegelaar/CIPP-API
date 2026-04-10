function Invoke-ExecExtensionClearHIBPKey {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Results = try {
        Remove-ExtensionAPIKey -Extension 'HIBP' | Out-Null
        'Successfully cleared the HIBP API key.'
    } catch {
        "Failed to clear the HIBP API key"
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
