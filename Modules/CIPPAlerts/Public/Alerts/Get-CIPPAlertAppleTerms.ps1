function Get-CIPPAlertAppleTerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    # 0 = Expired
    # 1 = expired?
    # 2 = unknown
    # 3 = Terms & Conditions
    # 4 = Warning

    try {
        Write-Host "Checking Apple Terms for $($TenantFilter)"
        $AppleTerms = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter
    } catch {
        return
    }

    if ($AppleTerms.lastSyncErrorCode -eq 3) {
        $AlertData = [PSCustomObject]@{
            Message                    = 'New Apple Business Manager terms are ready to accept.'
            AppleIdentifier            = $AppleTerms.appleIdentifier
            TokenName                  = $AppleTerms.tokenName
            TokenExpirationDateTime    = $AppleTerms.tokenExpirationDateTime
            LastSyncErrorCode          = $AppleTerms.lastSyncErrorCode
            LastSuccessfulSyncDateTime = $AppleTerms.lastSuccessfulSyncDateTime
            LastSyncTriggeredDateTime  = $AppleTerms.lastSyncTriggeredDateTime
            Tenant                     = $TenantFilter
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    }
}
