function Invoke-ListCopilotUsage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Returns Microsoft 365 Copilot usage reports for a tenant, flattened into table rows.
        Type=Adoption  -> getMicrosoft365CopilotUserCountSummary (per-product enabled vs active users)
        Type=Trend     -> getMicrosoft365CopilotUserCountTrend    (per-date active/enabled users)
        Type=UserDetail-> getMicrosoft365CopilotUsageUserDetail   (per-user last activity per app)
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Type = $Request.Query.Type ?? $Request.Body.Type ?? 'Adoption'
    $Period = $Request.Query.period ?? $Request.Body.period ?? 'D30'

    # Copilot usage reports support delegated auth with Reports.Read.All (granted to the SAM app);
    # CIPP's delegated identity carries the required usage-reports role via GDAP.
    try {
        switch ($Type) {
            'UserDetail' {
                $Uri = "https://graph.microsoft.com/beta/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='$Period')?`$format=application/json"
                $Report = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                $Results = foreach ($User in $Report) {
                    [PSCustomObject]@{
                        userPrincipalName = $User.userPrincipalName
                        displayName       = $User.displayName
                        lastActivityDate  = $User.lastActivityDate
                        copilotChat       = $User.copilotChatLastActivityDate
                        teams             = $User.microsoftTeamsCopilotLastActivityDate
                        word              = $User.wordCopilotLastActivityDate
                        excel             = $User.excelCopilotLastActivityDate
                        powerPoint        = $User.powerPointCopilotLastActivityDate
                        outlook           = $User.outlookCopilotLastActivityDate
                        oneNote           = $User.oneNoteCopilotLastActivityDate
                        loop              = $User.loopCopilotLastActivityDate
                    }
                }
            }
            'Trend' {
                $Uri = "https://graph.microsoft.com/beta/copilot/reports/getMicrosoft365CopilotUserCountTrend(period='$Period')?`$format=application/json"
                $Report = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                $Results = foreach ($Entry in $Report) {
                    foreach ($Day in $Entry.adoptionByDate) {
                        [PSCustomObject]@{
                            reportDate        = $Day.reportDate
                            anyAppActive      = $Day.anyAppActiveUsers
                            anyAppEnabled     = $Day.anyAppEnabledUsers
                            teamsActive       = $Day.microsoftTeamsActiveUsers
                            wordActive        = $Day.wordActiveUsers
                            excelActive       = $Day.excelActiveUsers
                            powerPointActive  = $Day.powerPointActiveUsers
                            outlookActive     = $Day.outlookActiveUsers
                            oneNoteActive     = $Day.oneNoteActiveUsers
                            loopActive        = $Day.loopActiveUsers
                            copilotChatActive = $Day.copilotChatActiveUsers
                        }
                    }
                }
            }
            default {
                # Adoption (by product) - getMicrosoft365CopilotUserCountSummary
                $Uri = "https://graph.microsoft.com/beta/copilot/reports/getMicrosoft365CopilotUserCountSummary(period='$Period')?`$format=application/json"
                $Report = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter
                $Adoption = ($Report | Select-Object -First 1).adoptionByProduct | Select-Object -First 1
                $ProductMap = [ordered]@{
                    'Any App'         = 'anyApp'
                    'Microsoft Teams' = 'microsoftTeams'
                    'Word'            = 'word'
                    'Excel'           = 'excel'
                    'PowerPoint'      = 'powerPoint'
                    'Outlook'         = 'outlook'
                    'OneNote'         = 'oneNote'
                    'Loop'            = 'loop'
                    'Copilot Chat'    = 'copilotChat'
                }
                $Results = foreach ($Product in $ProductMap.Keys) {
                    $Prefix = $ProductMap[$Product]
                    [PSCustomObject]@{
                        product      = $Product
                        enabledUsers = $Adoption."$($Prefix)EnabledUsers"
                        activeUsers  = $Adoption."$($Prefix)ActiveUsers"
                    }
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CopilotUsage' -tenant $TenantFilter -message "Failed to retrieve Copilot usage report ($Type). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::OK
        $Results = @()
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
