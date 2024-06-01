using namespace System.Net

Function Invoke-ListMessageTrace {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    try {
        $TenantFilter = $request.query.TenantFilter
        $SearchParams = @{
            StartDate = (Get-Date).AddDays( - $($request.query.days)).ToString('s')
            EndDate   = (Get-Date).ToString('s')
        }

        if ($null -ne $request.query.recipient) { $Searchparams.Add('RecipientAddress', $($request.query.recipient)) }
        if ($null -ne $request.query.sender) { $Searchparams.Add('SenderAddress', $($request.query.sender)) }
        $type = $request.query.Tracedetail
        $trace = if ($Request.Query.Tracedetail) {
            New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-MessageTraceDetail' -cmdParams $Searchparams
            Get-MessageTraceDetail -MessageTraceId $Request.Query.ID -RecipientAddress $request.query.recipient -erroraction stop | Select-Object Event, Action, Detail, @{ Name = 'Date'; Expression = { $_.Date.Tostring('s') } }
        } else {
            New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-MessageTrace' -cmdParams $Searchparams | Select-Object MessageTraceId, Status, Subject, RecipientAddress, SenderAddress, @{ Name = 'Date'; Expression = { $_.Received.tostring('s') } }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message 'Executed message trace' -Sev 'Info'

        }
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed executing messagetrace. Error: $($_.Exception.Message)" -Sev 'Error'
        $trace = @{Status = "Failed to retrieve message trace $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($trace)
        })

}
