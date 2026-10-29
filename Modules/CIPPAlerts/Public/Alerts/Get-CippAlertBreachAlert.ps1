
function Get-CippAlertBreachAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $TenantFilter
    )
    try {
        $Search = New-BreachTenantSearch -TenantFilter $TenantFilter
        $AlertData = foreach ($Breach in $Search) {
            [PSCustomObject]@{
                Id          = "$($Breach.email)|$($Breach.sources)|$($Breach.Date)" # stable identity; the feed's breach text can be edited
                Message     = "$($Breach.email) was found in the $($Breach.sources) breach ($($Breach.Date))"
                Email       = $Breach.email
                Breach      = $Breach.sources
                BreachDate  = $Breach.Date
                HasPassword = $Breach.has_password
                DataClasses = $Breach.DataClasses -join ', '
                Tenant      = $TenantFilter
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get New Breaches for $($TenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
