function Invoke-ExecCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.CustomScript.Execute
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $ScriptGuid = $Request.Body.ScriptGuid
        $TenantFilter = $Request.Body.TenantFilter
        $Parameters = $Request.Body.Parameters ?? @{}

        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            throw 'ScriptGuid is required'
        }

        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            throw 'TenantFilter is required'
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -user $Request.Headers.'x-ms-client-principal-name' -message "Executing custom script with GUID: $ScriptGuid" -sev Info

        # Execute script (lookup happens inside New-CippCustomScriptExecution)
        $Result = New-CippCustomScriptExecution -ScriptGuid $ScriptGuid -TenantFilter $TenantFilter -Parameters $Parameters

        $Body = @{
            Results     = $Result
            ScriptGuid  = $ScriptGuid
            Tenant      = $TenantFilter
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -user $Request.Headers.'x-ms-client-principal-name' -message "Failed to execute custom script: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{
            Error = $ErrorMessage.NormalizedError
            Tenant = $TenantFilter
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $Body
        })
}
