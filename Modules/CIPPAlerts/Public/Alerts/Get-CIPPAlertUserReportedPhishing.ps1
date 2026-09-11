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
        if ($ErrorMessage.NormalizedError -match 'dataservice\.protection\.outlook\.com' -or $ErrorMessage.NormalizedError -match 'No HTTP resource was found') {
            $Message = "User-reported phishing alert skipped for $($TenantFilter): Exchange Online API unavailable in this tenant's region. Check tenant and EXO health."
        } else {
            $Message = "User-reported phishing alert failed for $($TenantFilter): $($ErrorMessage.NormalizedError)"
        }
        Write-AlertMessage -message $Message -tenant $TenantFilter -LogData $ErrorMessage
    }
}
