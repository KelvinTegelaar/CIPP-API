function Invoke-CippTestZTNA21844 {
    <#
    .SYNOPSIS
    Block legacy Azure AD PowerShell module
    #>
    param($Tenant)

    $TestId = 'ZTNA21844'
    #Tested
    try {
        # Azure AD PowerShell App ID
        $AzureADPowerShellAppId = '1b730954-1685-4b74-9bfd-dac224a7b894'

        # Query for the Azure AD PowerShell service principal
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        $ServicePrincipal = $ServicePrincipals | Where-Object { $_.appId -eq $AzureADPowerShellAppId }

        $InvestigateStatus = $false
        $AppName = 'Azure AD PowerShell'
        $Passed = 'Failed'

        if (-not $ServicePrincipal -or $ServicePrincipal.Count -eq 0) {
            $SummaryLines = @(
                'Summary',
                '',
                "- $AppName (Enterprise App not found in tenant)",
                '- Sign in disabled: N/A',
                '',
                "$AppName has not been blocked by the organization."
            )
        } else {
            $SP = $ServicePrincipal[0]
            $PortalLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($SP.id)/appId/$($SP.appId)"
            $ServicePrincipalMarkdown = "[$AppName]($PortalLink)"

            if ($SP.accountEnabled -eq $false) {
                $Passed = 'Passed'
                $SummaryLines = @(
                    'Summary',
                    '',
                    "- $ServicePrincipalMarkdown",
                    '- Sign in disabled: Yes',
                    '',
                    "$AppName is blocked in the tenant by turning off user sign in to the Azure Active Directory PowerShell Enterprise Application."
                )
            } elseif ($SP.appRoleAssignmentRequired -eq $true) {
                $InvestigateStatus = $true
                $SummaryLines = @(
                    'Summary',
                    '',
                    "- $ServicePrincipalMarkdown",
                    '- Sign in disabled: No',
                    '- User assignment required: Yes',
                    '',
                    "App role assignment is required for $AppName. Review assignments and confirm that the app is inaccessible to users."
                )
            } else {
                $SummaryLines = @(
                    'Summary',
                    '',
                    "- $ServicePrincipalMarkdown",
                    '- Sign in disabled: No',
                    '',
                    "$AppName has not been blocked by the organization."
                )
            }
        }

        $ResultMarkdown = $SummaryLines -join "`n"

        if ($InvestigateStatus) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Block legacy Azure AD PowerShell module' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access control'
        } else {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Block legacy Azure AD PowerShell module' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access control'
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Block legacy Azure AD PowerShell module' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access control'
    }
}
