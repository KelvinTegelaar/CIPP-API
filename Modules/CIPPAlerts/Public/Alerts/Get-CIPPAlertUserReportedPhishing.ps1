function Get-CIPPAlertUserReportedPhishing {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        [int]$HoursBack = if ($InputValue.HoursBack) { [int]$InputValue.HoursBack } else { 24 }
        $Since = (Get-Date).AddHours(-$HoursBack).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        $Submissions = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/security/threatSubmission/emailThreats?`$filter=createdDateTime ge $Since" -tenantid $TenantFilter -AsApp $true

        $AlertData = foreach ($Submission in $Submissions) {
            # Only include user-reported submissions
            if ($Submission.source -ne 'user') { continue }

            [PSCustomObject]@{
                ReportedBy       = $Submission.createdBy.user.displayName
                ReporterEmail    = $Submission.createdBy.user.email
                Sender           = $Submission.sender
                Subject          = $Submission.emailSubject
                Category         = $Submission.category
                ReceivedDateTime = $Submission.receivedDateTime
                ReportedAt       = $Submission.createdDateTime
                Status           = $Submission.status
                ResultCategory   = $Submission.result.category
                ResultDetail     = $Submission.result.detail
                InternetMsgId    = $Submission.internetMessageId
                SubmissionId     = $Submission.id
                Tenant           = $TenantFilter
            }
        }
        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "User-reported phishing alert failed for $($TenantFilter): $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
