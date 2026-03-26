function Invoke-ListCustomScripts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.CustomScript.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $Headers = $Request.Headers

    try {
        $ScriptGuid = $Request.Query.ScriptGuid ?? $Request.Body.ScriptGuid
        $IncludeAllVersions = [bool]($Request.Query.IncludeAllVersions ?? $Request.Body.IncludeAllVersions)

        $Table = Get-CippTable -tablename 'CustomPowershellScripts'

        if ($ScriptGuid) {
            # Get specific script
            $Filter = "PartitionKey eq 'CustomScript' and ScriptGuid eq '{0}'" -f $ScriptGuid
            $Scripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Sort-Object -Property Version -Descending

            if ($Scripts) {
                if (-not $IncludeAllVersions) {
                    # Return only latest version
                    $Scripts = $Scripts | Sort-Object -Property Version -Descending | Select-Object -First 1
                }
            }
        } else {
            # Get all scripts
            $Filter = "PartitionKey eq 'CustomScript'"
            $AllScripts = Get-CIPPAzDataTableEntity @Table -Filter $Filter

            # Group by ScriptGuid and get latest version of each
            $Scripts = $AllScripts |
                Group-Object -Property ScriptGuid |
                ForEach-Object {
                    $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
                }
        }

        $Body = $Scripts

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -headers $Headers -message "Failed to list custom scripts: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? [HttpStatusCode]::OK
            Body       = @($Body)
        })
}
