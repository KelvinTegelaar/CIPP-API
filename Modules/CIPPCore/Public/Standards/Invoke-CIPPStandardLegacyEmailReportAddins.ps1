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
            AssetId = 'WA200002469'
            ProductId = '3f32746a-0586-4c54-b8ce-d3b611c5b6c8'
            Name = 'Report Phishing'
        },
        @{
            AssetId = 'WA104381180'
            ProductId = '6046742c-3aee-485e-a4ac-92ab7199db2e'
            Name = 'Report Message'
        }
    )

    try {
        $CurrentApps = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/fd/addins/api/apps?workloads=AzureActiveDirectory,WXPO,MetaOS,Teams,SharePoint'
        $InstalledApps = $CurrentApps.apps
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the installed add-ins for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Check which legacy add-ins are currently installed
    $AddinsToRemove = [System.Collections.Generic.List[PSCustomObject]]::new()
    $InstalledLegacyAddins = [System.Collections.Generic.List[string]]::new()

    foreach ($LegacyAddin in $LegacyAddins) {
        $InstalledAddin = $InstalledApps | Where-Object { $_.assetId -eq $LegacyAddin.AssetId -or $_.productId -eq $LegacyAddin.ProductId }
        if ($InstalledAddin) {
            $InstalledLegacyAddins.Add($LegacyAddin.Name)
            $AddinsToRemove.Add([PSCustomObject]@{
                AppsourceAssetID = $LegacyAddin.AssetId
                ProductID = $LegacyAddin.ProductId
                Command = 'UNDEPLOY'
                Workload = 'WXPO'
            })
        }
    }

    $StateIsCorrect = ($AddinsToRemove.Count -eq 0)
    $RemediationPerformed = $false

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Legacy Email Report Add-ins are already removed.' -Sev Info
        } else {
            foreach ($AddinToRemove in $AddinsToRemove) {
                try {
                    $Body = @{
                        Locale = 'en-US'
                        WorkloadManagementList = @($AddinToRemove)
                    } | ConvertTo-Json -Depth 10 -Compress

                    $GraphRequest = @{
                        tenantID = $Tenant
                        uri = 'https://admin.microsoft.com/fd/addins/api/apps'
                        scope = 'https://admin.microsoft.com/.default'
                        AsApp = $false
                        Type = 'POST'
                        ContentType = 'application/json; charset=utf-8'
                        Body = $Body
                    }

                    $Response = New-GraphPostRequest @GraphRequest
                    $AddinName = ($LegacyAddins | Where-Object { $_.AssetId -eq $AddinToRemove.AppsourceAssetID }).Name
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Successfully initiated removal of $AddinName add-in" -Sev Info
                    $RemediationPerformed = $true
                } catch {
                    $AddinName = ($LegacyAddins | Where-Object { $_.AssetId -eq $AddinToRemove.AppsourceAssetID }).Name
                    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to remove $AddinName add-in" -Sev Error -LogData $_
                }
            }
        }
    }

    # If we performed remediation and need to report/alert, get fresh state
    if ($RemediationPerformed -and ($Settings.alert -eq $true -or $Settings.report -eq $true)) {
        try {
            $FreshApps = New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -TenantID $Tenant -Uri 'https://admin.microsoft.com/fd/addins/api/apps?workloads=AzureActiveDirectory,WXPO,MetaOS,Teams,SharePoint'
            $FreshInstalledApps = $FreshApps.apps

            # Check fresh state
            $FreshInstalledLegacyAddins = [System.Collections.Generic.List[string]]::new()
            foreach ($LegacyAddin in $LegacyAddins) {
                $InstalledAddin = $FreshInstalledApps | Where-Object { $_.assetId -eq $LegacyAddin.AssetId -or $_.productId -eq $LegacyAddin.ProductId }
                if ($InstalledAddin) {
                    $FreshInstalledLegacyAddins.Add($LegacyAddin.Name)
                }
            }

            # Use fresh state for reporting/alerting
            $StateIsCorrect = ($FreshInstalledLegacyAddins.Count -eq 0)
            $InstalledLegacyAddins = $FreshInstalledLegacyAddins
        }
        catch {
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
        $ReportData = if ($StateIsCorrect) {
            $true
        } else {
            @{
                InstalledLegacyAddins = $InstalledLegacyAddins
                Status = 'Legacy add-ins still installed'
            }
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.LegacyEmailReportAddins' -FieldValue $ReportData -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'LegacyEmailReportAddins' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }
}
