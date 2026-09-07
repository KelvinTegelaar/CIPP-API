function Invoke-ExecHistoricalSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Starts or cancels an Exchange Online historical search. Historical searches cover up to 90 days,
        deliver results as CSV (max 100,000 rows) and are limited to 250 submissions per day per tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.tenantFilter
        $Action = $Request.Body.Action ?? 'Start'

        if ($Action -eq 'Stop') {
            $JobId = $Request.Body.jobId
            if ([string]::IsNullOrEmpty($JobId)) {
                throw 'jobId is required to cancel a historical search.'
            }
            $null = New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Stop-HistoricalSearch' -CmdParams @{ JobId = $JobId }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Cancelled historical search $JobId" -Sev 'Info'
            $Result = "Cancelled historical search $JobId. Cancelled searches still count toward the daily quota."
        } else {
            $CmdParams = @{
                ReportTitle = $Request.Body.reportTitle
                ReportType  = $Request.Body.reportType.value ?? $Request.Body.reportType
            }
            if ([string]::IsNullOrEmpty($CmdParams.ReportTitle)) {
                throw 'A report title is required.'
            }
            if ([string]::IsNullOrEmpty($CmdParams.ReportType)) {
                throw 'A report type is required.'
            }

            foreach ($DateField in @('startDate', 'endDate')) {
                $Value = $Request.Body.$DateField
                if ([string]::IsNullOrEmpty($Value)) {
                    throw 'A start and end date are required.'
                }
                $Parsed = $Value -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int64]$Value).UtcDateTime : ([DateTime]$Value).ToUniversalTime()
                $CmdParams[($DateField.Substring(0, 1).ToUpper() + $DateField.Substring(1))] = $Parsed.ToString('s')
            }

            $Senders = @($Request.Body.senderAddress).value ?? @($Request.Body.senderAddress) | Where-Object { -not [string]::IsNullOrEmpty($_) }
            if ($Senders) {
                $CmdParams.SenderAddress = @($Senders)
            }
            $Recipients = @($Request.Body.recipientAddress).value ?? @($Request.Body.recipientAddress) | Where-Object { -not [string]::IsNullOrEmpty($_) }
            if ($Recipients) {
                $CmdParams.RecipientAddress = @($Recipients)
            }
            if (![string]::IsNullOrEmpty($Request.Body.messageId)) {
                $CmdParams.MessageID = @($Request.Body.messageId -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            if (!$CmdParams.SenderAddress -and !$CmdParams.RecipientAddress -and !$CmdParams.MessageID) {
                throw 'At least one sender address, recipient address or message ID filter is required.'
            }

            $Direction = $Request.Body.direction.value ?? $Request.Body.direction
            if (![string]::IsNullOrEmpty($Direction) -and $Direction -ne 'All') {
                $CmdParams.Direction = $Direction
            }
            $DeliveryStatus = $Request.Body.deliveryStatus.value ?? $Request.Body.deliveryStatus
            if (![string]::IsNullOrEmpty($DeliveryStatus)) {
                $CmdParams.DeliveryStatus = $DeliveryStatus
            }
            if (![string]::IsNullOrEmpty($Request.Body.originalClientIP)) {
                $CmdParams.OriginalClientIP = $Request.Body.originalClientIP
            }
            $NotifyAddresses = @($Request.Body.notifyAddress).value ?? @($Request.Body.notifyAddress) | Where-Object { -not [string]::IsNullOrEmpty($_) }
            if ($NotifyAddresses) {
                $CmdParams.NotifyAddress = @($NotifyAddresses)
            }

            $Job = New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Start-HistoricalSearch' -CmdParams $CmdParams
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Started historical search '$($CmdParams.ReportTitle)' ($($CmdParams.ReportType))" -Sev 'Info'
            $Result = "Started historical search '$($CmdParams.ReportTitle)'. Job ID: $($Job.JobId)"
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Result) }
    } catch {
        $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Historical search action failed. Error: $ErrorMessage" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Historical search action failed: $ErrorMessage") }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
