Function Invoke-ExecSetSecurityAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $AlertFilter = $Request.Query.GUID ?? $Request.Body.GUID
    $Status = $Request.Query.Status ?? $Request.Body.Status
    $AssignBody = ConvertTo-Json -Compress -InputObject @{ status = $Status }

    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/security/alerts_v2/$AlertFilter" -type PATCH -tenantid $TenantFilter -body $AssignBody
        $Result = "Set alert $AlertFilter to status $Status"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update alert $($AlertFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
