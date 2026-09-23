function Get-CIPPAlertNewRiskyUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        # Opt-in: run the default BEC containment for users that newly appear at high risk.
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    $ContainHighRiskUsers = ($InputValue -eq $true -or [string]$InputValue -eq 'true')
    $Deltatable = Get-CIPPTable -Table DeltaCompare
    try {
        # Check if tenant has P2 capabilities
        $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter
        if (-not ($Capabilities.AAD_PREMIUM_P2 -eq $true)) {
            Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message 'Tenant does not have Azure AD Premium P2 licensing required for risky users detection' -sev Warning
            return
        }

        $Filter = "PartitionKey eq 'RiskyUsersDelta' and RowKey eq '{0}'" -f $TenantFilter
        $RiskyUsersDelta = (Get-CIPPAzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue

        # Get current risky users with more detailed information
        $NewDelta = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyUsers?`$top=500' -tenantid $TenantFilter) | Select-Object userPrincipalName, riskLevel, riskState, riskDetail, riskLastUpdatedDateTime, isProcessing, history

        $NewDeltatoSave = $NewDelta | ConvertTo-Json -Depth 10 -Compress -ErrorAction SilentlyContinue | Out-String
        $DeltaEntity = @{
            PartitionKey = 'RiskyUsersDelta'
            RowKey       = [string]$TenantFilter
            delta        = "$NewDeltatoSave"
        }
        Add-CIPPAzDataTableEntity @DeltaTable -Entity $DeltaEntity -Force

        if ($RiskyUsersDelta) {
            $AlertData = $NewDelta | Where-Object { $_.userPrincipalName -notin $RiskyUsersDelta.userPrincipalName } | ForEach-Object {
                $RiskHistory = if ($_.history) {
                    $latestHistory = $_.history | Sort-Object -Property riskLastUpdatedDateTime -Descending | Select-Object -First 1
                    "Previous Risk Level: $($latestHistory.riskLevel), Last Updated: $($latestHistory.riskLastUpdatedDateTime)"
                } else {
                    'No previous risk history'
                }

                # Map risk level to severity
                $Severity = switch ($_.riskLevel) {
                    'high' { 'Critical' }
                    'medium' { 'Warning' }
                    'low' { 'Info' }
                    default { 'Info' }
                }

                # Opt-in auto-containment: the default six-step BEC containment for a user that is
                # newly at high risk and still at risk. Automation confirms the Critical actions by
                # design; the password never enters the alert payload.
                $Containment = $null
                if ($ContainHighRiskUsers -and $_.riskLevel -eq 'high' -and $_.riskState -eq 'atRisk') {
                    $RiskyUpn = $_.userPrincipalName
                    try {
                        $Rows = Invoke-CIPPBecContainment -TenantFilter $TenantFilter -UserPrincipalName $RiskyUpn -Confirmed -Redacted -Headers 'Alert Engine' -APIName 'Alert Engine'
                        $Containment = @(foreach ($Row in @($Rows)) { "$($Row.Action) ($($Row.state)): $($Row.resultText)" }) -join '; '
                        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Auto-contained high-risk user $RiskyUpn (NewRiskyUsers alert)" -sev Info
                    } catch {
                        $Containment = "Auto-containment failed: $($_.Exception.Message)"
                        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Auto-containment of high-risk user $RiskyUpn failed: $($_.Exception.Message)" -sev Error
                    }
                }

                [PSCustomObject]@{
                    Message = "New risky user detected: $($_.userPrincipalName)$(if ($Containment) { ' - BEC containment executed' })"
                    Details = @{
                        RiskLevel    = $_.riskLevel
                        RiskState    = $_.riskState
                        RiskDetail   = $_.riskDetail
                        LastUpdated  = $_.riskLastUpdatedDateTime
                        IsProcessing = $_.isProcessing
                        RiskHistory  = $RiskHistory
                        Severity     = $Severity
                        Containment  = $Containment
                    }
                    Tenant  = $TenantFilter
                }
            }
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get risky users for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
