function Invoke-ExecGetBecReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Server-renders a stored Business Email Compromise (BEC) run as application/pdf bytes. Reads the
        run through Get-CIPPBecReport (the BecReports metadata row plus its BecResults payload) and
        composes it through the shared CIPPSharp component kit (Build-CippBecReportTree) - the server-side
        replacement for the client react-pdf BECRemediationReportButton. A run is named by its caseId;
        pass userId instead to render the user's newest completed run. The run must have completed - the
        report reads its stored result, it does not trigger a new investigation.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        # The stored run to render. A caseId names it directly; a userId picks the user's newest completed run.
        $CaseId = $Request.Query.caseId ?? $Request.Body.caseId
        $UserId = $Request.Query.userId ?? $Request.Body.userId
        # 'full' (default) = every page; 'summary' = the executive lead only, for a C-suite reader
        $Variant = switch ([string]($Request.Query.variant ?? $Request.Body.variant)) {
            'summary' { 'summary' }
            default { 'full' }
        }
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or ([string]::IsNullOrWhiteSpace($CaseId) -and [string]::IsNullOrWhiteSpace($UserId))) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter and either a caseId or a userId are required' })
        }

        # Without a caseId, fall back to the user's most recent completed run (the list is newest-first).
        if ([string]::IsNullOrWhiteSpace($CaseId)) {
            $Runs = @(Get-CIPPBecReport -TenantFilter $TenantFilter -UserId $UserId)
            $CaseId = ($Runs | Where-Object { $_.Status -eq 'Completed' } | Select-Object -First 1).CaseId
            if ([string]::IsNullOrWhiteSpace($CaseId)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = 'No completed BEC analysis is stored for this user. Run the BEC check first, then generate the report.'
                    })
            }
        }

        $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
        if (-not $Run -or $Run.Status -ne 'Completed' -or -not $Run.Results) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = "No completed BEC analysis is stored for case '$CaseId'. Run the BEC check first, then generate the report."
                })
        }

        # The results payload is what the check pages render. The containment history and the run's own
        # identifiers live on the metadata row, and the client renderer reads them off becData.Run - so
        # attach the same .Run block here, and the builder reads it exactly as the client does.
        $BecData = $Run.Results
        $RunBlock = [pscustomobject]@{
            CaseId      = $Run.CaseId
            Status      = $Run.Status
            ExtractedAt = $Run.ExtractedAt
            RequestedAt = $Run.RequestedAt
            RequestedBy = $Run.RequestedBy
            Containment = $Run.Containment
        }
        $BecData | Add-Member -NotePropertyName 'Run' -NotePropertyValue $RunBlock -Force

        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        # The investigated user labels the cover and footer; the run stored who it was for.
        $DisplayName = @($Run.DisplayName, $Run.UserPrincipalName, $Request.Query.userDisplayName, $Request.Body.userDisplayName, $Run.UserId) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        $UserName = @($Run.UserPrincipalName, $Request.Query.userName, $Request.Body.userName) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        $UserData = [pscustomobject]@{ displayName = $DisplayName; userPrincipalName = $UserName; id = $Run.UserId }

        $Report = Build-CippBecReportTree -UserData $UserData -BecData $BecData -TenantName $TenantName -Variant $Variant

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'BEC Analysis Report'
        $FileName = ("BEC_$(if ($Variant -eq 'summary') { 'Summary' } else { 'Report' })_$DisplayName" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render BEC report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
