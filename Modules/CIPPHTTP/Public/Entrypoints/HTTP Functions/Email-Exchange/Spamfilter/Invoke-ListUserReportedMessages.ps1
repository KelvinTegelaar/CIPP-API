function Invoke-ListUserReportedMessages {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists user reported email threat submissions (Defender Submissions with source 'user') for a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $GraphRequest = @()
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'User reported messages are loaded per tenant. Select a tenant to view its reported messages.'
            }
        } else {
            $Submissions = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/threatSubmission/emailThreats' -tenantid $TenantFilter -AsApp $true
            $Results = [System.Collections.Generic.List[object]]::new()
            foreach ($Submission in $Submissions) {
                # Admin submissions share the same Graph collection; this page only covers user reports
                if ($Submission.source -ne 'user') { continue }
                $Results.Add([PSCustomObject]@{
                        ReportedDateTime  = $Submission.createdDateTime
                        ReceivedDateTime  = $Submission.receivedDateTime
                        Subject           = $Submission.subject ?? $Submission.emailSubject
                        Sender            = $Submission.sender
                        SenderIP          = $Submission.senderIP
                        RecipientEmail    = $Submission.recipientEmailAddress
                        ReportedBy        = $Submission.createdBy.user.displayName
                        ReporterEmail     = $Submission.createdBy.user.email
                        Category          = $Submission.category
                        OriginalCategory  = $Submission.originalCategory
                        Status            = $Submission.status
                        ResultCategory    = $Submission.result.category
                        ResultDetail      = $Submission.result.detail
                        AdminReviewResult = $Submission.adminReview.reviewResult
                        InternetMessageId = $Submission.internetMessageId
                        Id                = $Submission.id
                        Tenant            = $TenantFilter
                    })
            }
            $GraphRequest = $Results | Sort-Object -Property ReportedDateTime -Descending
        }
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest)
            Metadata = $Metadata
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
