function Invoke-ExecExtensionClearHIBPKey {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint ?? 'ExtensionClearHIBPKey'
    $Headers = $Request.Headers

    $Results = try {
        Remove-ExtensionAPIKey -Extension 'HIBP' | Out-Null
        $Result = 'Successfully cleared the HIBP API key.'
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Cleared API key for extension 'HIBP'" -Sev 'Info'
        $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Failed to clear API key for extension 'HIBP': $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        'Failed to clear the HIBP API key'
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })
}
