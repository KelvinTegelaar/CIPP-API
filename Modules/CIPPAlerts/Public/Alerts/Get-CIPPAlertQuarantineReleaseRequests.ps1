function Get-CIPPAlertQuarantineReleaseRequests {
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

    $HasLicense = Test-CIPPStandardLicense -StandardName 'QuarantineReleaseRequests' -TenantFilter $TenantFilter -Preset Exchange

    if (-not $HasLicense) {
        return
    }

    try {
        # EXO can only filter on when the message was received, not when release was requested, and users
        # often ask days after the message was quarantined. Cover the full 30 days EXO allows so every
        # pending request is seen; Write-AlertTrace keeps an already-alerted request from re-alerting.
        $cmdParams = @{
            PageSize          = 1000
            ReleaseStatus     = 'Requested'
            StartReceivedDate = (Get-Date).AddDays(-30)
            EndReceivedDate   = (Get-Date)
        }
        $RequestedReleases = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams $cmdParams -ErrorAction Stop | Select-Object -ExcludeProperty *data.type* | Sort-Object -Property ReceivedTime

        if ($RequestedReleases) {
            # Get the CIPP URL for the Quarantine link
            $CippConfigTable = Get-CippTable -tablename Config
            $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
            $CIPPUrl = 'https://{0}' -f $CippConfig.Value

            $AlertData = foreach ($Message in $RequestedReleases) {
                [PSCustomObject]@{
                    Identity          = $Message.Identity
                    MessageId         = $Message.MessageId
                    Subject           = $Message.Subject
                    SenderAddress     = $Message.SenderAddress
                    RecipientAddress  = $Message.RecipientAddress -join '; '
                    Type              = $Message.Type
                    PolicyName        = $Message.PolicyName
                    ReleaseStatus     = $Message.ReleaseStatus
                    ReceivedTime      = $Message.ReceivedTime
                    QuarantineViewUrl = "$CIPPUrl/email/administration/quarantine?tenantFilter=$TenantFilter"
                    Tenant            = $TenantFilter
                }
            }
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "QuarantineReleaseRequests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
