function Get-CIPPAlertNewRiskyUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $TenantFilter
    )
    $Deltatable = Get-CIPPTable -Table DeltaCompare
    try {
        # Check if tenant has P2 capabilities
        $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter
        if (-not ($Capabilities.AAD_PREMIUM_P2 -eq $true)) {
            Write-AlertMessage -tenant $($TenantFilter) -message 'Tenant does not have Azure AD Premium P2 licensing required for risky users detection'
            return
        }

        $Filter = "PartitionKey eq 'RiskyUsersDelta' and RowKey eq '{0}'" -f $TenantFilter
        $RiskyUsersDelta = (Get-CIPPAzDataTableEntity @Deltatable -Filter $Filter).delta | ConvertFrom-Json -ErrorAction SilentlyContinue

        # Get current risky users with more detailed information
        $NewDelta = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyUsers' -tenantid $TenantFilter) | Select-Object userPrincipalName, riskLevel, riskState, riskDetail, riskLastUpdatedDateTime, isProcessing, history

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

                [PSCustomObject]@{
                    Message = "New risky user detected: $($_.userPrincipalName)"
                    Details = @{
                        RiskLevel    = $_.riskLevel
                        RiskState    = $_.riskState
                        RiskDetail   = $_.riskDetail
                        LastUpdated  = $_.riskLastUpdatedDateTime
                        IsProcessing = $_.isProcessing
                        RiskHistory  = $RiskHistory
                        Severity     = $Severity
                    }
                    Tenant  = $TenantFilter
                }
            }

            if ($AlertData) {
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get risky users for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
