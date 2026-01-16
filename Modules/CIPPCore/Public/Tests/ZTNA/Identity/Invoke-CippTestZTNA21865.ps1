function Invoke-CippTestZTNA21865 {
    <#
    .SYNOPSIS
    Named locations are configured
    #>
    param($Tenant)

    $TestId = 'ZTNA21865'
    #tested
    try {
        $NamedLocations = New-CIPPDbRequest -TenantFilter $Tenant -Type 'NamedLocations'

        if (-not $NamedLocations) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Named locations are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
            return
        }

        $TrustedLocations = @($NamedLocations | Where-Object { $_.isTrusted -eq $true })
        $Passed = $TrustedLocations.Count -gt 0

        if ($Passed) {
            $ResultMarkdown = "✅ Trusted named locations are configured.`n`n"
        } else {
            $ResultMarkdown = "❌ No trusted named locations configured.`n`n"
        }

        $ResultMarkdown += "## Named Locations`n`n"
        $ResultMarkdown += "$($NamedLocations.Count) named locations found.`n`n"

        if ($NamedLocations.Count -gt 0) {
            $ResultMarkdown += "| Name | Type | Trusted |`n"
            $ResultMarkdown += "| :--- | :--- | :------ |`n"

            foreach ($Location in $NamedLocations) {
                $Name = $Location.displayName
                $Type = if ($Location.'@odata.type' -eq '#microsoft.graph.ipNamedLocation') { 'IP-based' }
                elseif ($Location.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') { 'Country-based' }
                else { 'Unknown' }
                $Trusted = if ($Location.isTrusted) { 'Yes' } else { 'No' }
                $ResultMarkdown += "| $Name | $Type | $Trusted |`n"
            }
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Named locations are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Named locations are configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application management'
    }
}
