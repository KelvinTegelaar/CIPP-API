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

    #Add rerun protection: This Monitor can only run once every hour.
    $Rerun = Test-CIPPRerun -TenantFilter $TenantFilter -Type 'ExchangeMonitor' -API 'Get-CIPPAlertQuarantineReleaseRequests'
    if ($Rerun) {
        return $true
    }
    $HasLicense = Test-CIPPStandardLicense -StandardName 'QuarantineReleaseRequests' -TenantFilter $TenantFilter -RequiredCapabilities @(
        'EXCHANGE_S_STANDARD',
        'EXCHANGE_S_ENTERPRISE',
        'EXCHANGE_S_STANDARD_GOV',
        'EXCHANGE_S_ENTERPRISE_GOV',
        'EXCHANGE_LITE'
    )

    if (-not $HasLicense) {
        return $true
    }

    try {
        $cmdParams = @{
            PageSize          = 1000
            ReleaseStatus     = 'Requested'
            StartReceivedDate = (Get-Date).AddHours(-6)
            EndReceivedDate   = (Get-Date).AddHours(0)
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
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "QuarantineReleaseRequests: $(Get-NormalizedError -message $_.Exception.Message)" -sev Error
    }
}
