Function Invoke-RemoveExConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Connector.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $request.Query.tenantFilter ?? $Request.Body.tenantFilter


    try {
        $Type = $Request.Query.Type ?? $Request.Body.Type
        $Guid = $Request.Query.GUID ?? $Request.Body.GUID
        $Params = @{ Identity = $Guid }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet "Remove-$($Type)Connector" -cmdParams $params -useSystemMailbox $true
        $Result = "Deleted Connector: $($Guid)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted connector $($Guid)" -sev Debug
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed deleting connector $($Guid). Error:$($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Result = $ErrorMessage.NormalizedError
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
