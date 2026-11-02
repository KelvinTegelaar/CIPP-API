function Build-CippShadowAIReportTree {
    <#
    .SYNOPSIS
        Compose the Shadow AI report as a component tree (server port of ShadowAIReportButton's
        ShadowAIReportPages).
    .PARAMETER Data
        Shadow AI data: summary, detectedApps[], consentedApps[], topTools[], byRisk[]. Returns
        @{ Blocks; Variables }.
    .PARAMETER SectionConfig
        Which sections to include, keyed executiveSummary/infographics/background/riskLevels/
        sanctionedTools/detectedSoftware/entraApplications/recommendations. Empty (the default) includes
        every section; a populated map includes only the keys set to $true (mirrors the client's section
        toggles).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data, [hashtable]$SectionConfig = @{})

    $summary = if ($Data.summary) { $Data.summary } else { @{} }
    # `?? @()` so a missing list is empty rather than @($null), which would render as one blank row.
    $detected = @($Data.detectedApps ?? @())
    $consented = @($Data.consentedApps ?? @())
    $topTools = @($Data.topTools ?? @())
    $byRisk = @($Data.byRisk ?? @())
    $riskColours = @{ high = '#EF4444'; medium = '#F59E0B'; low = '#3B82F6'; informational = '#10B981' }
    function RiskColour($r) { $k = "$r".ToLower(); if ($riskColours.ContainsKey($k)) { $riskColours[$k] } else { '#A0AEC0' } }
    function nz($v) { if ($null -eq $v) { 0 } else { $v } }
    # No config supplied -> full report; a supplied config includes only the keys explicitly set true.
    $cfg = $SectionConfig
    $allOn = ($null -eq $cfg -or $cfg.Count -eq 0)
    function on($k) { if ($allOn) { $true } else { [bool]$cfg[$k] } }

    $riskAreas = @(
        @{ title = 'Data Leakage'; colour = '#EF4444'; text = 'Customer records, credentials, source code and financials pasted into consumer AI tools may be retained by the provider and used to train future models, permanently placing them outside your control. Every prompt is a data transfer to a third party.' }
        @{ title = 'Compliance & Legal Exposure'; colour = '#F59E0B'; text = 'Processing personal data through unvetted AI services can breach GDPR, HIPAA and industry-specific regulations, and undermines contractual confidentiality commitments made to customers.' }
        @{ title = 'Excessive Application Permissions'; colour = '#D69E2E'; text = 'AI meeting assistants and productivity plugins often request broad access to mailboxes, calendars and files. A single user consent can expose organization-wide data to a third-party service, and that access persists until the consent is revoked.' }
        @{ title = 'Unreliable Output in Business Processes'; colour = '#3B82F6'; text = 'AI-generated content flows into quotes, contracts and customer communication without review. Errors produced by unmanaged tools are difficult to trace because the organization does not know the tools are in use.' }
    )
    $riskLevels = @(
        @{ name = 'High'; text = 'Consumer tools that train on submitted data, retain prompts indefinitely, or operate from jurisdictions without adequate data protection. Content pasted into these tools should be treated as disclosed to an unvetted third party.' }
        @{ name = 'Medium'; text = 'Tools with business-grade privacy options that are typically used through personal, unmanaged accounts. Risk depends heavily on the plan and account type in use.' }
        @{ name = 'Low'; text = 'Tools with enterprise controls, contractual data-processing terms and no training on customer data when configured correctly.' }
        @{ name = 'Informational'; text = 'Company sanctioned tools that have been explicitly approved for use in this tenant. They remain in the report for visibility but no longer contribute to the risk figures.' }
    )

    # Distinct sanctioned tools across both sources: device installs come from the Intune inventory
    # rows, 7-day users from the Entra consent rows, summed per tool.
    $sanctionedList = @($detected + $consented | Where-Object { $_.status -eq 'Sanctioned' } | Group-Object { $_.aiTool } | ForEach-Object {
            @{
                tool     = $_.Name
                vendor   = $_.Group[0].vendor
                category = $_.Group[0].category
                devices  = ($_.Group | ForEach-Object { nz $_.deviceCount } | Measure-Object -Sum).Sum
                users    = ($_.Group | ForEach-Object { nz $_.activeUsersLast7Days } | Measure-Object -Sum).Sum
            }
        } | Select-Object -First 18)
    $detectedRows = @($detected | Select-Object -First 18)
    $consentedRows = @($consented | Select-Object -First 18)

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- AI Summary --
    if (on 'executiveSummary') {
        $blocks.Add((New-CippReportPage -Title 'AI Summary' -Subtitle 'Strategic overview of AI usage in your Microsoft 365 environment'))
        $blocks.Add((New-CippReportParagraph -Html ('<p>This report identifies the artificial intelligence tools discovered in the <b>{0}</b> environment, combining software inventory from managed devices (Intune) with cloud application consent data from Entra ID. Each tool is matched against a curated catalog of known AI services and assigned a risk level based on its data handling practices.</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName))))
        $blocks.Add((New-CippReportParagraph -Html '<p>Tools that have been explicitly approved are marked as company sanctioned and report the Informational risk level. Everything else represents shadow AI: tools adopted by employees without review or approval, whose handling of company data is unknown.</p>'))
        $blocks.Add((New-CippReportStatRow -Title 'AI Usage Overview' -Stats @(
                    @{ value = (nz $summary.aiToolsDetected); label = 'AI Tools' }
                    @{ value = (nz $summary.deviceInstalls); label = 'Device Installs' }
                    @{ value = (nz $summary.consentedAiApps); label = 'Entra AI Apps' }
                    @{ value = (nz $summary.highRiskTools); label = 'High Risk'; colour = (RiskColour 'high') }
                    @{ value = (nz $summary.sanctionedTools); label = 'Sanctioned'; colour = (RiskColour 'informational') }
                )))
        if ($topTools.Count -gt 0) {
            $blocks.Add((New-CippReportTable -Title 'Most Used AI Tools' -Limit $topTools.Count -Columns @(
                        @{ header = 'Tool'; key = 'tool'; width = 3; bold = $true }, @{ header = 'Category'; key = 'category'; width = 3 }
                        @{ header = 'Status'; key = 'status'; width = 2 }, @{ header = 'Devices'; key = 'devices'; width = 1.5 }, @{ header = 'Users (7d)'; key = 'users'; width = 1.5 }
                    ) -Rows @($topTools | ForEach-Object { @{ tool = $_.tool; category = $_.category; status = ($_.status ?? 'Unsanctioned'); devices = "$($_.devices)"; users = "$($_.users)" } })))
        }
    }

    if (on 'infographics') { $blocks.Add((New-CippReportHero -Image '/reportImages/laptop.jpg' -Highlight '75%' -SubText "of knowledge workers already`nuse generative AI at work -`nmost without their employer knowing" -FooterText "Visibility is the first step`nto control")) }

    # -- Understanding Shadow AI --
    if (on 'background') {
        $blocks.Add((New-CippReportPage -Title 'Understanding Shadow AI' -Subtitle 'What unmanaged AI usage means for your organization'))
        $blocks.Add((New-CippReportParagraph -Text 'Shadow AI is the use of artificial intelligence tools by employees without the knowledge or approval of the organization - the AI-era equivalent of shadow IT. Because most AI tools are free, browser-based and immediately useful, adoption happens quietly and quickly: an employee pastes a customer email into a chatbot to draft a reply, uploads a spreadsheet for analysis, or installs an AI notetaker that joins every meeting.'))
        $blocks.Add((New-CippReportParagraph -Text 'The goal of a shadow AI program is not zero AI usage, but zero unsanctioned usage. Every tool in this report should end up either approved and managed, or replaced and blocked. The four risk areas below explain why unmanaged usage deserves attention.'))
        $blocks.Add((New-CippReportHeading -Title 'Key Risk Areas'))
        foreach ($area in $riskAreas) { $blocks.Add((New-CippReportInfoBox -Title $area.title -Colour $area.colour -Content $area.text)) }
    }

    # -- Risk Levels & Distribution --
    if (on 'riskLevels') {
        $blocks.Add((New-CippReportPage -Title 'AI Tool Risk Levels' -Subtitle 'How risk is assigned and how it is distributed in this tenant'))
        $blocks.Add((New-CippReportParagraph -Text 'Detected tools are matched against a curated catalog of known AI services, each carrying a risk classification based on its data handling practices, account model and enterprise controls. Marking a tool as company sanctioned overrides its catalog risk with the Informational level, so the figures below reflect only unapproved use.'))
        $blocks.Add((New-CippReportChart -Kind donut -Title 'AI Tool Risk Distribution' -CentreLabel 'Tools' -Data @($byRisk | ForEach-Object { @{ label = $_.risk; value = $_.tools; colour = (RiskColour $_.risk) } })))
        $blocks.Add((New-CippReportInfoBoxColumns -Columns 2 -Items @($riskLevels | ForEach-Object { @{ title = $_.name; content = $_.text; colour = (RiskColour $_.name); tintTitle = $true } })))
    }

    # -- Sanctioned Tools --
    if ((on 'sanctionedTools') -and $sanctionedList.Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'Company Sanctioned AI Tools' -Subtitle 'AI tools that are approved for use in this organization'))
        $blocks.Add((New-CippReportParagraph -Text 'The tools listed below are permitted in this environment. They are allowed either because a business justification exists for their use, or because the system administrator has explicitly approved these tools for deployment. Sanctioned tools report the Informational risk level and are excluded from the shadow AI risk figures in this report; they remain listed for visibility into where AI is used across the organization.'))
        $blocks.Add((New-CippReportParagraph -Text "Approval is not permanent: sanctioned tools should be reviewed periodically to confirm that the plan in use, the vendor's data handling terms and the business justification still hold."))
        $blocks.Add((New-CippReportTable -Limit $sanctionedList.Count -Columns @(
                    @{ header = 'Tool'; key = 'tool'; width = 3; bold = $true }, @{ header = 'Vendor'; key = 'vendor'; width = 3 }, @{ header = 'Category'; key = 'category'; width = 3 }
                    @{ header = 'Devices'; key = 'devices'; width = 2 }, @{ header = 'Users (7d)'; key = 'users'; width = 2 }
                ) -Rows @($sanctionedList | ForEach-Object { @{ tool = $_.tool; vendor = $_.vendor; category = $_.category; devices = "$($_.devices)"; users = "$($_.users)" } })))
    }

    # -- Detected Software --
    if (on 'detectedSoftware') {
        $blocks.Add((New-CippReportPage -Title 'AI Software on Managed Devices' -Subtitle 'AI applications found in the Intune software inventory'))
        $detNote = if ($detected.Count -gt $detectedRows.Count) { ", showing the top $($detectedRows.Count) of $($detected.Count) entries" } else { '' }
        $blocks.Add((New-CippReportParagraph -Text "The following AI applications were detected in the software inventory of managed devices$detNote. Device counts indicate how widely each application has spread through the environment."))
        $blocks.Add((New-CippReportTable -Limit $detectedRows.Count -EmptyText 'No AI software was detected on managed devices during the last inventory sync.' -Columns @(
                    @{ header = 'Application'; key = 'application'; width = 4; bold = $true }, @{ header = 'AI Tool'; key = 'aiTool'; width = 3 }, @{ header = 'Category'; key = 'category'; width = 3 }
                    @{ header = 'Risk'; key = 'risk'; width = 2; colourField = 'riskColour' }, @{ header = 'Status'; key = 'status'; width = 2.5 }, @{ header = 'Devices'; key = 'deviceCount'; width = 1.5 }
                ) -Rows @($detectedRows | ForEach-Object { @{ application = $_.application; aiTool = $_.aiTool; category = $_.category; risk = $_.risk; riskColour = (RiskColour $_.risk); status = $_.status; deviceCount = "$($_.deviceCount)" } })))
    }

    # -- Entra Applications --
    if (on 'entraApplications') {
        $blocks.Add((New-CippReportPage -Title 'AI Applications in Entra ID' -Subtitle 'AI services with a footprint in your identity platform'))
        $conNote = if ($consented.Count -gt $consentedRows.Count) { ", showing the top $($consentedRows.Count) of $($consented.Count) entries" } else { '' }
        $blocks.Add((New-CippReportParagraph -Text "The following AI services are registered as applications in the tenant, including any permissions users have consented to$conNote. The consent date shows when each service first gained a foothold in the environment."))
        $blocks.Add((New-CippReportTable -Limit $consentedRows.Count -EmptyText 'No AI applications were found in Entra ID.' -Columns @(
                    @{ header = 'Application'; key = 'application'; width = 4; bold = $true }, @{ header = 'AI Tool'; key = 'aiTool'; width = 3 }
                    @{ header = 'Risk'; key = 'risk'; width = 2; colourField = 'riskColour' }, @{ header = 'Status'; key = 'status'; width = 2.5 }, @{ header = 'Users (7d)'; key = 'activeUsersLast7Days'; width = 2 }, @{ header = 'First Consented'; key = 'firstConsented'; width = 2.5 }
                ) -Rows @($consentedRows | ForEach-Object { @{ application = $_.application; aiTool = $_.aiTool; risk = $_.risk; riskColour = (RiskColour $_.risk); status = $_.status; activeUsersLast7Days = "$($_.activeUsersLast7Days)"; firstConsented = $(if ($_.firstConsentedDateTime) { ([datetime]$_.firstConsentedDateTime).ToString('M/d/yyyy') } else { 'Unknown' }) } })))
    }

    if (on 'infographics') { $blocks.Add((New-CippReportHero -Image '/reportImages/working.jpg' -Highlight '1 in 3' -SubText "employees shares sensitive work data`nwith AI tools without approval" -FooterText "Sanctioned alternatives keep`nyour data under contract")) }

    # -- Recommendations --
    if (on 'recommendations') {
        $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'A structured response to shadow AI in your environment'))
        $blocks.Add((New-CippReportParagraph -Text 'A structured response to shadow AI combines approval of useful tools with controls on the rest. The following actions are recommended based on the findings in this report:'))
        $blocks.Add((New-CippReportBullets -Title 'Action Plan' -Items @(
                    @{ label = 'Review & Decide:'; text = 'Evaluate each detected tool with stakeholders and decide whether it should be sanctioned, replaced with an approved alternative, or blocked.' }
                    @{ label = 'Sanction Approved Tools:'; text = 'Maintain a list of company sanctioned tools so future reports separate approved AI use from true shadow AI.' }
                    @{ label = 'Offer an Alternative:'; text = 'Provide a sanctioned option such as Microsoft 365 Copilot before blocking popular tools - blocking without an alternative drives usage to personal devices.' }
                    @{ label = 'Restrict Consent:'; text = 'Require admin approval for unverified applications in Entra ID so new AI services cannot access company data through user consent.' }
                    @{ label = 'Block & Monitor:'; text = 'Deploy Conditional Access and Defender for Cloud Apps policies to block or monitor unsanctioned AI web services.' }
                    @{ label = 'Extend DLP:'; text = 'Cover generative AI endpoints with data loss prevention policies to stop sensitive data from being pasted into chat prompts.' }
                    @{ label = 'Train Users:'; text = 'Publish an acceptable AI use policy and train users on what data may never be shared with AI tools.' }
                    @{ label = 'Review Monthly:'; text = 'Re-run this report on a regular cadence - new AI tools appear in tenants within days of release.' }
                )))
        $blocks.Add((New-CippReportInfoBox -Title 'Next Review' -Content 'The AI tool landscape changes quickly and new tools appear in tenants within days of release. We recommend re-running this assessment monthly and reviewing newly detected tools against your acceptable AI use policy.'))
    }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'AI Risk Assessment'
            coversubtitle      = 'Discovery and risk assessment of AI tools in use across managed devices and cloud applications.'
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "$($Data.TenantName) - Shadow AI Report"
        }
    }
}
