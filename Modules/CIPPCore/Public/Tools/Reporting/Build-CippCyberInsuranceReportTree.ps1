function Build-CippCyberInsuranceReportTree {
    <#
    .SYNOPSIS
        Compose the Cyber Insurance Readiness report as a component tree.
    .DESCRIPTION
        Pure composition from the data Get-CIPPCyberInsuranceReport returns. Returns @{ Blocks; Variables }
        for ConvertTo-CippReportPdf.
    .PARAMETER Data
        TenantName, summary and questions[].
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $TenantName = [string]$Data.TenantName
    $Summary = $Data.summary
    $DataDate = if ($Summary.lastDataRefresh) { ([datetime]$Summary.lastDataRefresh).ToUniversalTime().ToString('d MMMM yyyy HH:mm') + ' UTC' } else { 'not available' }
    $Source = @{ Verified = 'Verified by CIPP'; Partial = 'Verified by CIPP (Microsoft 365 only)'; Attestation = 'Attested by MSP' }

    $Blocks = [System.Collections.Generic.List[object]]::new()
    $Blocks.Add((New-CippReportPage -Title 'Summary' -Subtitle 'The application questions at a glance'))
    $Blocks.Add((New-CippReportParagraph -Html ('<p>This report answers the cyber insurance application questions for <b>{0}</b> using settings read from its Microsoft 365 tenant. Answers marked as verified were read from the tenant. Answers marked as attested cannot be seen in Microsoft 365 and are provided by the managed service provider.</p>' -f [System.Net.WebUtility]::HtmlEncode($TenantName))))
    $Blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = $Summary.yes; label = 'Verified: Yes' }
                @{ value = $Summary.no; label = 'Verified: No' }
                @{ value = $Summary.partial; label = 'Partial' }
                @{ value = $Summary.attestation; label = 'Attested by MSP' }
            )))
    $Blocks.Add((New-CippReportInfoBox -Title 'When the data was collected' -Content "Tenant data was last collected on $DataDate. Where sources were collected at different times, this is the oldest of them."))
    $Blocks.Add((New-CippReportTable -Limit 100 -Columns @(@{ header = '#'; key = 'id'; width = 0.4 }, @{ header = 'Question'; key = 'question'; width = 3 }, @{ header = 'Source'; key = 'source'; width = 1.8 }, @{ header = 'Answer'; key = 'answer'; width = 1.2 }) -Rows @(
                foreach ($Question in $Data.questions) { @{ id = "$($Question.number)"; question = $Question.question; source = $Source[$Question.coverage]; answer = $Question.answer } }
            )))

    $Blocks.Add((New-CippReportPage -Title 'Verified by CIPP' -Subtitle 'Answers read from the Microsoft 365 tenant'))
    foreach ($Question in $Data.questions) {
        if ($Question.coverage -eq 'Attestation') { continue }
        $Blocks.Add([PSCustomObject]@{ type = 'test'; static = $false; title = "$($Question.number). $($Question.question)"; status = $Question.answer; content = $Question.detail })
        if ($Question.attestation) {
            $Blocks.Add([PSCustomObject]@{ type = 'blank'; title = 'Customer attestation'; content = $Question.attestation + ('<p><em>Entered by {0} on {1}</em></p>' -f [System.Net.WebUtility]::HtmlEncode($Question.attestedBy), ([datetime]$Question.attestedDate).ToUniversalTime().ToString('d MMMM yyyy')) })
        }
    }

    $Blocks.Add((New-CippReportPage -Title 'Attested by MSP' -Subtitle 'Questions Microsoft 365 cannot answer'))
    $Blocks.Add((New-CippReportParagraph -Text 'The questions below cover systems and processes that are not visible in Microsoft 365. The managed service provider attests to them. Where the tenant holds supporting evidence it is shown, but it does not answer the question.'))
    foreach ($Question in $Data.questions) {
        if ($Question.coverage -ne 'Attestation') { continue }
        $Blocks.Add([PSCustomObject]@{ type = 'test'; static = $false; title = "$($Question.number). $($Question.question)"; status = $Question.answer; content = $Question.detail })
        if ($Question.attestation) {
            $Blocks.Add([PSCustomObject]@{ type = 'blank'; title = 'Customer attestation'; content = $Question.attestation + ('<p><em>Entered by {0} on {1}</em></p>' -f [System.Net.WebUtility]::HtmlEncode($Question.attestedBy), ([datetime]$Question.attestedDate).ToUniversalTime().ToString('d MMMM yyyy')) })
        } else {
            $Blocks.Add((New-CippReportParagraph -Title 'Customer attestation' -Text 'No attestation has been entered for this question.'))
        }
    }

    $Blocks.Add((New-CippReportPage -Title 'Scope and Limitations' -Subtitle 'What this report does and does not show'))
    $Blocks.Add((New-CippReportBullets -Items @(
                @{ label = 'Microsoft 365 only.'; text = 'The report reads Microsoft 365, Entra ID, Intune and Defender. It cannot see on-premises networks and firewalls, non-Microsoft endpoint protection, non-Microsoft SaaS, backup platforms, SIEM tools or business processes.' }
                @{ label = 'A point-in-time snapshot.'; text = "Answers reflect the tenant as it was when the data was collected ($DataDate), not as it is when the report is read." }
                @{ label = 'Managed devices only.'; text = 'Device figures cover devices managed by Intune. Each percentage shows the number it is measured against.' }
                @{ label = 'Not a replacement for the application.'; text = 'This report supports the signed application and does not replace it. The applicant remains responsible for the answers given on the application.' }
                @{ label = 'Check for differences.'; text = 'Any answer here that differs from the answer on the application should be raised with the broker before submission.' }
            )))

    @{
        Blocks    = @($Blocks)
        Variables = @{
            coverlabel         = 'Cyber Insurance Readiness'
            coversubtitle      = "Evidence for the cyber insurance application of $TenantName, read from its Microsoft 365 tenant."
            covermeta          = "Data collected $DataDate"
            coverfooternote    = "Confidential $([char]0x2014) For the applicant, broker and underwriter"
            coverfallbackimage = '/reportImages/glasses.jpg'
            footerlabel        = "$TenantName $([char]0x2014) Cyber Insurance Readiness $([char]0x2014) Data collected $DataDate"
        }
    }
}
