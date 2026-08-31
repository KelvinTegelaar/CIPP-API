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
        # The received-date window has to be wide enough to catch a release request raised some time after
        # the message was quarantined. The old 6-hour window missed most of them; a one-day window suits an
        # hourly-scheduled alert. (The Quarantine page applies no received-date filter, which is why the
        # request is visible there while no webhook or email is ever sent.)
        $cmdParams = @{
            PageSize          = 1000
            ReleaseStatus     = 'Requested'
            StartReceivedDate = (Get-Date).AddDays(-1)
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

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "QuarantineReleaseRequests: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
