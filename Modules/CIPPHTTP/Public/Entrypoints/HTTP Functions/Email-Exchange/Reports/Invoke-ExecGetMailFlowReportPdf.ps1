function Invoke-ExecGetMailFlowReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Server-renders the Exchange mail flow report as application/pdf bytes. Reads the same three Exchange
        reports the Mail Flow page uses (Get-MailFlowStatusReport plus the TopMailSender and
        TopSpamRecipient traffic summaries), aggregates the daily disposition rows the way the page does,
        and composes them through the shared CIPPSharp kit (Build-CippMailFlowReportTree) - the server-side
        replacement for the client react-pdf MailFlowReportButton.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }
        # Reporting window in days (1-90).
        $Days = [Math]::Min([Math]::Max([int]($Request.Query.days ?? 14), 1), 90)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter

        $Window = @{
            StartDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('s')
            EndDate   = (Get-Date).ToUniversalTime().ToString('s')
        }
        $FlowRows = @(New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MailFlowStatusReport' -CmdParams $Window)
        # For the Top* traffic summary categories C1 is the address and C2 the message count.
        function Get-TopList($Category) {
            @(New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MailTrafficSummaryReport' -CmdParams ($Window + @{ Category = $Category }) |
                    ForEach-Object { @{ name = $_.C1; count = $_.C2 } })
        }

        # Message counts summed per event type, per direction and per day (the page's useMemo aggregation).
        $Totals = @{}
        foreach ($g in ($FlowRows | Group-Object EventType)) { $Totals[$g.Name] = ($g.Group | Measure-Object -Property MessageCount -Sum).Sum }
        $DirectionTotals = @{}
        foreach ($g in ($FlowRows | Group-Object Direction)) { $DirectionTotals[$g.Name] = ($g.Group | Measure-Object -Property MessageCount -Sum).Sum }
        $Daily = @($FlowRows | Group-Object { ([datetime]$_.Date).ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
                $Day = @{ date = $_.Name }
                foreach ($t in ($_.Group | Group-Object EventType)) { $Day[$t.Name] = ($t.Group | Measure-Object -Property MessageCount -Sum).Sum }
                $Day
            })

        $Report = Build-CippMailFlowReportTree -Data @{
            TenantName        = $TenantName
            days              = $Days
            totals            = $Totals
            directionTotals   = $DirectionTotals
            daily             = $Daily
            topSenders        = Get-TopList 'TopMailSender'
            topSpamRecipients = Get-TopList 'TopSpamRecipient'
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Mail Flow Report'
        $FileName = ("Mail_Flow_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Mail Flow report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
