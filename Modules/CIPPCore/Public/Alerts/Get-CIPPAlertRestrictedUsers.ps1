function Get-CIPPAlertRestrictedUsers {
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

    try {
        $BlockedUsers = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-BlockedSenderAddress'

        if ($BlockedUsers) {
            $AlertData = foreach ($User in $BlockedUsers) {
                # Parse the reason to make it more readable
                $ReasonParts = $User.Reason -split ';'
                $LimitType = ($ReasonParts | Where-Object { $_ -like 'ExceedingLimitType=*' }) -replace 'ExceedingLimitType=', ''
                $InternalCount = ($ReasonParts | Where-Object { $_ -like 'InternalRecipientCountToday=*' }) -replace 'InternalRecipientCountToday=', ''
                $ExternalCount = ($ReasonParts | Where-Object { $_ -like 'ExternalRecipientCountToday=*' }) -replace 'ExternalRecipientCountToday=', ''

                [PSCustomObject]@{
                    SenderAddress   = $User.SenderAddress
                    Message         = "User $($User.SenderAddress) is restricted from sending email. Block type: $($LimitType ?? 'Unknown'). Created: $($User.CreatedDatetime)"
                    BlockType       = if ($LimitType) { "$LimitType recipient limit exceeded" } else { 'Email sending limit exceeded' }
                    TemporaryBlock  = $User.TemporaryBlock
                    InternalCount   = $InternalCount
                    ExternalCount   = $ExternalCount
                    CreatedDatetime = $User.CreatedDatetime
                    Reason          = $User.Reason
                    Tenant          = $TenantFilter
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
       # Write-LogMessage -tenant $($TenantFilter) -message "Could not get restricted users for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -severity 'Error' -API 'Get-CIPPAlertRestrictedUsers' -LogData (Get-CippException -Exception $_)
    }
}
