function Get-CIPPAlertAppleTerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
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
        $appleterms = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/depOnboardingSettings" -tenantid $TenantFilter
    } catch {
        return
    }

    if ($appleterms.lastSyncErrorCode -eq 3) {
        $AlertData = "New Apple Business Manager terms are ready to accept."
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    }
}
