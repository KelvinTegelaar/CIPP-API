function Invoke-CippTestZTNA23183 {
    <#
    .SYNOPSIS
    Service principals use safe redirect URIs
    #>
    param($Tenant)

    try {
        $ServicePrincipals = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA23183' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Service principals use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
            return
        }

        $TestUri = {
            param([string]$Uri)
            $Issues = [System.Collections.Generic.List[string]]::new()
            if ([string]::IsNullOrWhiteSpace($Uri)) { return $Issues }
            if ($Uri -match '\*') { $Issues.Add('Wildcard URI') }
            if ($Uri -match '^http://(?!localhost(?:[:/]|$))') { $Issues.Add('Plain HTTP (non-localhost)') }
            if ($Uri -match '\.azurewebsites\.net') { $Issues.Add('Azure default *.azurewebsites.net domain') }
            if ($Uri -match '\.cloudapp\.(?:net|azure\.com)') { $Issues.Add('Azure default cloudapp domain') }
            if ($Uri -match '^https?://(?:\d{1,3}\.){3}\d{1,3}') { $Issues.Add('IP-address redirect URI') }
            return $Issues
        }

        # Skip Microsoft-published service principals — these are out of tenant control.
        $TenantSPs = $ServicePrincipals.Where({
                $_.appOwnerOrganizationId -ne 'f8cdef31-a31e-4b4a-93e4-5f571e91255a' -and
                $_.servicePrincipalType -ne 'ManagedIdentity'
            })

        $Failed = [System.Collections.Generic.List[object]]::new()
        foreach ($SP in $TenantSPs) {
            $AllIssues = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($Uri in @($SP.replyUrls)) {
                foreach ($Reason in (& $TestUri $Uri)) {
                    $AllIssues.Add(@{ Uri = $Uri; Reason = $Reason })
                }
            }
            if ($AllIssues.Count -gt 0) {
                $Failed.Add([PSCustomObject]@{
                        Sp     = $SP
                        Issues = $AllIssues
                    })
            }
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($Failed.Count -eq 0) {
            $Status = 'Passed'
            $Lines.Add("All $($TenantSPs.Count) tenant-owned service principal(s) use safe reply URLs.")
        } else {
            $Status = 'Failed'
            $Lines.Add("$($Failed.Count) of $($TenantSPs.Count) service principal(s) have unsafe reply URLs.")
            $Lines.Add('')
            $Lines.Add('| Service Principal | Issue | URI |')
            $Lines.Add('| :---------------- | :---- | :-- |')
            $RowCount = 0
            foreach ($Entry in $Failed) {
                foreach ($Issue in $Entry.Issues) {
                    if ($RowCount -ge 50) { break }
                    $Lines.Add("| $($Entry.Sp.displayName) | $($Issue.Reason) | $($Issue.Uri) |")
                    $RowCount++
                }
                if ($RowCount -ge 50) { break }
            }
            $Lines.Add('')
            $Lines.Add('**Remediation:** Remove unsafe reply URLs from each affected service principal. Use only HTTPS URIs that you own with proper DNS — avoid wildcards, IPs, and shared Azure default domains.')
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA23183' -TestType 'Identity' -Status $Status -ResultMarkdown ($Lines -join "`n") -Risk 'High' -Name 'Service principals use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA23183' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Service principals use safe redirect URIs' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application Management'
    }
}
