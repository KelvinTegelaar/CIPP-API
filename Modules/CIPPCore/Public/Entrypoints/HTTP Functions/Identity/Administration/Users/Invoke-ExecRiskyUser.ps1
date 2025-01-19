function Invoke-ExecRiskyUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $TenantFilter = $Request.Query.tenantfilter
    $SuspectUser = $Request.Query.userid
    $userDisplayName = $Request.Query.userDisplayName
    $userAction = $Request.Query.userAction

    if ($userAction -eq "dismiss") {
        $uri = 'https://graph.microsoft.com/beta/riskyUsers/dismiss'
        $idParam = 'userIds'
    }
    elseif ($userAction -eq "confirmCompromised") {
        $uri = 'https://graph.microsoft.com/beta/riskyUsers/confirmCompromised'
        $idParam = 'userIds'
    }
    elseif ($userAction -eq "confirmSafe") {
        $uri = 'https://graph.microsoft.com/beta/auditLogs/signIns/confirmSafe'
        $idParam = 'requestIds'
    }
    else {
        $ResponseBody = [pscustomobject]@{ 'Results' = "Invalid action specified. Please specify either 'dismiss', 'confirmCompromised' or 'confirmSafe'." }
        Write-LogMessage -API 'DismissRiskyUser' -tenant $TenantFilter -message "Invalid action specified for user $userDisplayName" -sev 'Error'

        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = $ResponseBody
        })
        return
    }

    $GraphRequest = @{
        'uri'           = $uri
        'tenantid'      = $TenantFilter
        'type'          = 'POST'
        'contentType'   = 'application/json; charset=utf-8'
        'body'          = @{
            $idParam = @($SuspectUser)
        } | ConvertTo-Json
    }

    try {
        $GraphResults = New-GraphPostRequest @GraphRequest
        Write-LogMessage -API 'DismissRiskyUser' -tenant $TenantFilter -message "$userAction action executed for $userDisplayName" -sev 'Info'

        $ResponseBody = [pscustomobject]@{ 'Results' = "Successfully executed $userAction action for user $userDisplayName." }
    } catch {
        $ResponseBody = [pscustomobject]@{ 'Results' = "Failed to execute $userAction action. $($_.Exception.Message)" }
        Write-LogMessage -API 'DismissRiskyUser' -tenant $TenantFilter -message "Failed to execute $userAction action for $userDisplayName" -sev 'Error' -LogData $_
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $ResponseBody
    })
}
