function Invoke-ExecCustomScript {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Tests.ReadWrite
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

        # Extract wrapper properties if present
        $CIPPResultMarkdown = $null
        $CIPPStatus = $null
        $ResultData = $Result
        if ($Result -is [hashtable] -and $Result.ContainsKey('CIPPStatus')) {
            $CIPPStatus = $Result['CIPPStatus']
            $ResultData = if ($Result.ContainsKey('CIPPResults')) { $Result['CIPPResults'] } else { $null }
            $CIPPResultMarkdown = if ($Result.ContainsKey('CIPPResultMarkdown')) { $Result['CIPPResultMarkdown'] } else { $null }
        } elseif ($Result -is [PSCustomObject] -and $Result.PSObject.Properties['CIPPStatus']) {
            $CIPPStatus = $Result.CIPPStatus
            $ResultData = if ($Result.PSObject.Properties['CIPPResults']) { $Result.CIPPResults } else { $null }
            $CIPPResultMarkdown = if ($Result.PSObject.Properties['CIPPResultMarkdown']) { $Result.CIPPResultMarkdown } else { $null }
        }

        $Body = @{
            Results            = $ResultData
            ScriptGuid         = $ScriptGuid
            Tenant             = $TenantFilter
            CIPPStatus         = $CIPPStatus
            CIPPResultMarkdown = $CIPPResultMarkdown
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
