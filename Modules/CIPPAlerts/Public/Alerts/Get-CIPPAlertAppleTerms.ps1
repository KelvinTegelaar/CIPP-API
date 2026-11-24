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
        Write-Information "Checking Apple Terms for $($TenantFilter)"
        $AppleTerms = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings' -tenantid $TenantFilter
    } catch {
        return
    }

    $AlertData = foreach ($Token in $AppleTerms) {
        if ($Token.lastSyncErrorCode -ne 3) { continue }
        [PSCustomObject]@{
            Message                    = 'New Apple Business Manager terms are ready to accept.'
            AppleIdentifier            = $Token.appleIdentifier
            TokenName                  = $Token.tokenName
            TokenExpirationDateTime    = $Token.tokenExpirationDateTime
            LastSyncErrorCode          = $Token.lastSyncErrorCode
            LastSuccessfulSyncDateTime = $Token.lastSuccessfulSyncDateTime
            LastSyncTriggeredDateTime  = $Token.lastSyncTriggeredDateTime
            Tenant                     = $TenantFilter
        }
    }
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
