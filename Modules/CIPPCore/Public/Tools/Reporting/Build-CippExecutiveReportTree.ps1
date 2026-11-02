function Build-CippExecutiveReportTree {
    <#
    .SYNOPSIS
        Compose the Executive report as a component tree (server port of ExecutiveReportButton.jsx).
    .DESCRIPTION
        Pure composition: takes the already-gathered/shaped report data and returns @{ Blocks; Variables }
        - the component nodes for ConvertTo-CippReportPdf and the cover/footer report variables. Holds no
        data gathering, so it is unit-testable with sample data and drives the same layout the client
        ExecutiveReportDocument produces.
    .PARAMETER Data
        Hashtable of the report's data:
          TenantName, UserStats, SecureScore (currentScore/maxScore/percentageCurrent/percentageVsSimilar/
          percentageVsAllTenants/trend), Licenses[], Devices[], CAPolicies[] (raw state), SecurityControls[]
          (name/description/tags/status).
    .PARAMETER SectionConfig
        Which sections to include (executiveSummary/securityStandards/secureScore/licenseManagement/
        deviceManagement/conditionalAccess/infographics).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [hashtable]$SectionConfig = @{}
    )

    $cfg = @{
        executiveSummary = $true; securityStandards = $true; secureScore = $true
        licenseManagement = $true; deviceManagement = $true; conditionalAccess = $true; infographics = $true
    }
    foreach ($k in $SectionConfig.Keys) { $cfg[$k] = $SectionConfig[$k] }

    $tenant = $Data.TenantName
    $blocks = [System.Collections.Generic.List[object]]::new()
    # Chapter dividers over the bundled stock photos (the renderer resolves /reportImages/ paths).
    function Hero($image, $ov, $hi, $hl, $sub, $ft) {
        if ($cfg.infographics) {
            $blocks.Add((New-CippReportHero -Image "/reportImages/$image.jpg" -Overtitle $ov -Highlight $hi -Headline $hl -SubText $sub -FooterText $ft))
        }
    }

    # -- Executive Summary --
    if ($cfg.executiveSummary) {
        $blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'Strategic overview of your Microsoft 365 security posture'))
        $blocks.Add((New-CippReportParagraph -Html ("<p>This security assessment for <b>{0}</b> provides a clear picture of your organization's cybersecurity posture and readiness against modern threats. We've evaluated your current security measures against industry best practices to identify strengths and opportunities for improvement.</p>" -f [System.Net.WebUtility]::HtmlEncode([string]$tenant))))
        $blocks.Add((New-CippReportParagraph -Html '<p>Our assessment follows globally recognized security standards to ensure your organization meets regulatory requirements and industry benchmarks. This approach helps protect your business assets, maintain customer trust, and reduce operational risks from cyber threats.</p>'))
        $us = $Data.UserStats
        $gaCaption = if ($us.pimCapable) { "$($us.permanentGlobalAdmins) permanent, $($us.eligibleGlobalAdmins) eligible" } else { $null }
        $gaStat = @{ value = "$($us.globalAdmins)"; label = 'Global Admins' }
        if ($gaCaption) { $gaStat.caption = $gaCaption }
        $blocks.Add((New-CippReportStatRow -Title 'Environment Overview' -Stats @(
                    @{ value = "$($us.licensedUsers)"; label = 'Licensed Users' }
                    @{ value = "$($us.unlicensedUsers)"; label = 'Unlicensed Users' }
                    @{ value = "$($us.guests)"; label = 'Guest Users' }
                    $gaStat
                )))
    }

    Hero 'board' $null '83%' $null "of organizations experienced`nmore than one cyberattack`nin the past year" "Proactive security prevents`nrepeated attacks"

    # -- Security Standards --
    if ($cfg.securityStandards -and $Data.SecurityControls -and @($Data.SecurityControls).Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'Security Standards Assessment' -Subtitle 'Detailed evaluation of implemented security standards'))
        $blocks.Add((New-CippReportParagraph -Html '<p>Your security standards have been carefully evaluated against industry best practices to protect your business from cyber threats while ensuring smooth daily operations. These standards help maintain business continuity, protect sensitive data, and meet regulatory requirements that are essential for your industry.</p>'))
        $rows = foreach ($c in $Data.SecurityControls) {
            @{ name = $c.name; description = $c.description; tags = $c.tags; status = $c.status
                tone = @{ Compliant = 'pass'; Partial = 'warn'; Review = 'fail'; 'Review Required' = 'fail' }[$c.status]
            }
        }
        $blocks.Add((New-CippReportTable -Title 'Security Standards Status' -Limit @($Data.SecurityControls).Count -Columns @(
                    @{ header = 'Standard'; key = 'name'; width = 2; bold = $true }
                    @{ header = 'Description'; key = 'description'; width = 4 }
                    @{ header = 'Tags'; key = 'tags'; width = 2 }
                    @{ header = 'Status'; key = 'status'; width = 1.5; toneField = 'tone' }
                ) -Rows @($rows)))
        $blocks.Add((New-CippReportBullets -Title 'Key Recommendations' -Items @(
                    @{ label = 'Immediate Actions:'; text = 'Address standards marked as "Review" to enhance security posture' }
                    @{ label = 'Compliance:'; text = 'Ensure all security standards are properly implemented and maintained' }
                    @{ label = 'Monitoring:'; text = 'Establish regular review cycles for all security standards' }
                    @{ label = 'Training:'; text = 'Implement security awareness programs to reduce human risk factors' }
                )))
    }

    Hero 'glasses' $null '95%' $null "of successful cyber attacks`ncould have been prevented with`nproactive security measures" "Your security resilience is`nour primary mission"

    # -- Microsoft Secure Score --
    if ($cfg.secureScore -and $Data.SecureScore) {
        $ss = $Data.SecureScore
        $blocks.Add((New-CippReportPage -Title 'Microsoft Secure Score' -Subtitle 'Comprehensive security posture measurement and benchmarking'))
        $blocks.Add((New-CippReportParagraph -Html '<p>Microsoft Secure Score measures how well your organization is protected against cyber threats. This score reflects the effectiveness of your current security measures and helps identify areas where additional protection could strengthen your business resilience.</p>'))
        $blocks.Add((New-CippReportStatRow -Title 'Score Comparison' -Stats @(
                    @{ value = "$(if ($null -ne $ss.currentScore) { $ss.currentScore } else { 'N/A' })"; label = 'Current Score' }
                    @{ value = "$(if ($null -ne $ss.maxScore) { $ss.maxScore } else { 'N/A' })"; label = 'Max Score' }
                    @{ value = "$(if ($null -ne $ss.percentageVsSimilar) { $ss.percentageVsSimilar } else { 'N/A' })%"; label = 'vs Similar Orgs' }
                    @{ value = "$(if ($null -ne $ss.percentageVsAllTenants) { $ss.percentageVsAllTenants } else { 'N/A' })%"; label = 'vs All Orgs' }
                )))
        $blocks.Add((New-CippReportHeading -Title '7-Day Score Trend'))
        $blocks.Add((New-CippReportChart -Title 'Secure Score Progress' -Kind trend -Max ([double]$ss.maxScore) -Caption ("Current: {0} / {1} ({2}%)" -f $ss.currentScore, $ss.maxScore, $ss.percentageCurrent) -Data @($ss.trend)))
        $blocks.Add((New-CippReportInfoBox -Title 'What Your Score Means' -Content ("Your current score of {0} represents {1}% of the maximum protection level available. This indicates how well your organization is currently defended against common cyber threats and data breaches." -f $ss.currentScore, $ss.percentageCurrent)))
        $blocks.Add((New-CippReportInfoBox -Title 'Why Scores Change' -Content "- Business growth and new employees may temporarily lower scores until security measures are applied`n- Changes in software licenses can affect available security features`n- New security threats require updated protections, which may impact scores`n- Regular security improvements help maintain and increase your protection level"))
    }

    Hero 'working' 'Every' '39' 'seconds' "a business falls victim to`nransomware attacks" "Proactive defense beats`nreactive recovery"

    # -- License Management --
    if ($cfg.licenseManagement -and $Data.Licenses -and @($Data.Licenses).Count -gt 0) {
        $blocks.Add((New-CippReportPage -Title 'License Management' -Subtitle 'Microsoft 365 license allocation and utilization analysis'))
        $blocks.Add((New-CippReportParagraph -Html '<p>Smart license management helps control costs while ensuring your team has the tools they need to be productive. This analysis shows how your current licenses are being used and identifies opportunities to optimize spending without compromising business operations.</p>'))
        $blocks.Add((New-CippReportTable -Title 'License Allocation Summary' -Limit @($Data.Licenses).Count -Columns @(
                    @{ header = 'License Type'; key = 'name'; width = 5; bold = $true }
                    @{ header = 'Used'; key = 'used'; width = 1.5; align = 'center'; bold = $true }
                    @{ header = 'Available'; key = 'available'; width = 1.5; align = 'center'; bold = $true }
                    @{ header = 'Total'; key = 'total'; width = 1.5; align = 'center'; bold = $true }
                ) -Rows @($Data.Licenses)))
        $blocks.Add((New-CippReportBullets -Title 'License Optimization Recommendations' -Items @(
                    @{ label = 'Usage Monitoring:'; text = 'Track how licenses are being used to identify cost-saving opportunities' }
                    @{ label = 'Cost Control:'; text = 'Review unused licenses to reduce unnecessary spending' }
                    @{ label = 'Growth Planning:'; text = 'Ensure you have enough licenses for business expansion without overspending' }
                    @{ label = 'Regular Reviews:'; text = 'Conduct quarterly reviews to maintain cost-effective license allocation' }
                )))
    }

    Hero 'laptop' $null '$4.45M' $null "average cost of a`ndata breach in 2024" "Investment in security`nsaves millions in recovery"

    # -- Device Management --
    if ($cfg.deviceManagement -and $Data.Devices -and @($Data.Devices).Count -gt 0) {
        $devices = @($Data.Devices)
        $compliant = @($devices | Where-Object { $_.compliant }).Count
        $blocks.Add((New-CippReportPage -Title 'Device Management' -Subtitle 'Device compliance status and management overview'))
        $blocks.Add((New-CippReportParagraph -Html '<p>Managing employee devices is essential for protecting your business data and maintaining productivity. This analysis shows which devices meet your security standards and identifies any that may need attention to prevent data breaches or operational disruptions.</p>'))
        $blocks.Add((New-CippReportStatRow -Title 'Device Compliance Overview' -Stats @(
                    @{ value = "$($devices.Count)"; label = 'Total Devices' }
                    @{ value = "$compliant"; label = 'Compliant' }
                    @{ value = "$($devices.Count - $compliant)"; label = 'Non-Compliant' }
                    @{ value = "$([math]::Round(($compliant / $devices.Count) * 100))%"; label = 'Compliance Rate' }
                )))
        $devRows = foreach ($d in $devices) {
            @{ name = $d.name; os = $d.os; compliance = $d.compliance; lastSync = $d.lastSync
                tone = if ($d.compliant) { 'pass' } else { 'fail' }
            }
        }
        $blocks.Add((New-CippReportTable -Title 'Device Management Summary' -Limit 8 -Columns @(
                    @{ header = 'Device Name'; key = 'name'; width = 3; bold = $true }
                    @{ header = 'OS'; key = 'os'; width = 2; bold = $true }
                    @{ header = 'Compliance'; key = 'compliance'; width = 2; toneField = 'tone' }
                    @{ header = 'Last Sync'; key = 'lastSync'; width = 2; bold = $true }
                ) -Rows @($devRows)))
        $blocks.Add((New-CippReportStatRow -Title 'Device Insights' -Stats @(
                    @{ value = "$(@($devices | Where-Object { $_.os -eq 'Windows' }).Count)"; label = 'Windows Devices' }
                    @{ value = "$(@($devices | Where-Object { $_.os -eq 'iOS' }).Count)"; label = 'iOS Devices' }
                    @{ value = "$(@($devices | Where-Object { $_.os -eq 'Android' }).Count)"; label = 'Android Devices' }
                    @{ value = "$(@($devices | Where-Object { $_.encrypted }).Count)"; label = 'Encrypted' }
                )))
        $blocks.Add((New-CippReportInfoBox -Title 'Device Management Recommendations' -Content 'Keep devices updated and secure to protect business data. Regularly check that all employee devices meet security standards and address any issues promptly. Consider automated policies to maintain consistent security across all devices and conduct regular reviews to identify potential risks.'))
    }

    Hero 'city' $null '277' 'days' "average time to identify and`ncontain a data breach" "Early detection minimizes`nbusiness impact"

    # -- Conditional Access --
    if ($cfg.conditionalAccess -and $Data.CAPolicies -and @($Data.CAPolicies).Count -gt 0) {
        $ca = @($Data.CAPolicies)
        $stateLabel = @{ enabled = 'Enabled'; enabledForReportingButNotEnforced = 'Report Only'; disabled = 'Disabled' }
        $stateTone = @{ enabled = 'pass'; enabledForReportingButNotEnforced = 'warn'; disabled = 'fail' }
        $enabled = @($ca | Where-Object { $_.state -eq 'enabled' }).Count
        $reportOnly = @($ca | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' }).Count
        $mfa = @($ca | Where-Object { $_.controls -contains 'mfa' -or $_.controlsText -eq 'MFA' }).Count
        $blocks.Add((New-CippReportPage -Title 'Conditional Access Policies' -Subtitle 'Identity and access management security controls'))
        $blocks.Add((New-CippReportParagraph -Html '<p>Access control policies help protect your business by ensuring only the right people can access sensitive information under appropriate circumstances. These smart security measures automatically evaluate each access request and apply additional verification when needed, balancing security with employee productivity.</p>'))
        $blocks.Add((New-CippReportParagraph -Title 'How Access Controls Protect Your Business' -Html '<p>These policies work like intelligent security guards, making decisions based on who is trying to access what, from where, and when. For example, accessing email from the office might be seamless, but accessing it from an unusual location might require additional verification. This approach protects your data while minimizing disruption to daily work.</p>'))
        $caRows = foreach ($p in $ca) {
            @{ name = $p.name; state = ($stateLabel[$p.state] ?? $p.state); tone = ($stateTone[$p.state]); applications = $p.applications; controls = $p.controlsText }
        }
        $blocks.Add((New-CippReportTable -Title 'Current Policy Configuration' -Limit 8 -Columns @(
                    @{ header = 'Policy Name'; key = 'name'; width = 4; bold = $true }
                    @{ header = 'State'; key = 'state'; width = 2; toneField = 'tone' }
                    @{ header = 'Applications'; key = 'applications'; width = 2; bold = $true }
                    @{ header = 'Controls'; key = 'controls'; width = 3; bold = $true }
                ) -Rows @($caRows)))
        $blocks.Add((New-CippReportStatRow -Title 'Policy Overview' -Stats @(
                    @{ value = "$($ca.Count)"; label = 'Total Policies' }
                    @{ value = "$enabled"; label = 'Enabled' }
                    @{ value = "$reportOnly"; label = 'Report Only' }
                    @{ value = "$mfa"; label = 'MFA Policies' }
                )))
        $blocks.Add((New-CippReportBullets -Title 'Policy Analysis' -Items @(
                    @{ label = 'Policy Coverage:'; text = "$($ca.Count) conditional access policies configured" }
                    @{ label = 'Enforcement Status:'; text = "$enabled policies actively enforced" }
                    @{ label = 'Testing Phase:'; text = "$reportOnly policies in report-only mode" }
                    @{ label = 'Security Controls:'; text = 'Multi-factor authentication and access blocking implemented' }
                )))
        $caRec = if ($reportOnly -gt 0) { "Consider activating $reportOnly policies currently in testing mode after ensuring they don't disrupt business operations. " } else { 'Your access controls are properly configured. ' }
        $blocks.Add((New-CippReportInfoBox -Title 'Access Control Recommendations' -Content ($caRec + 'Regularly review how these policies affect employee productivity and adjust as needed. Consider additional location-based protections for enhanced security without impacting daily operations.')))
    }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'SECURITY ASSESSMENT'
            covertitle         = 'Executive'
            coveraccent        = 'Summary'
            covertenant        = [string]$tenant
            coversubtitle      = "Security & Compliance Assessment for $tenant"
            coverfallbackimage = '/reportImages/soc.jpg'
            footerlabel        = "$tenant - Executive Summary"
        }
    }
}
