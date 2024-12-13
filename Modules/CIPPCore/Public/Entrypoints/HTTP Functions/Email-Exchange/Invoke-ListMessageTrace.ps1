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
        $TenantFilter = $Request.Body.tenantFilter

        if ($Request.Body.MessageId) {
            $SearchParams = @{ 'MessageId' = $Request.Body.messageId }
        } else {
            $Days = $Request.Body.days
            $SearchParams = @{
                StartDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('s')
                EndDate   = (Get-Date).ToUniversalTime().ToString('s')
            }
        }

        if (![string]::IsNullOrEmpty($Request.Body.recipient)) {
            $Searchparams.Add('RecipientAddress', $($Request.Body.recipient))
        }
        if (![string]::IsNullOrEmpty($Request.Body.sender)) {
            $Searchparams.Add('SenderAddress', $($Request.Body.sender))
        }

        $trace = if ($Request.Body.traceDetail) {
            $CmdParams = @{
                MessageTraceId   = $Request.Body.ID
                RecipientAddress = $Request.Body.recipient
            }
            New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTraceDetail' -CmdParams $CmdParams | Select-Object @{ Name = 'Date'; Expression = { $_.Date.ToString('u') } }, Event, Action, Detail
        } else {
            New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTrace' -CmdParams $SearchParams | Select-Object MessageTraceId, Status, Subject, RecipientAddress, SenderAddress, @{ Name = 'Received'; Expression = { $_.Received.ToString('u') } }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($TenantFilter) -message 'Executed message trace' -Sev 'Info'

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
