function Invoke-CIPPStandardLegacyEmailReportAddins {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) LegacyEmailReportAddins
    .SYNOPSIS
        (Label) Remove legacy Outlook Report add-ins
    .DESCRIPTION
        (Helptext) Removes legacy Report Phishing and Report Message Outlook add-ins.
        (DocsDescription) Removes legacy Report Phishing and Report Message Outlook add-ins.
    .NOTES
        CAT
            Exchange Standards
        TAG
        EXECUTIVETEXT
            The legacy Report Phishing and Report Message Outlook add-ins are security issues with the add-in which makes them unsafe for the organization.
        IMPACT
            Low Impact
        ADDEDDATE
            2025-08-26
        POWERSHELLEQUIVALENT
            None
        RECOMMENDEDBY
            "Microsoft"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)

    # Define the legacy add-ins to remove
    $LegacyAddins = @(
        @{
            AssetId   = 'WA200002469'
            ProductId = '3f32746a-0586-4c54-b8ce-d3b611c5b6c8'
            Name      = 'Report Phishing'
        },
        @{
            AssetId   = 'WA104381180'
            ProductId = '6046742c-3aee-485e-a4ac-92ab7199db2e'
            Name      = 'Report Message'
        }
    )

    try {
        $CurrentApps = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications&select=addins" -TenantID $Tenant

        # Filter to only applications that have the legacy add-ins we're looking for
        $LegacyProductIds = $LegacyAddins | ForEach-Object { $_.ProductId }
        $InstalledApps = $CurrentApps | Where-Object {
            $app = $_
            $app.addIns | Where-Object { $_.id -in $LegacyProductIds }
        }
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Retrieved $($InstalledApps.Count) applications with legacy add-ins" -Sev Info
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the installed add-ins for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $InstalledLegacyAddins = [System.Collections.Generic.List[string]]::new()

    foreach ($App in $InstalledApps) {
        foreach ($Addin in $App.addIns) {
            $LegacyAddin = $LegacyAddins | Where-Object { $_.ProductId -eq $Addin.id }
            if ($LegacyAddin) {
                $InstalledLegacyAddins.Add($LegacyAddin.Name)
            }
        }
    }

    $StateIsCorrect = ($InstalledApps.Count -eq 0)
    $RemediationPerformed = $false

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Legacy Email Report Add-ins are already removed.' -Sev Info
        } else {
            foreach ($App in $InstalledApps) {
                try {
                    # Delete the application object using Graph API
                    $GraphRequest = @{
                        tenantID = $Tenant
                        uri      = "https://graph.microsoft.com/beta/applications/$($App.id)"
                        Type     = 'DELETE'
                    }

                    $null = New-GraphPostRequest @GraphRequest

                    $RemovedAddins = foreach ($Addin in $App.addIns) {
                        $LegacyAddin = $LegacyAddins | Where-Object { $_.ProductId -eq $Addin.id }
                        if ($LegacyAddin) { $LegacyAddin.Name }
                    }

                    $RemovedAddinsText = $RemovedAddins -join ', '
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Successfully removed legacy add-in(s): $RemovedAddinsText (deleted application $($App.displayName))" -Sev Info
                    $RemediationPerformed = $true
                } catch {
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to remove application $($App.displayName)" -Sev Error -LogData $_
                }
            }
        }
    }

    # If we performed remediation and need to report/alert, get fresh state
    if ($RemediationPerformed -and ($Settings.alert -eq $true -or $Settings.report -eq $true)) {
        try {
            $FreshApps = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications&select=addins" -TenantID $Tenant
            $LegacyProductIds = $LegacyAddins | ForEach-Object { $_.ProductId }
            $FreshInstalledApps = $FreshApps | Where-Object {
                $app = $_
                $app.addIns | Where-Object { $_.id -in $LegacyProductIds }
            }

            # Check fresh state
            $FreshInstalledLegacyAddins = [System.Collections.Generic.List[string]]::new()
            foreach ($LegacyAddin in $LegacyAddins) {
                $InstalledAddin = $FreshInstalledApps | Where-Object {
                    $_.addIns | Where-Object { $_.id -eq $LegacyAddin.ProductId }
                }
                if ($InstalledAddin) {
                    $FreshInstalledLegacyAddins.Add($LegacyAddin.Name)
                }
            }

            # Use fresh state for reporting/alerting
            $StateIsCorrect = ($FreshInstalledLegacyAddins.Count -eq 0)
            $InstalledLegacyAddins = $FreshInstalledLegacyAddins
        } catch {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get fresh add-in state after remediation for $Tenant" -Sev Warning
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Legacy Email Report Add-ins are not installed.' -sev Info
        } else {
            $InstalledAddinsText = ($InstalledLegacyAddins -join ', ')
            Write-StandardsAlert -message "Legacy Email Report Add-ins are still installed: $InstalledAddinsText" -tenant $tenant -standardName 'LegacyEmailReportAddins' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Legacy Email Report Add-ins are still installed: $InstalledAddinsText" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            InstalledLegacyAddins = $InstalledLegacyAddins
        }
        $ExpectedValue = @{
            InstalledLegacyAddins = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.LegacyEmailReportAddins' -Tenant $Tenant -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue
        Add-CIPPBPAField -FieldName 'LegacyEmailReportAddins' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
