function Invoke-ListHistoricalSearches {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists Exchange Online historical searches (async message trace/report jobs) submitted in the last 10 days.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Query.tenantFilter
        $CmdParams = @{}
        if (![string]::IsNullOrEmpty($Request.Query.jobId)) {
            $CmdParams.JobId = $Request.Query.jobId
        }

        # FileUrl is the legacy admin.protection.outlook.com download endpoint. It is not GDAP-aware
        # (401s for delegated partners by every path, including the modern EAC), so the CSV is only
        # retrievable by a customer-native admin login, or delivered to a customer NotifyAddress.
        $Searches = New-ExoRequest -TenantId $TenantFilter -Cmdlet 'Get-HistoricalSearch' -CmdParams $CmdParams |
            Sort-Object -Property SubmitDate -Descending |
            Select-Object JobId, ReportTitle, ReportType, Status, JobProgress, Rows, FileRows, ErrorDescription, FileUrl,
            @{ Name = 'SubmitDate'; Expression = { $_.SubmitDate ? ([DateTime]$_.SubmitDate).ToString('u') : $null } },
            @{ Name = 'CompletionDate'; Expression = { $_.CompletionDate ? ([DateTime]$_.CompletionDate).ToString('u') : $null } },
            @{ Name = 'StartDate'; Expression = { $_.StartDate ? ([DateTime]$_.StartDate).ToString('u') : $null } },
            @{ Name = 'EndDate'; Expression = { $_.EndDate ? ([DateTime]$_.EndDate).ToString('u') : $null } },
            @{ Name = 'SenderAddress'; Expression = { @($_.SenderAddress) -join ', ' } },
            @{ Name = 'RecipientAddress'; Expression = { @($_.RecipientAddress) -join ', ' } }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Searches)
    } catch {
        $ErrorMessage = Get-NormalizedError -message $_.Exception.Message
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Failed to list historical searches. Error: $ErrorMessage" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Failed to list historical searches: $ErrorMessage") }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
