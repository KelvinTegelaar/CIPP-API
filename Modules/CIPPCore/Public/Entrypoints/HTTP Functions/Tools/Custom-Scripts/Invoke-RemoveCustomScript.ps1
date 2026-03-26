function Invoke-RemoveCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.CustomScript.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $ScriptGuid = $Request.Query.ScriptGuid ?? $Request.Body.ScriptGuid

        if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
            throw 'ScriptGuid is required'
        }

        $Table = Get-CippTable -tablename 'CustomPowershellScripts'

        # Actually delete all versions of the script
        $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
        $Scripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $Scripts) {
            throw "Script with GUID '$ScriptGuid' not found"
        }

        # Get script name for logging
        $ScriptName = ($Scripts | Select-Object -First 1).ScriptName

        # Delete all versions
        foreach ($script in $Scripts) {
            Remove-AzDataTableEntity @Table -Entity $script
        }

        Write-LogMessage -API $APIName -headers $Headers -message "Deleted custom script: $ScriptName (Versions: $($Scripts.Count))" -sev 'Info'

        $Body = @{
            Results = "Successfully removed custom script '$ScriptName'"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to remove custom script: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = $Body
        })
}
