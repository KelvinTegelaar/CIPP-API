using namespace System.Net

function Invoke-ListMessageTrace {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Body.tenantFilter

        if ($Request.Body.MessageId) {
            $SearchParams = @{ 'MessageId' = $Request.Body.messageId }
        } else {
            $SearchParams = @{}
            if ($Request.Body.days) {
                $Days = $Request.Body.days
                $SearchParams.StartDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('s')
                $SearchParams.EndDate = (Get-Date).ToUniversalTime().ToString('s')
            } else {
                if ($Request.Body.startDate) {
                    if ($Request.Body.startDate -match '^\d+$') {
                        $SearchParams.StartDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Request.Body.startDate).UtcDateTime.ToString('s')
                    } else {
                        $SearchParams.StartDate = [DateTime]::ParseExact($Request.Body.startDate, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToUniversalTime().ToString('s')
                    }
                }
                if ($Request.Body.endDate) {
                    if ($Request.Body.endDate -match '^\d+$') {
                        $SearchParams.EndDate = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Request.Body.endDate).UtcDateTime.ToString('s')
                    } else {
                        $SearchParams.EndDate = [DateTime]::ParseExact($Request.Body.endDate, 'yyyy-MM-ddTHH:mm:ssZ', $null).ToUniversalTime().ToString('s')
                    }
                }
            }

            if ($Request.Body.status) {
                $SearchParams.Add('Status', $Request.Body.status.value)
            }
            if (![string]::IsNullOrEmpty($Request.Body.fromIP)) {
                $SearchParams.Add('FromIP', $Request.Body.fromIP)
            }
            if (![string]::IsNullOrEmpty($Request.Body.toIP)) {
                $SearchParams.Add('ToIP', $Request.Body.toIP)
            }
        }

        if ($Request.Body.recipient) {
            $SearchParams.Add('RecipientAddress', $($Request.Body.recipient.value ?? $Request.Body.recipient))
        }
        if ($Request.Body.sender) {
            $SearchParams.Add('SenderAddress', $($Request.Body.sender.value ?? $Request.Body.sender))
        }

        $Trace = if ($Request.Body.traceDetail) {
            $CmdParams = @{
                MessageTraceId   = $Request.Body.ID
                RecipientAddress = $Request.Body.recipient
            }
            New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTraceDetail' -CmdParams $CmdParams | Select-Object @{ Name = 'Date'; Expression = { $_.Date.ToString('u') } }, Event, Action, Detail
        } else {
            Write-Information ($SearchParams | ConvertTo-Json)

            New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MessageTrace' -CmdParams $SearchParams | Select-Object MessageTraceId, Status, Subject, RecipientAddress, SenderAddress, @{ Name = 'Received'; Expression = { $_.Received.ToString('u') } }, FromIP, ToIP
            Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message 'Executed message trace' -Sev 'Info'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed executing message trace. Error: $ErrorMessage" -Sev 'Error'
        $Trace = @{Status = "Failed to retrieve message trace: $ErrorMessage" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @($Trace)
    }
}
