function Invoke-CippTestZTNA21885 {
    <#
    .SYNOPSIS
    App registrations use safe redirect URIs
    #>
    param($Tenant)

    try {
        $Apps = Get-CIPPTestData -TenantFilter $Tenant -Type 'Apps'

        if (-not $Apps) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21885' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'App registrations use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
            return
        }

        # Returns array of {Reason, Uri} entries for any unsafe URI on the app.
        $TestUri = {
            param([string]$Uri, [string]$Section)
            $Issues = [System.Collections.Generic.List[hashtable]]::new()
            if ([string]::IsNullOrWhiteSpace($Uri)) { return $Issues }
            if ($Uri -match '\*') { $Issues.Add(@{ Reason = 'Wildcard URI'; Uri = $Uri; Section = $Section }) }
            if ($Uri -match '^http://(?!localhost(?:[:/]|$))') { $Issues.Add(@{ Reason = 'Plain HTTP (non-localhost)'; Uri = $Uri; Section = $Section }) }
            if ($Uri -match '\.azurewebsites\.net') { $Issues.Add(@{ Reason = 'Azure default *.azurewebsites.net domain (subject to subdomain takeover)'; Uri = $Uri; Section = $Section }) }
            if ($Uri -match '\.cloudapp\.(?:net|azure\.com)') { $Issues.Add(@{ Reason = 'Azure default cloudapp domain'; Uri = $Uri; Section = $Section }) }
            if ($Uri -match '^https?://(?:\d{1,3}\.){3}\d{1,3}') { $Issues.Add(@{ Reason = 'IP-address redirect URI'; Uri = $Uri; Section = $Section }) }
            return $Issues
        }

        $Failed = [System.Collections.Generic.List[object]]::new()
        $Inspected = 0

        foreach ($App in $Apps) {
            $Inspected++
            $AllIssues = [System.Collections.Generic.List[hashtable]]::new()

            foreach ($Uri in @($App.web.redirectUris)) {
                (& $TestUri $Uri 'web').ForEach({ $AllIssues.Add($_) })
            }
            foreach ($Uri in @($App.spa.redirectUris)) {
                (& $TestUri $Uri 'spa').ForEach({ $AllIssues.Add($_) })
            }
            # publicClient is allowed to use localhost / loopback, so only flag wildcards / azurewebsites.
            foreach ($Uri in @($App.publicClient.redirectUris)) {
                if ([string]::IsNullOrWhiteSpace($Uri)) { continue }
                if ($Uri -match '\*') { $AllIssues.Add(@{ Reason = 'Wildcard URI'; Uri = $Uri; Section = 'publicClient' }) }
                if ($Uri -match '\.azurewebsites\.net') { $AllIssues.Add(@{ Reason = 'Azure default domain'; Uri = $Uri; Section = 'publicClient' }) }
            }

            if ($AllIssues.Count -gt 0) {
                $Failed.Add([PSCustomObject]@{
                        App    = $App
                        Issues = $AllIssues
                    })
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Failed.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $Inspected application(s) use safe redirect URIs.")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($Failed.Count) of $Inspected application(s) have unsafe redirect URIs.")
            $Lines.Add('')
            $Lines.Add('| App | Section | Issue | URI |')
            $Lines.Add('| :-- | :------ | :---- | :-- |')
            $RowCount = 0
            foreach ($Entry in $Failed) {
                foreach ($Issue in $Entry.Issues) {
                    if ($RowCount -ge 50) { break }
                    $Lines.Add("| $($Entry.App.displayName) | $($Issue.Section) | $($Issue.Reason) | $($Issue.Uri) |")
                    $RowCount++
                }
                if ($RowCount -ge 50) { break }
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Use only HTTPS URIs that you own and that have proper DNS. Avoid wildcards, IP addresses, and shared Azure default domains (*.azurewebsites.net, *.cloudapp.net) which are vulnerable to subdomain takeover.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21885' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'High' -Name 'App registrations use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21885' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'App registrations use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
    }
}
