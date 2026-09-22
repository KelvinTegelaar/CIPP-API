function Invoke-ListMailFlowReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Returns Exchange Online mail flow reports: disposition counts by day (Get-MailFlowStatusReport)
        and top sender/recipient summaries (Get-MailTrafficSummaryReport). Both support up to 90 days.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Query.tenantFilter
        $ReportType = $Request.Query.reportType ?? 'MailFlowStatus'
        $Days = [Math]::Min([Math]::Max([int]($Request.Query.days ?? 14), 1), 90)
        $StartDate = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('s')
        $EndDate = (Get-Date).ToUniversalTime().ToString('s')

        $Report = switch ($ReportType) {
            'MailFlowStatus' {
                $CmdParams = @{ StartDate = $StartDate; EndDate = $EndDate }
                New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MailFlowStatusReport' -CmdParams $CmdParams |
                    Select-Object @{ Name = 'Date'; Expression = { ([DateTime]$_.Date).ToString('yyyy-MM-dd') } }, Direction, EventType, @{ Name = 'Count'; Expression = { $_.MessageCount } }
            }
            'TrafficSummary' {
                $Category = $Request.Query.category ?? 'TopMailSender'
                $CmdParams = @{ Category = $Category; StartDate = $StartDate; EndDate = $EndDate }
                # C1/C2/C3 are generic columns whose meaning depends on the category; for the Top* categories
                # C1 is the address/name and C2 the message count.
                New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-MailTrafficSummaryReport' -CmdParams $CmdParams |
                    Select-Object @{ Name = 'Name'; Expression = { $_.C1 } }, @{ Name = 'Count'; Expression = { $_.C2 } }, @{ Name = 'Extra'; Expression = { $_.C3 } }
            }
            default {
                throw "Unknown report type '$ReportType'. Supported: MailFlowStatus, TrafficSummary."
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results  = @($Report)
            Metadata = @{
                ReportType = $ReportType
                StartDate  = $StartDate
                EndDate    = $EndDate
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed to retrieve mail flow report. Error: $ErrorMessage" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{
            Results  = @()
            Metadata = @{ Error = "Failed to retrieve mail flow report: $ErrorMessage" }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
